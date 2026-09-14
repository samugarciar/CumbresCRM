-- =====================================================================
-- Fase 3-A — Requerimientos y cruce contra el catálogo.
--
-- ESTO ES LO QUE KOMMO NO PUEDE DAR
-- Kommo sabe en qué etapa está un lead. No sabe qué busca, porque no
-- tiene el catálogo. Aquí sí: la misma base guarda los 81 inmuebles
-- disponibles y las 1.810 búsquedas que el bot ya hizo por la gente.
--
-- EL REQUERIMIENTO NO HAY QUE TECLEARLO: YA EXISTE
-- Cada vez que el agente llama a `buscar_inmuebles`, sus filtros quedan
-- en agente_comercial_mensajes.herramientas_usadas. Eso ES el
-- requerimiento, dicho por el cliente y traducido por el bot. En
-- producción: 1.810 búsquedas de 559 personas distintas.
--
-- CUELGA DEL CONTACTO, NO DE LA OPORTUNIDAD
-- Un requerimiento SOBREVIVE al cierre del negocio, y eso es
-- precisamente lo que hace posible la bandeja de reactivación: alguien
-- a quien cerramos en julio sigue habiendo dicho qué quería, y cuando
-- entre ese apartamento en diciembre hay que poder encontrarlo.
-- =====================================================================

CREATE TABLE crm.requerimientos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  inmobiliaria_id uuid NOT NULL
    REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,
  contacto_id uuid NOT NULL
    REFERENCES crm.contactos(id) ON DELETE CASCADE,

  -- ---------------------------------------------------------------
  -- Qué busca. TODO es opcional porque en la vida real la gente dice
  -- lo que dice: en producción solo el 48% mencionó presupuesto y el
  -- 57% un barrio. Un modelo que exija todos los campos describiría
  -- un cliente que no existe.
  -- ---------------------------------------------------------------
  ciudad           text,
  barrios          text[],
  tipo_inmueble    text[],
  tipo_transaccion text CHECK (tipo_transaccion IN ('arriendo', 'venta')),
  precio_max       numeric(14,2),
  habitaciones_min smallint,
  notas            text,

  -- De dónde salió. 'agente' es deducido de las búsquedas del bot;
  -- 'humano' lo escribió un asesor hablando con la persona. Distinguirlo
  -- importa: lo segundo vale más y no debe pisarse con lo primero.
  origen text NOT NULL DEFAULT 'agente'
    CHECK (origen IN ('agente', 'humano')),

  activo boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Un requerimiento sin ni un dato no es un requerimiento.
  CONSTRAINT requerimientos_algo_pedido CHECK (
    num_nonnulls(ciudad, barrios, tipo_inmueble, tipo_transaccion,
                 precio_max, habitaciones_min) >= 1
  )
);

-- Uno activo por persona y tipo de transacción: alguien puede estar
-- buscando arriendo YA y compra para dentro de dos años, y son dos cosas
-- distintas. Dos requerimientos de arriendo a la vez, no.
CREATE UNIQUE INDEX requerimientos_uno_activo
  ON crm.requerimientos (contacto_id, tipo_transaccion)
  WHERE activo;

CREATE INDEX requerimientos_contacto ON crm.requerimientos (contacto_id);
CREATE INDEX requerimientos_busqueda
  ON crm.requerimientos (inmobiliaria_id, tipo_transaccion)
  WHERE activo;

ALTER TABLE crm.requerimientos ENABLE ROW LEVEL SECURITY;

CREATE POLICY requerimientos_select ON crm.requerimientos
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());

CREATE POLICY requerimientos_insert ON crm.requerimientos
  FOR INSERT TO authenticated
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria());

CREATE POLICY requerimientos_update ON crm.requerimientos
  FOR UPDATE TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria())
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria());

CREATE POLICY requerimientos_delete ON crm.requerimientos
  FOR DELETE TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());

COMMENT ON TABLE crm.requerimientos IS
  'Qué busca cada persona. Sobrevive al cierre de la oportunidad, que es lo que permite reactivar.';

-- ---------------------------------------------------------------------
-- Comparar textos de zona sin que una tilde decida un negocio
--
-- El catálogo dice "Niquia" y el cliente escribe "Niquía". Sin
-- normalizar, ese acento cuesta una coincidencia.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.igual_zona(a text, b text)
RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path = ''
AS $zona$
  SELECT a IS NOT NULL AND b IS NOT NULL
     AND lower(public.unaccent(btrim(a))) = lower(public.unaccent(btrim(b)));
$zona$;

-- ---------------------------------------------------------------------
-- El puntaje
--
-- TOLERANTE Y CON PUNTAJE, no filtro exacto. Con solo el 48% de los
-- requerimientos indicando precio y el 57% un barrio, un filtro estricto
-- devolvería cero casi siempre y la función parecería rota. Y en
-- arriendo, a quien pidió "hasta 1,5M" sí le sirve ver uno de 1,6M.
--
-- Se puntúa SOLO sobre los campos que la persona dijo, y el resultado es
-- el porcentaje de lo que pidió que este inmueble cumple. Así alguien
-- que solo dijo "apartamento en Bello" obtiene un puntaje con sentido en
-- vez de quedar penalizado por callarse el presupuesto.
--
-- Devuelve NULL cuando el inmueble NO debe mostrarse nunca:
--   · otra transacción — enseñarle una venta a quien arrienda es ruido
--   · más de un 10% por encima del presupuesto — eso no es estirar, es
--     otro negocio
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.puntaje_match(
  p_requerimiento_id uuid,
  p_inmueble_id      uuid)
RETURNS smallint
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $puntaje$
DECLARE
  r crm.requerimientos%ROWTYPE;
  i record;
  v_posible numeric := 0;   -- peso de lo que la persona SÍ dijo
  v_logrado numeric := 0;
BEGIN
  SELECT * INTO r FROM crm.requerimientos WHERE id = p_requerimiento_id AND activo;
  IF r.id IS NULL THEN RETURN NULL; END IF;

  SELECT v.ciudad, v.barrio, v.habitaciones, v.precio,
         v.tipo_inmueble, v.tipo_transaccion, v.estado, v.inmobiliaria_id
    INTO i
    FROM crm.v_inmuebles v WHERE v.id = p_inmueble_id;
  IF i.inmobiliaria_id IS NULL OR i.inmobiliaria_id <> r.inmobiliaria_id THEN
    RETURN NULL;
  END IF;
  IF i.estado <> 'disponible' THEN RETURN NULL; END IF;

  -- --- Descalificaciones ---------------------------------------------
  IF r.tipo_transaccion IS NOT NULL
     AND i.tipo_transaccion IS DISTINCT FROM r.tipo_transaccion THEN
    RETURN NULL;
  END IF;

  IF r.precio_max IS NOT NULL
     AND i.precio IS NOT NULL
     AND i.precio > r.precio_max * 1.10 THEN
    RETURN NULL;
  END IF;

  -- --- Puntaje --------------------------------------------------------
  -- Tipo de inmueble (peso 30). No descalifica: el propio agente ofrece
  -- alternativas de otro tipo en la misma zona cuando no hay del pedido,
  -- y esa conversación funciona.
  IF r.tipo_inmueble IS NOT NULL AND array_length(r.tipo_inmueble, 1) > 0 THEN
    v_posible := v_posible + 30;
    IF i.tipo_inmueble = ANY (r.tipo_inmueble) THEN
      v_logrado := v_logrado + 30;
    END IF;
  END IF;

  -- Zona (peso 30). El barrio pedido vale todo; la misma ciudad, la
  -- mitad: "no es Niquía pero es Bello" sigue siendo una conversación
  -- que se puede tener.
  IF r.barrios IS NOT NULL AND array_length(r.barrios, 1) > 0 THEN
    v_posible := v_posible + 30;
    IF EXISTS (SELECT 1 FROM unnest(r.barrios) b WHERE crm.igual_zona(b, i.barrio)) THEN
      v_logrado := v_logrado + 30;
    ELSIF crm.igual_zona(r.ciudad, i.ciudad) THEN
      v_logrado := v_logrado + 15;
    END IF;
  ELSIF r.ciudad IS NOT NULL THEN
    v_posible := v_posible + 30;
    IF crm.igual_zona(r.ciudad, i.ciudad) THEN
      v_logrado := v_logrado + 30;
    END IF;
  END IF;

  -- Precio (peso 25). Dentro del presupuesto vale todo; el margen del
  -- 10% vale poco más de la mitad, porque estirar cuesta.
  IF r.precio_max IS NOT NULL THEN
    v_posible := v_posible + 25;
    IF i.precio IS NULL THEN
      NULL;                                   -- sin precio no se premia ni se castiga
    ELSIF i.precio <= r.precio_max THEN
      v_logrado := v_logrado + 25;
    ELSE
      v_logrado := v_logrado + 14;            -- entre el 100% y el 110%
    END IF;
  END IF;

  -- Habitaciones (peso 15). Una menos de las pedidas todavía se enseña;
  -- dos menos, no.
  IF r.habitaciones_min IS NOT NULL THEN
    v_posible := v_posible + 15;
    IF i.habitaciones IS NULL THEN
      NULL;
    ELSIF i.habitaciones >= r.habitaciones_min THEN
      v_logrado := v_logrado + 15;
    ELSIF i.habitaciones = r.habitaciones_min - 1 THEN
      v_logrado := v_logrado + 6;
    END IF;
  END IF;

  IF v_posible = 0 THEN
    RETURN NULL;   -- no dijo nada puntuable
  END IF;

  RETURN round(100 * v_logrado / v_posible)::smallint;
END $puntaje$;

-- ---------------------------------------------------------------------
-- Cuántas cosas pidió esta persona
--
-- EL PUNTAJE SOLO NO BASTA PARA ORDENAR. Es un porcentaje, así que quien
-- dijo "apartamento en Bello" y lo cumple saca 100 igual que quien pidió
-- barrio, presupuesto y habitaciones y lo cumple todo. Encajan igual de
-- bien, pero de la segunda SABEMOS mucho más, y ésa es la que el asesor
-- quiere arriba: la coincidencia informada vale más que la afortunada.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.especificidad(p_requerimiento_id uuid)
RETURNS smallint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $esp$
  SELECT num_nonnulls(r.ciudad, r.barrios, r.tipo_inmueble,
                      r.tipo_transaccion, r.precio_max,
                      r.habitaciones_min)::smallint
  FROM crm.requerimientos r WHERE r.id = p_requerimiento_id;
$esp$;

GRANT EXECUTE ON FUNCTION crm.especificidad(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- EL CRITERIO DE LA FASE, hecho función
--
-- "Entra un apto en Robledo y el asesor recibe los clientes que lo
-- pidieron". Esto es exactamente eso, al revés de como suele pensarse
-- un buscador: del inmueble hacia las personas.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.clientes_para(
  p_inmueble_id uuid,
  p_minimo      smallint DEFAULT 50)
RETURNS TABLE (
  contacto_id      uuid,
  requerimiento_id uuid,
  nombre           text,
  telefono_e164    text,
  puntaje          smallint,
  -- Cuántos campos pidió: desempata, y la pantalla puede decir "cumple
  -- las cuatro cosas que pidió" en vez de un porcentaje desnudo.
  especificidad    smallint,
  pidio            text,
  oportunidad_id   uuid,
  etapa            text,
  estado           text,
  ultima_actividad_at timestamptz
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $clientes$
  SELECT
    r.contacto_id,
    r.id,
    c.nombre,
    c.telefono_e164,
    crm.puntaje_match(r.id, p_inmueble_id) AS puntaje,
    crm.especificidad(r.id)                AS especificidad,
    -- Lo que pidió, en una línea legible: el asesor va a escribirle por
    -- WhatsApp y necesita recordar de qué hablaron, no leer un jsonb.
    btrim(concat_ws(', ',
      array_to_string(r.tipo_inmueble, ' o '),
      CASE WHEN r.barrios IS NOT NULL
           THEN 'en ' || array_to_string(r.barrios, ' o ')
           WHEN r.ciudad IS NOT NULL THEN 'en ' || r.ciudad END,
      CASE WHEN r.habitaciones_min IS NOT NULL
           THEN r.habitaciones_min || '+ hab' END,
      -- El separador de miles se fuerza a punto: 'G' usa el del locale
      -- del servidor, que en esta base es la coma. "$1,500,000" en
      -- Colombia se lee mal.
      CASE WHEN r.precio_max IS NOT NULL
           THEN 'hasta $' || replace(to_char(r.precio_max, 'FM999G999G999'), ',', '.') END
    )) AS pidio,
    o.id,
    o.etapa,
    o.estado,
    c.ultima_actividad_at
  FROM crm.requerimientos r
  JOIN crm.contactos c ON c.id = r.contacto_id AND c.deleted_at IS NULL
  -- LEFT: una persona con la oportunidad cerrada TAMBIÉN vale. Es
  -- justamente la bandeja de reactivación: dijo qué quería, no se lo
  -- pudimos dar, y hoy sí.
  LEFT JOIN crm.oportunidades o
         ON o.contacto_id = r.contacto_id AND o.estado = 'abierta'
  WHERE r.activo
    AND crm.puntaje_match(r.id, p_inmueble_id) >= p_minimo
  ORDER BY crm.puntaje_match(r.id, p_inmueble_id) DESC,
           crm.especificidad(r.id) DESC,
           c.ultima_actividad_at DESC NULLS LAST;
$clientes$;

-- ---------------------------------------------------------------------
-- El sentido contrario: qué le sirve HOY a esta persona
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.inmuebles_para(
  p_contacto_id uuid,
  p_minimo      smallint DEFAULT 50,
  p_limite      int      DEFAULT 10)
RETURNS TABLE (
  inmueble_id uuid,
  titulo      text,
  barrio      text,
  ciudad      text,
  precio      numeric,
  habitaciones integer,
  tipo_inmueble text,
  puntaje     smallint
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $inmuebles$
  SELECT v.id, v.titulo, v.barrio, v.ciudad, v.precio, v.habitaciones,
         v.tipo_inmueble, crm.puntaje_match(r.id, v.id) AS puntaje
  FROM crm.requerimientos r
  CROSS JOIN crm.v_inmuebles v
  WHERE r.contacto_id = p_contacto_id
    AND r.activo
    AND v.estado = 'disponible'
    AND crm.puntaje_match(r.id, v.id) >= p_minimo
  ORDER BY crm.puntaje_match(r.id, v.id) DESC, v.created_at DESC
  LIMIT p_limite;
$inmuebles$;

-- ---------------------------------------------------------------------
-- El backfill: los requerimientos que ya existen sin saberlo
--
-- Se lee la ÚLTIMA búsqueda de cada persona por tipo de transacción: si
-- alguien empezó pidiendo casa y acabó preguntando por apartamentos, lo
-- que vale es lo último que dijo.
--
-- Solo crea requerimientos de origen 'agente', y NUNCA pisa uno
-- 'humano': lo que un asesor escribió hablando con la persona vale más
-- que lo que dedujo un bot.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.backfill_requerimientos()
RETURNS TABLE (creados integer, actualizados integer, personas integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $backfill$
DECLARE
  v_creados      integer := 0;
  v_actualizados integer := 0;
  b record;
BEGIN
  FOR b IN
    WITH busquedas AS (
      SELECT
        a.contacto_id,
        a.inmobiliaria_id,
        h->'entrada' AS e,
        m.created_at
      FROM public.agente_comercial_mensajes m
      CROSS JOIN LATERAL jsonb_array_elements(m.herramientas_usadas) h
      JOIN crm.actividades a
        ON a.metadata->>'origen_tabla' = 'agente_comercial_mensajes'
       AND a.metadata->>'origen_id' = m.id::text
      WHERE h->>'nombre' = 'buscar_inmuebles'
        AND a.contacto_id IS NOT NULL
    )
    SELECT DISTINCT ON (contacto_id, e->>'tipo_transaccion')
      contacto_id,
      inmobiliaria_id,
      NULLIF(e->>'ciudad', '')            AS ciudad,
      NULLIF(e->>'barrio', '')            AS barrio,
      NULLIF(e->>'tipo_inmueble', '')     AS tipo_inmueble,
      NULLIF(e->>'tipo_transaccion', '')  AS tipo_transaccion,
      NULLIF(e->>'precio_max', '')::numeric       AS precio_max,
      NULLIF(e->>'habitaciones_min', '')::smallint AS habitaciones_min
    FROM busquedas
    ORDER BY contacto_id, e->>'tipo_transaccion', created_at DESC
  LOOP
    CONTINUE WHEN b.tipo_transaccion IS NULL;   -- el índice único lo exige
    CONTINUE WHEN num_nonnulls(b.ciudad, b.barrio, b.tipo_inmueble,
                               b.precio_max, b.habitaciones_min) = 0;

    BEGIN
      INSERT INTO crm.requerimientos (
        inmobiliaria_id, contacto_id, ciudad, barrios, tipo_inmueble,
        tipo_transaccion, precio_max, habitaciones_min, origen)
      VALUES (
        b.inmobiliaria_id, b.contacto_id, b.ciudad,
        CASE WHEN b.barrio IS NOT NULL THEN ARRAY[b.barrio] END,
        CASE WHEN b.tipo_inmueble IS NOT NULL THEN ARRAY[b.tipo_inmueble] END,
        b.tipo_transaccion, b.precio_max, b.habitaciones_min, 'agente')
      ON CONFLICT (contacto_id, tipo_transaccion) WHERE activo
      DO UPDATE SET
        ciudad           = EXCLUDED.ciudad,
        barrios          = EXCLUDED.barrios,
        tipo_inmueble    = EXCLUDED.tipo_inmueble,
        precio_max       = EXCLUDED.precio_max,
        habitaciones_min = EXCLUDED.habitaciones_min,
        updated_at       = now()
      -- Lo que escribió una persona NO se pisa con lo que dedujo el bot.
      WHERE crm.requerimientos.origen = 'agente';

      IF FOUND THEN v_creados := v_creados + 1; END IF;
    EXCEPTION WHEN OTHERS THEN
      v_actualizados := v_actualizados;   -- una fila rota no para el resto
    END;
  END LOOP;

  RETURN QUERY
    SELECT v_creados, v_actualizados,
           (SELECT count(DISTINCT contacto_id)::integer
              FROM crm.requerimientos WHERE activo);
END $backfill$;

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION crm.clientes_para(uuid, smallint) TO authenticated;
GRANT EXECUTE ON FUNCTION crm.inmuebles_para(uuid, smallint, int) TO authenticated;
GRANT EXECUTE ON FUNCTION crm.puntaje_match(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION crm.igual_zona(text, text) TO authenticated;

REVOKE ALL ON FUNCTION crm.backfill_requerimientos() FROM public, anon, authenticated;
