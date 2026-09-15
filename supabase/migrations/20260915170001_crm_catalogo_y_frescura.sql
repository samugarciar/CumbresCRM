-- =====================================================================
-- Fase 3-C — Que "entrar al catálogo" signifique entrar, y que la
-- pantalla sea una lista de trabajo y no una guía telefónica.
--
-- DOS FALLOS QUE NINGUNA PRUEBA IBA A ENCONTRAR
-- Se vieron apuntando la aplicación a producción, con los 81 inmuebles y
-- los 550 requerimientos de verdad.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. La foto del catálogo
--
-- EL PROBLEMA: la pantalla ordenaba por `inmuebles.created_at`, que es
-- cuándo se creó la FILA — no cuándo el inmueble salió al mercado. De los
-- 81 disponibles, 54 son de la importación de mayo.
--
-- Y el caso más común del arriendo es justo el que no se veía: un
-- apartamento arrendado cuyo inquilino se va y vuelve al mercado. Es una
-- oportunidad nueva de verdad, con `created_at` de mayo, al fondo de la
-- lista.
--
-- En `public.inmuebles` no hay dónde mirarlo: tiene `created_at`,
-- `estado`, `estado_erp` y `estado_override`, y NINGUNA columna que diga
-- cuándo cambió el estado.
--
-- POR QUÉ UNA TABLA NUESTRA Y NO UN TRIGGER EN `public`
-- Añadir una columna o un trigger a `inmuebles` sería tocar el esquema
-- del otro repo, que es la línea que este proyecto no cruza. Esto solo
-- LEE `public` y escribe en `crm`: la misma dirección de siempre.
-- ---------------------------------------------------------------------
CREATE TABLE crm.catalogo (
  inmueble_id     uuid PRIMARY KEY REFERENCES public.inmuebles(id) ON DELETE CASCADE,
  inmobiliaria_id uuid NOT NULL REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,

  estado text NOT NULL,
  -- Cuándo pasó a estar disponible. NULL mientras no lo esté. ESTE es el
  -- "entró" que la pantalla necesita.
  disponible_desde timestamptz,
  visto_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX catalogo_disponibles
  ON crm.catalogo (inmobiliaria_id, disponible_desde DESC)
  WHERE estado = 'disponible';

ALTER TABLE crm.catalogo ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalogo_select ON crm.catalogo
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());

COMMENT ON TABLE crm.catalogo IS
  'Foto del estado de cada inmueble, para saber CUÁNDO salió al mercado. public.inmuebles no lo guarda.';

CREATE OR REPLACE FUNCTION crm.refrescar_catalogo()
RETURNS TABLE (nuevos integer, volvieron integer, se_fueron integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $refrescar$
DECLARE
  v_nuevos integer := 0;
  v_volvieron integer := 0;
  v_fueron integer := 0;
BEGIN
  -- Los que aparecen por primera vez. En la PRIMERA pasada esto son los
  -- 81 de hoy, y su `disponible_desde` se siembra con `created_at`: no
  -- sabemos cuándo salieron al mercado de verdad y inventar una fecha
  -- sería peor que usar la única que existe. A partir de mañana, el dato
  -- es real.
  WITH ins AS (
    INSERT INTO crm.catalogo (inmueble_id, inmobiliaria_id, estado, disponible_desde)
    SELECT i.id, i.inmobiliaria_id, i.estado,
           CASE WHEN i.estado = 'disponible' THEN i.created_at END
    FROM public.inmuebles i
    WHERE NOT EXISTS (SELECT 1 FROM crm.catalogo c WHERE c.inmueble_id = i.id)
    RETURNING 1
  ) SELECT count(*)::integer INTO v_nuevos FROM ins;

  -- Los que VUELVEN al mercado. Este es el evento que no se podía ver.
  WITH upd AS (
    UPDATE crm.catalogo c
       SET estado = i.estado, disponible_desde = now(), visto_at = now()
      FROM public.inmuebles i
     WHERE i.id = c.inmueble_id
       AND i.estado = 'disponible'
       AND c.estado IS DISTINCT FROM 'disponible'
    RETURNING 1
  ) SELECT count(*)::integer INTO v_volvieron FROM upd;

  -- Los que salen del mercado: se arrendaron, se vendieron o se dieron
  -- de baja. Se borra `disponible_desde` para que el día que vuelvan
  -- cuente como entrada nueva, que es lo que es.
  WITH upd AS (
    UPDATE crm.catalogo c
       SET estado = i.estado, disponible_desde = NULL, visto_at = now()
      FROM public.inmuebles i
     WHERE i.id = c.inmueble_id
       AND i.estado IS DISTINCT FROM 'disponible'
       AND c.estado = 'disponible'
    RETURNING 1
  ) SELECT count(*)::integer INTO v_fueron FROM upd;

  -- El resto: solo se marca que se vieron, sin tocar la fecha.
  UPDATE crm.catalogo c
     SET estado = i.estado, visto_at = now()
    FROM public.inmuebles i
   WHERE i.id = c.inmueble_id AND c.estado IS NOT DISTINCT FROM i.estado;

  RETURN QUERY SELECT v_nuevos, v_volvieron, v_fueron;
END $refrescar$;

REVOKE ALL ON FUNCTION crm.refrescar_catalogo() FROM public, anon, authenticated;

-- Cada quince minutos. El catálogo lo mueve un sync con el ERP, no una
-- persona pulsando un botón: no hace falta más fino, y algo que corre
-- seguido sobre una tabla ajena conviene que sea barato.
DO $cron$
BEGIN
  PERFORM cron.schedule(
    'crm_refrescar_catalogo', '*/15 * * * *',
    $trabajo$SELECT crm.refrescar_catalogo();$trabajo$);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron no disponible; agendar crm.refrescar_catalogo() a mano: %', SQLERRM;
END $cron$;

-- ---------------------------------------------------------------------
-- 2. La frescura
--
-- EL PROBLEMA: 40 de los 81 inmuebles tienen 200 o más interesados, y uno
-- llega a 500, con puntaje medio 90. El puntaje NO está mal calibrado —la
-- gente sí pidió cosas concretas, el 78% dijo cuatro o más— sino que 40
-- inmuebles son apartamentos genéricos en Bello para arriendo y ~400
-- personas pidieron exactamente eso. Encajan todos con todos.
--
-- Lo que falta no es precisión en el cruce: es ESTAR VIVO. De esas 500, la
-- mayoría lleva meses sin hablar. El puntaje mide si le sirve, no si vale
-- la pena llamarla hoy.
--
-- Se ordena por tramos y no por fecha cruda a propósito: así "reciente y
-- bueno" gana a "viejo y perfecto", pero dentro del mismo tramo sigue
-- mandando el encaje. Ordenar por fecha sola pondría arriba a quien
-- escribió ayer aunque encaje a medias.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.frescura(p_ultima timestamptz)
RETURNS smallint
LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path = ''
AS $f$
  SELECT CASE
    WHEN p_ultima IS NULL                          THEN 3   -- nunca habló
    WHEN p_ultima > now() - interval '7 days'      THEN 0   -- esta semana
    WHEN p_ultima > now() - interval '30 days'     THEN 1   -- este mes
    ELSE 2                                                   -- más atrás
  END::smallint;
$f$;

-- IMMUTABLE con now() dentro sería mentira y Postgres podría cachear el
-- resultado entre filas. Se marca STABLE, que es lo que realmente es.
ALTER FUNCTION crm.frescura(timestamptz) STABLE;

GRANT EXECUTE ON FUNCTION crm.frescura(timestamptz) TO authenticated;

-- ---------------------------------------------------------------------
-- 3. La pantalla, con las dos cosas
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS crm.coincidencias(smallint, int, int, uuid);

CREATE OR REPLACE FUNCTION crm.coincidencias(
  p_minimo        smallint DEFAULT 50,
  p_por_inmueble  int      DEFAULT 5,
  p_limite        int      DEFAULT 20,
  p_inmueble_id   uuid     DEFAULT NULL,
  -- Por defecto solo gente que habló en el último mes: es lo que
  -- convierte 500 nombres en una lista a la que llamar hoy. Se puede
  -- apagar para rebuscar en el histórico.
  p_frescura_max  smallint DEFAULT 1)
RETURNS TABLE (
  inmueble_id      uuid,
  titulo           text,
  barrio           text,
  ciudad           text,
  precio           numeric,
  habitaciones     integer,
  tipo_inmueble    text,
  tipo_transaccion text,
  disponible_desde timestamptz,
  total_clientes   bigint,
  contacto_id      uuid,
  requerimiento_id uuid,
  nombre           text,
  telefono_e164    text,
  puntaje          smallint,
  especificidad    smallint,
  frescura         smallint,
  pidio            text,
  oportunidad_id   uuid,
  etapa            text,
  ultima_actividad_at timestamptz
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $co$
  WITH pares AS (
    SELECT
      v.id AS inmueble_id, v.titulo, v.barrio, v.ciudad, v.precio,
      v.habitaciones, v.tipo_inmueble, v.tipo_transaccion,
      COALESCE(cat.disponible_desde, v.created_at) AS disponible_desde,
      r.id AS requerimiento_id, r.contacto_id,
      crm.puntaje(
        r.ciudad, r.barrios, r.tipo_inmueble, r.tipo_transaccion,
        r.precio_max, r.habitaciones_min,
        v.ciudad, v.barrio, v.tipo_inmueble, v.tipo_transaccion,
        v.precio, v.habitaciones, v.estado) AS puntaje,
      num_nonnulls(r.ciudad, r.barrios, r.tipo_inmueble, r.tipo_transaccion,
                   r.precio_max, r.habitaciones_min)::smallint AS especificidad,
      crm.frescura(c.ultima_actividad_at) AS frescura,
      c.ultima_actividad_at,
      btrim(concat_ws(', ',
        array_to_string(r.tipo_inmueble, ' o '),
        CASE WHEN r.barrios IS NOT NULL THEN 'en ' || array_to_string(r.barrios, ' o ')
             WHEN r.ciudad  IS NOT NULL THEN 'en ' || r.ciudad END,
        CASE WHEN r.habitaciones_min IS NOT NULL THEN r.habitaciones_min || '+ hab' END,
        CASE WHEN r.precio_max IS NOT NULL
             THEN 'hasta $' || replace(to_char(r.precio_max, 'FM999G999G999'), ',', '.') END
      )) AS pidio
    FROM crm.v_inmuebles v
    LEFT JOIN crm.catalogo cat ON cat.inmueble_id = v.id
    JOIN crm.requerimientos r
      ON r.inmobiliaria_id = v.inmobiliaria_id AND r.activo
    JOIN crm.contactos c ON c.id = r.contacto_id AND c.deleted_at IS NULL
    WHERE v.estado = 'disponible'
      AND (p_inmueble_id IS NULL OR v.id = p_inmueble_id)
  ), filtrados AS (
    SELECT p.*,
           row_number() OVER (PARTITION BY p.inmueble_id
                              ORDER BY p.frescura, p.puntaje DESC,
                                       p.especificidad DESC) AS n,
           count(*)     OVER (PARTITION BY p.inmueble_id) AS total_clientes
    FROM pares p
    WHERE p.puntaje >= p_minimo
      AND (p_frescura_max IS NULL OR p.frescura <= p_frescura_max)
  ), elegidos AS (
    SELECT DISTINCT inmueble_id, disponible_desde
    FROM filtrados
    ORDER BY disponible_desde DESC
    LIMIT p_limite
  )
  SELECT
    f.inmueble_id, f.titulo, f.barrio, f.ciudad, f.precio, f.habitaciones,
    f.tipo_inmueble, f.tipo_transaccion, f.disponible_desde, f.total_clientes,
    f.contacto_id, f.requerimiento_id, c.nombre, c.telefono_e164,
    f.puntaje, f.especificidad, f.frescura, f.pidio,
    o.id, o.etapa, f.ultima_actividad_at
  FROM filtrados f
  JOIN elegidos e ON e.inmueble_id = f.inmueble_id
  JOIN crm.contactos c ON c.id = f.contacto_id
  LEFT JOIN crm.oportunidades o
         ON o.contacto_id = f.contacto_id AND o.estado = 'abierta'
  WHERE f.n <= p_por_inmueble
  ORDER BY f.disponible_desde DESC, f.n;
$co$;

GRANT EXECUTE ON FUNCTION crm.coincidencias(smallint, int, int, uuid, smallint)
  TO authenticated;

-- ---------------------------------------------------------------------
-- 4. Y el sentido contrario, con la ROTACIÓN que pidió Samuel
--
-- Para la vista de chat: al abrir un lead, qué se le puede ofrecer. El
-- orden por defecto es de VIEJOS A NUEVOS, y va contra el instinto a
-- propósito — lo recién entrado se vende solo; **lo que lleva cuatro
-- meses parado necesita salir**. El puntaje sigue filtrando: rotar no es
-- ofrecer cualquier cosa.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS crm.inmuebles_para(uuid, smallint, int);

CREATE OR REPLACE FUNCTION crm.inmuebles_para(
  p_contacto_id uuid,
  p_minimo      smallint DEFAULT 50,
  p_limite      int      DEFAULT 10,
  -- true = viejos primero, para rotar inventario parado.
  p_rotar       boolean  DEFAULT true)
RETURNS TABLE (
  inmueble_id      uuid,
  titulo           text,
  barrio           text,
  ciudad           text,
  precio           numeric,
  habitaciones     integer,
  tipo_inmueble    text,
  puntaje          smallint,
  disponible_desde timestamptz
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $inmuebles$
  SELECT v.id, v.titulo, v.barrio, v.ciudad, v.precio, v.habitaciones,
         v.tipo_inmueble,
         crm.puntaje(
           r.ciudad, r.barrios, r.tipo_inmueble, r.tipo_transaccion,
           r.precio_max, r.habitaciones_min,
           v.ciudad, v.barrio, v.tipo_inmueble, v.tipo_transaccion,
           v.precio, v.habitaciones, v.estado) AS puntaje,
         COALESCE(cat.disponible_desde, v.created_at) AS disponible_desde
  FROM crm.requerimientos r
  CROSS JOIN crm.v_inmuebles v
  LEFT JOIN crm.catalogo cat ON cat.inmueble_id = v.id
  WHERE r.contacto_id = p_contacto_id
    AND r.activo
    AND r.inmobiliaria_id = v.inmobiliaria_id
    AND v.estado = 'disponible'
    AND crm.puntaje(
          r.ciudad, r.barrios, r.tipo_inmueble, r.tipo_transaccion,
          r.precio_max, r.habitaciones_min,
          v.ciudad, v.barrio, v.tipo_inmueble, v.tipo_transaccion,
          v.precio, v.habitaciones, v.estado) >= p_minimo
  ORDER BY
    CASE WHEN p_rotar THEN COALESCE(cat.disponible_desde, v.created_at) END ASC,
    CASE WHEN NOT p_rotar THEN COALESCE(cat.disponible_desde, v.created_at) END DESC,
    crm.puntaje(
      r.ciudad, r.barrios, r.tipo_inmueble, r.tipo_transaccion,
      r.precio_max, r.habitaciones_min,
      v.ciudad, v.barrio, v.tipo_inmueble, v.tipo_transaccion,
      v.precio, v.habitaciones, v.estado) DESC
  LIMIT p_limite;
$inmuebles$;

COMMENT ON FUNCTION crm.inmuebles_para(uuid, smallint, int, boolean) IS
  'Qué ofrecerle a esta persona. Por defecto de VIEJOS a NUEVOS, para rotar el inventario parado. También es la herramienta del agente.';

GRANT EXECUTE ON FUNCTION crm.inmuebles_para(uuid, smallint, int, boolean)
  TO authenticated;
