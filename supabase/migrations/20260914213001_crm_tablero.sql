-- =====================================================================
-- Fase 2-B — La lectura del tablero.
--
-- POR QUÉ ESTO ES UNA FUNCIÓN Y NO SEIS CONSULTAS
-- Un kanban necesita, por cada columna, las primeras N tarjetas Y el
-- total de la columna. Hecho desde la aplicación son doce viajes a la
-- base para pintar una pantalla. Aquí es uno.
--
-- Y HACE FALTA EL LÍMITE POR COLUMNA
-- "Contactado" tiene 845 oportunidades en producción el día uno.
-- Pintarlas todas serían 845 tarjetas en el DOM de una columna que nadie
-- va a recorrer entera. Se piden las primeras y se dice cuántas hay.
-- =====================================================================

-- ---------------------------------------------------------------------
-- El orden dentro de cada columna NO es cronológico
--
-- Es por urgencia, que es lo que un asesor necesita arriba:
--   1. Pidió un humano y NADIE ha abierto la ficha desde entonces
--   2. Estancada: lleva más días de los que su etapa tolera
--   3. El resto, por actividad más reciente
--
-- El primer criterio es el que ningún CRM revisado tiene, y solo se
-- puede calcular porque crm.lecturas sabe quién ha mirado qué.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.tablero(
  p_limite         int     DEFAULT 40,
  p_zona           text    DEFAULT NULL,
  p_asesor         uuid    DEFAULT NULL,
  p_solo_pendiente boolean DEFAULT NULL,
  p_texto          text    DEFAULT NULL)
RETURNS TABLE (
  id                      uuid,
  contacto_id             uuid,
  etapa                   text,
  etapa_orden             smallint,
  nombre                  text,
  telefono_e164           text,
  zona                    text,
  ultima_actividad_at     timestamptz,
  etapa_at                timestamptz,
  escalado_at             timestamptz,
  escalado_sin_atender    boolean,
  estancada               boolean,
  visita_realizada_origen text,
  total_en_etapa          bigint
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $tablero$
  WITH filtradas AS (
    SELECT
      v.*,
      -- La pregunta que ningún CRM del mercado responde: el bot pidió un
      -- humano, ¿y ha llegado alguno? "Llegar" = que ALGUIEN del equipo
      -- haya abierto la ficha DESPUÉS de la escalada. No se mira si
      -- respondió por WhatsApp porque esa respuesta no pasa por nuestra
      -- base: la manda el asesor desde su teléfono.
      (v.escalado_at IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM crm.lecturas l
          WHERE l.contacto_id = v.contacto_id
            AND l.visto_hasta >= v.escalado_at
       )) AS escalado_sin_atender
    FROM crm.v_oportunidades v
    WHERE v.estado = 'abierta'
      AND (p_zona   IS NULL OR v.zona = p_zona)
      AND (p_asesor IS NULL OR v.asesor_id = p_asesor)
      AND (
        p_texto IS NULL
        OR v.telefono_e164 ILIKE '%' || p_texto || '%'
        OR public.unaccent(COALESCE(v.nombre, ''))
             ILIKE '%' || public.unaccent(p_texto) || '%'
      )
  ), pendientes AS (
    SELECT f.* FROM filtradas f
     -- El filtro que convierte el tablero en una lista de trabajo.
     WHERE p_solo_pendiente IS NOT TRUE
        OR f.escalado_sin_atender
        OR f.estancada
  ), numeradas AS (
    SELECT
      p.*,
      row_number() OVER (
        PARTITION BY p.etapa
        ORDER BY p.escalado_sin_atender DESC,
                 p.estancada DESC,
                 p.ultima_actividad_at DESC NULLS LAST,
                 p.id
      ) AS n,
      count(*) OVER (PARTITION BY p.etapa) AS total_en_etapa
    FROM pendientes p
  )
  SELECT
    n.id, n.contacto_id, n.etapa, n.etapa_orden, n.nombre, n.telefono_e164,
    n.zona, n.ultima_actividad_at, n.etapa_at, n.escalado_at,
    n.escalado_sin_atender, n.estancada, n.visita_realizada_origen,
    n.total_en_etapa
  FROM numeradas n
  WHERE n.n <= p_limite
  ORDER BY n.etapa_orden, n.n;
$tablero$;

COMMENT ON FUNCTION crm.tablero(int, text, uuid, boolean, text) IS
  'El kanban en una sola consulta: las primeras N por columna, ordenadas por urgencia, más el total de cada columna.';

GRANT EXECUTE ON FUNCTION crm.tablero(int, text, uuid, boolean, text) TO authenticated;

-- ---------------------------------------------------------------------
-- Las zonas que existen de verdad
--
-- Para poblar el filtro sin inventarse una lista: salen de los datos,
-- que en producción son 'Bello' y 'Medellin' recuperados del vocabulario
-- de Kommo.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.zonas()
RETURNS TABLE (zona text, oportunidades bigint)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $zonas$
  SELECT o.zona, count(*)
    FROM crm.oportunidades o
   WHERE o.estado = 'abierta' AND o.zona IS NOT NULL
   GROUP BY o.zona
   ORDER BY 2 DESC;
$zonas$;

GRANT EXECUTE ON FUNCTION crm.zonas() TO authenticated;
