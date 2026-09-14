-- =====================================================================
-- Fase 3-B — La pantalla de coincidencias, y el puntaje que la hace
-- posible.
--
-- POR QUÉ HAY QUE REESCRIBIR EL PUNTAJE
-- crm.puntaje_match() recibe dos ids y busca las dos filas. Perfecto para
-- una tarjeta; inservible para una pantalla: cruzar los 81 inmuebles con
-- los 550 requerimientos son 44.550 llamadas y 89.000 consultas.
-- Medido en producción con EXPLAIN ANALYZE: 1.557 ms. Y empeora cada vez
-- que alguien nuevo dice qué busca.
--
-- La lógica pasa a una función IMMUTABLE sobre VALORES, que Postgres
-- puede evaluar dentro de la consulta sin ir a buscar nada. `puntaje_match`
-- se queda como envoltorio por comodidad —y porque sus pruebas valen— pero
-- ya no es la que corre en bucle.
--
-- UNA SOLA FUENTE DE VERDAD: la fórmula vive aquí y nadie la duplica.
-- Dos copias de un puntaje es una granja de bugs donde la pantalla y la
-- ficha acaban diciendo cosas distintas del mismo par.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Normalizar una lista de zonas de una vez
--
-- Permite comparar con `= ANY(...)`, que es un operador, en vez de con un
-- EXISTS por fila, que es una subconsulta y ata las manos al planificador.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.normaliza_zonas(p text[])
RETURNS text[]
LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path = ''
AS $nz$
  SELECT CASE WHEN p IS NULL THEN NULL ELSE
    (SELECT array_agg(lower(public.unaccent(btrim(z)))) FROM unnest(p) z)
  END;
$nz$;

-- ---------------------------------------------------------------------
-- El puntaje, sobre valores
--
-- Misma fórmula que ya está probada, sin cambiar un peso:
--   tipo 30 · zona 30 (barrio pedido entero, misma ciudad la mitad)
--   precio 25 (14 si se estira hasta el 10%) · habitaciones 15 (6 si falta una)
--
-- Se puntúa SOLO sobre lo que la persona dijo, y el resultado es el
-- porcentaje de eso que este inmueble cumple.
--
-- NULL = no enseñar nunca: otra transacción, o más de un 10% por encima
-- del presupuesto.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.puntaje(
  r_ciudad      text,
  r_barrios     text[],
  r_tipos       text[],
  r_transaccion text,
  r_precio_max  numeric,
  r_hab_min     smallint,
  i_ciudad      text,
  i_barrio      text,
  i_tipo        text,
  i_transaccion text,
  i_precio      numeric,
  i_hab         integer,
  i_estado      text)
RETURNS smallint
LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path = ''
AS $p$
  SELECT CASE
    WHEN i_estado IS DISTINCT FROM 'disponible' THEN NULL
    WHEN r_transaccion IS NOT NULL
         AND i_transaccion IS DISTINCT FROM r_transaccion THEN NULL
    WHEN r_precio_max IS NOT NULL AND i_precio IS NOT NULL
         AND i_precio > r_precio_max * 1.10 THEN NULL
    WHEN x.posible = 0 THEN NULL
    ELSE round(100 * x.logrado / x.posible)::smallint
  END
  FROM (
    SELECT
      -- Lo que la persona SÍ dijo, que es sobre lo único que se puntúa.
        (CASE WHEN r_tipos IS NOT NULL AND cardinality(r_tipos) > 0 THEN 30 ELSE 0 END)
      + (CASE WHEN (r_barrios IS NOT NULL AND cardinality(r_barrios) > 0)
                   OR r_ciudad IS NOT NULL THEN 30 ELSE 0 END)
      + (CASE WHEN r_precio_max IS NOT NULL THEN 25 ELSE 0 END)
      + (CASE WHEN r_hab_min    IS NOT NULL THEN 15 ELSE 0 END) AS posible,

        (CASE WHEN r_tipos IS NOT NULL AND cardinality(r_tipos) > 0
                   AND i_tipo = ANY (r_tipos) THEN 30 ELSE 0 END)
      + (CASE
           WHEN r_barrios IS NOT NULL AND cardinality(r_barrios) > 0 THEN
             CASE
               WHEN lower(public.unaccent(btrim(i_barrio)))
                      = ANY (crm.normaliza_zonas(r_barrios)) THEN 30
               -- "No es Niquía pero es Bello" sigue siendo una
               -- conversación que se puede tener: vale la mitad.
               WHEN crm.igual_zona(r_ciudad, i_ciudad) THEN 15
               ELSE 0
             END
           WHEN r_ciudad IS NOT NULL THEN
             CASE WHEN crm.igual_zona(r_ciudad, i_ciudad) THEN 30 ELSE 0 END
           ELSE 0
         END)
      + (CASE
           WHEN r_precio_max IS NULL OR i_precio IS NULL THEN 0
           WHEN i_precio <= r_precio_max THEN 25
           ELSE 14                              -- entre el 100% y el 110%
         END)
      + (CASE
           WHEN r_hab_min IS NULL OR i_hab IS NULL THEN 0
           WHEN i_hab >= r_hab_min          THEN 15
           WHEN i_hab  = r_hab_min - 1      THEN 6
           ELSE 0
         END) AS logrado
  ) x;
$p$;

-- El envoltorio por id se queda: es cómodo para una tarjeta suelta y sus
-- pruebas siguen siendo válidas. Ahora delega, así que no hay dos
-- fórmulas que puedan separarse con el tiempo.
CREATE OR REPLACE FUNCTION crm.puntaje_match(
  p_requerimiento_id uuid,
  p_inmueble_id      uuid)
RETURNS smallint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $pm$
  SELECT crm.puntaje(
    r.ciudad, r.barrios, r.tipo_inmueble, r.tipo_transaccion,
    r.precio_max, r.habitaciones_min,
    v.ciudad, v.barrio, v.tipo_inmueble, v.tipo_transaccion,
    v.precio, v.habitaciones, v.estado)
  FROM crm.requerimientos r, crm.v_inmuebles v
  WHERE r.id = p_requerimiento_id AND r.activo
    AND v.id = p_inmueble_id
    AND v.inmobiliaria_id = r.inmobiliaria_id;
$pm$;

GRANT EXECUTE ON FUNCTION crm.puntaje(text, text[], text[], text, numeric, smallint,
                                      text, text, text, text, numeric, integer, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION crm.normaliza_zonas(text[]) TO authenticated;

-- ---------------------------------------------------------------------
-- LA PANTALLA
--
-- Un inmueble entró y hay gente que lo pidió. Esto devuelve las dos cosas
-- de una sola consulta: el inmueble con su total de interesados, y los
-- primeros N de cada uno.
--
-- ESTÁ ESCRITA PARA DOS CONSUMIDORES, no para una pantalla. Hoy la usa la
-- página de coincidencias; el día que el agente trabaje dentro del CRM,
-- ésta es la herramienta con la que sabrá a quién ofrecerle lo que acaba
-- de entrar. Por eso la firma es estable y los nombres se leen solos.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.coincidencias(
  p_minimo        smallint DEFAULT 50,
  p_por_inmueble  int      DEFAULT 5,
  p_limite        int      DEFAULT 20,
  p_inmueble_id   uuid     DEFAULT NULL)
RETURNS TABLE (
  inmueble_id      uuid,
  titulo           text,
  barrio           text,
  ciudad           text,
  precio           numeric,
  habitaciones     integer,
  tipo_inmueble    text,
  tipo_transaccion text,
  inmueble_desde   timestamptz,
  total_clientes   bigint,
  contacto_id      uuid,
  requerimiento_id uuid,
  nombre           text,
  telefono_e164    text,
  puntaje          smallint,
  especificidad    smallint,
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
      v.habitaciones, v.tipo_inmueble, v.tipo_transaccion, v.created_at,
      r.id AS requerimiento_id, r.contacto_id,
      crm.puntaje(
        r.ciudad, r.barrios, r.tipo_inmueble, r.tipo_transaccion,
        r.precio_max, r.habitaciones_min,
        v.ciudad, v.barrio, v.tipo_inmueble, v.tipo_transaccion,
        v.precio, v.habitaciones, v.estado) AS puntaje,
      num_nonnulls(r.ciudad, r.barrios, r.tipo_inmueble, r.tipo_transaccion,
                   r.precio_max, r.habitaciones_min)::smallint AS especificidad,
      btrim(concat_ws(', ',
        array_to_string(r.tipo_inmueble, ' o '),
        CASE WHEN r.barrios IS NOT NULL THEN 'en ' || array_to_string(r.barrios, ' o ')
             WHEN r.ciudad  IS NOT NULL THEN 'en ' || r.ciudad END,
        CASE WHEN r.habitaciones_min IS NOT NULL THEN r.habitaciones_min || '+ hab' END,
        CASE WHEN r.precio_max IS NOT NULL
             THEN 'hasta $' || replace(to_char(r.precio_max, 'FM999G999G999'), ',', '.') END
      )) AS pidio
    FROM crm.v_inmuebles v
    JOIN crm.requerimientos r
      ON r.inmobiliaria_id = v.inmobiliaria_id AND r.activo
    WHERE v.estado = 'disponible'
      AND (p_inmueble_id IS NULL OR v.id = p_inmueble_id)
  ), filtrados AS (
    SELECT p.*,
           row_number() OVER (PARTITION BY p.inmueble_id
                              ORDER BY p.puntaje DESC, p.especificidad DESC) AS n,
           count(*)     OVER (PARTITION BY p.inmueble_id) AS total_clientes
    FROM pares p
    WHERE p.puntaje >= p_minimo
  ), elegidos AS (
    -- Los inmuebles que muestra la pantalla: los que TIENEN gente. Uno sin
    -- interesados no es una coincidencia, es sólo inventario.
    SELECT DISTINCT inmueble_id, created_at, total_clientes
    FROM filtrados
    ORDER BY created_at DESC
    LIMIT p_limite
  )
  SELECT
    f.inmueble_id, f.titulo, f.barrio, f.ciudad, f.precio, f.habitaciones,
    f.tipo_inmueble, f.tipo_transaccion, f.created_at, f.total_clientes,
    f.contacto_id, f.requerimiento_id, c.nombre, c.telefono_e164,
    f.puntaje, f.especificidad, f.pidio,
    o.id, o.etapa, c.ultima_actividad_at
  FROM filtrados f
  JOIN elegidos e ON e.inmueble_id = f.inmueble_id
  JOIN crm.contactos c ON c.id = f.contacto_id AND c.deleted_at IS NULL
  -- LEFT: quien tiene la oportunidad CERRADA también sale. Es la bandeja
  -- de reactivación: dijo qué quería, no se lo pudimos dar, y hoy sí.
  LEFT JOIN crm.oportunidades o
         ON o.contacto_id = f.contacto_id AND o.estado = 'abierta'
  WHERE f.n <= p_por_inmueble
  ORDER BY f.created_at DESC, f.n;
$co$;

GRANT EXECUTE ON FUNCTION crm.coincidencias(smallint, int, int, uuid) TO authenticated;
