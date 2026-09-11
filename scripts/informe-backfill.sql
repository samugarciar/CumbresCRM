-- =====================================================================
-- INFORME DE BACKFILL — SOLO LECTURA
--
-- Mide cuántos contactos saldrían de unificar las cuatro fuentes del
-- histórico, y cuánta suciedad hay, ANTES de escribir un solo registro.
--
-- CÓMO SE USA
-- Pégalo en el SQL Editor de Supabase (producción). No escribe nada: son
-- puros SELECT. Hace falta ejecutarlo ahí y no desde la app porque el rol
-- `bi_reader` solo alcanza 9 de las 21 tablas — no ve
-- agente_comercial_conversaciones ni captacion_prospectos, que son
-- justamente las dos fuentes más ricas.
--
-- OJO: LÓGICA DUPLICADA
-- La normalización de abajo es un ESPEJO de crm.normalizar_telefono, que
-- todavía no existe en producción. Si esa función cambia, este informe
-- hay que actualizarlo a mano. Es aceptable porque el informe es de un
-- solo uso; no lo conviertas en parte de la aplicación.
-- =====================================================================

WITH fuentes AS (
  SELECT 'agente_comercial' AS fuente, telefono AS crudo, cliente_nombre AS nombre
    FROM public.agente_comercial_conversaciones
  UNION ALL
  SELECT 'citas', cliente_telefono, cliente_nombre
    FROM public.citas
  UNION ALL
  SELECT 'solicitudes_apertura', cliente_telefono, cliente_nombre
    FROM public.solicitudes_apertura
  UNION ALL
  SELECT 'captacion_prospectos', contacto_telefono, contacto_nombre
    FROM public.captacion_prospectos
),
limpio AS (
  SELECT
    fuente, crudo, nombre,
    ltrim(coalesce(crudo, '')) LIKE '+%' AS marca,
    CASE
      WHEN left(regexp_replace(coalesce(crudo,''), '[^0-9]', '', 'g'), 2) = '00'
        THEN substr(regexp_replace(coalesce(crudo,''), '[^0-9]', '', 'g'), 3)
      ELSE regexp_replace(coalesce(crudo,''), '[^0-9]', '', 'g')
    END AS d
  FROM fuentes
),
norm AS (
  SELECT
    fuente, crudo, nombre, d,
    CASE
      WHEN d = ''                              THEN NULL
      WHEN d ~ '^3[0-9]{9}$'                   THEN '+57' || d
      WHEN d ~ '^60[0-9]{8}$'                  THEN '+57' || d
      WHEN d ~ '^57(3[0-9]{9}|60[0-9]{8})$'    THEN '+'   || d
      WHEN d ~ '^3[0-9]{10}$'                  THEN NULL   -- ambiguo: ¿dedazo?
      WHEN d ~ '^[1-9][0-9]{7,14}$'
           AND (marca OR length(d) >= 11)      THEN '+'   || d
      ELSE NULL
    END AS e164
  FROM limpio
)

-- ---------------------------------------------------------------------
-- 1. Qué tan limpia está cada fuente
-- ---------------------------------------------------------------------
SELECT
  '1. por fuente'                                        AS seccion,
  fuente                                                 AS detalle,
  count(*)                                               AS filas,
  count(*) FILTER (WHERE e164 IS NOT NULL)               AS normalizan,
  count(*) FILTER (WHERE e164 IS NULL)                   AS no_normalizan,
  count(DISTINCT e164)                                   AS personas_distintas
FROM norm
GROUP BY fuente

UNION ALL

-- ---------------------------------------------------------------------
-- 2. El total: cuántos contactos crearía el backfill
-- ---------------------------------------------------------------------
SELECT
  '2. total',
  'todas las fuentes unificadas',
  count(*),
  count(*) FILTER (WHERE e164 IS NOT NULL),
  count(*) FILTER (WHERE e164 IS NULL),
  count(DISTINCT e164)
FROM norm

UNION ALL

-- ---------------------------------------------------------------------
-- 3. La gente que hoy está partida entre varias tablas.
--    Este número es el valor del proyecto en una cifra: son personas de
--    las que ya tenemos historial en más de un sitio y nadie lo ve junto.
-- ---------------------------------------------------------------------
SELECT
  '3. solapamiento',
  'personas presentes en ' || n_fuentes || ' fuente(s)',
  count(*), NULL, NULL, NULL
FROM (
  SELECT e164, count(DISTINCT fuente) AS n_fuentes
  FROM norm WHERE e164 IS NOT NULL
  GROUP BY e164
) t
GROUP BY n_fuentes

UNION ALL

-- ---------------------------------------------------------------------
-- 4. Qué forma tienen los que NO normalizan, para saber si hay que
--    mejorar la función o si simplemente son basura.
--    No muestra números: solo longitud y los dos primeros dígitos.
-- ---------------------------------------------------------------------
SELECT
  '4. los que no normalizan',
  CASE
    WHEN d = '' THEN 'vacío o sin dígitos'
    ELSE length(d)::text || ' dígitos, empieza por ' || left(d, 2)
  END,
  count(*), NULL, NULL, NULL
FROM norm
WHERE e164 IS NULL
GROUP BY 2

ORDER BY 1, 3 DESC NULLS LAST;
