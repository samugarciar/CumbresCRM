-- =====================================================================
-- La alerta de "pidió una persona" solo grita si TODAVÍA SIRVE GRITAR.
--
-- QUÉ SE VIO AL MIRARLO CON DATOS REALES
-- Con la primera versión, 266 oportunidades salían en rojo el día uno.
-- La razón: crm.lecturas nació vacía, así que literalmente nadie había
-- abierto nunca ninguna ficha y todo escalamiento contaba como
-- desatendido. Pero al medir su antigüedad:
--
--     hoy              2
--     esta semana     47
--     este mes       167
--     más de un mes   50
--
-- 217 de 266 tenían más de una semana. Un escalamiento de hace cinco
-- semanas que nadie atendió NO es una tarea pendiente: es historia. Y
-- una alerta que se enciende en todas partes deja de ser una alerta —
-- el día que aparezca la que sí importa, nadie la va a distinguir.
--
-- Por eso el rojo exige dos cosas, no una: que nadie haya llegado Y que
-- todavía se esté a tiempo. Las viejas siguen visibles, pero en gris:
-- son contexto, no trabajo.
-- =====================================================================

DROP FUNCTION IF EXISTS crm.tablero(int, text, uuid, boolean, text);

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
  -- Pidió una persona, nadie ha llegado, y todavía se está a tiempo.
  escalado_sin_atender    boolean,
  -- Pidió una persona y alguien abrió la ficha después.
  escalado_atendido       boolean,
  estancada               boolean,
  visita_realizada_origen text,
  total_en_etapa          bigint
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $tablero$
  WITH base AS (
    SELECT
      v.*,
      -- "Llegar" es que ALGUIEN del equipo haya abierto la ficha después
      -- de la escalada. No se mira si respondió por WhatsApp porque esa
      -- respuesta no pasa por nuestra base: la manda el asesor desde su
      -- teléfono.
      (v.escalado_at IS NOT NULL AND EXISTS (
        SELECT 1 FROM crm.lecturas l
         WHERE l.contacto_id = v.contacto_id
           AND l.visto_hasta >= v.escalado_at
      )) AS atendido
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
  ), filtradas AS (
    SELECT
      b.*,
      -- 48 horas. En un negocio donde el bot contesta en segundos y una
      -- visita se agenda para esta semana, pasado ese plazo el asunto ya
      -- no se arregla contestando: se arregla volviendo a empezar, que
      -- es otra conversación y otra tarjeta.
      (b.escalado_at IS NOT NULL
       AND NOT b.atendido
       AND b.escalado_at > now() - interval '48 hours') AS escalado_sin_atender
    FROM base b
  ), pendientes AS (
    SELECT f.* FROM filtradas f
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
    n.escalado_sin_atender, n.atendido, n.estancada,
    n.visita_realizada_origen, n.total_en_etapa
  FROM numeradas n
  WHERE n.n <= p_limite
  ORDER BY n.etapa_orden, n.n;
$tablero$;

COMMENT ON FUNCTION crm.tablero(int, text, uuid, boolean, text) IS
  'El kanban en una sola consulta. La alerta roja exige escalada reciente Y sin atender: una de hace cinco semanas es historia, no tarea.';

GRANT EXECUTE ON FUNCTION crm.tablero(int, text, uuid, boolean, text) TO authenticated;
