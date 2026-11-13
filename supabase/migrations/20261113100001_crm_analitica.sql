-- =====================================================================
-- Analítica comercial (13 nov 2026)
--
-- LO QUE SE PIDIÓ
-- Una pantalla donde el equipo vea la actividad comercial por periodos
-- (hoy, última semana, últimos 30 días, último mes): leads atendidos,
-- citas agendadas, cuántos avanzan de etapa y dónde se mueren.
--
-- UNA SOLA FUNCIÓN, UNA SOLA IDA A LA BASE
-- crm.analitica(periodo, embudo) devuelve un jsonb con todo lo que pinta
-- la pantalla. Es SECURITY INVOKER: la RLS de quien mira decide qué
-- filas entran (su inmobiliaria), igual que en el tablero. No escribe
-- nada.
--
-- LAS DEFINICIONES (lo que significa cada número)
--  · Lead nuevo: oportunidad del embudo creada en el periodo.
--  · Conversación: contacto del embudo (tiene alguna oportunidad en él)
--    que escribió al menos un mensaje en el periodo.
--  · Atendida: a esa conversación le salió un mensaje DESPUÉS de su
--    primer mensaje del periodo, aunque saliera ya pasado el periodo.
--    «Por una persona» = alguno de esos mensajes es de origen humano.
--  · Tiempo de respuesta: mediana entre el primer mensaje del cliente en
--    el periodo y la primera respuesta (de cualquiera / de una persona).
--  · Cita agendada: fila de public.citas creada en el periodo (solo en el
--    embudo comercial). origen 'n8n' = la agendó el bot; 'app' = el
--    equipo.
--  · Avanzó: la oportunidad tuvo en el periodo al menos una transición a
--    una etapa de orden MAYOR del mismo embudo. No cuenta el primer
--    paso automático (Nuevo → Contactado cuando el bot contesta): lo da
--    todo lead, y con él «avanzaron» era igual a «leads nuevos» (medido
--    en producción el 13 nov: 2.438 y 2.438).
--  · Embudo del periodo: de los leads creados en el periodo, cuántos
--    llegaron a cada etapa. «Llegar» = la etapa más alta que tocaron
--    (actual o en el historial), porque las automáticas se pueden saltar.
--  · Dónde se mueren: oportunidades cerradas como perdidas en el periodo,
--    por la etapa en la que estaban y por motivo. Las reclasificadas
--    (es_captacion, es_administrativa, duplicado) NO son muertes y se
--    cuentan aparte.
--  · Estancadas: foto de AHORA, no del periodo: abiertas que llevan en su
--    etapa más días que su dias_pudricion.
--
-- EL PERIODO, EN BOGOTÁ
-- Se arma con crm.hoy() / crm.inicio_de_hoy(): la base corre en UTC.
--   hoy  → desde la medianoche hasta ahora; se compara con ayer a la
--          misma hora.
--   7d   → hoy y los 6 días anteriores; contra los 7 de antes.
--   30d  → hoy y los 29 anteriores; contra los 30 de antes.
--   mes  → el mes calendario anterior completo; contra el de antes.
--
-- Nace cerrada (20261001235001): el GRANT de abajo la abre a la pantalla.
-- =====================================================================

CREATE OR REPLACE FUNCTION crm.analitica(
  p_periodo text DEFAULT '30d',
  p_embudo  text DEFAULT 'comercial'
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path = ''
AS $analitica$
DECLARE
  z constant text := 'America/Bogota';
  v_hoy        date := crm.hoy();
  v_mes        date;
  v_desde      timestamptz;
  v_hasta      timestamptz;
  v_prev_desde timestamptz;
  v_prev_hasta timestamptz;
  v_unidad     text;
  v_kpis       jsonb;
  v_embudo     jsonb;
  v_cohorte    jsonb;
  v_muertes    jsonb;
  v_motivos    jsonb;
  v_reclasif   jsonb;
  v_estancadas jsonb;
  v_serie      jsonb;
  v_asesores   jsonb;
  v_flujos     jsonb;
  v_mensajes   jsonb;
  v_citas      jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM crm.embudos e WHERE e.codigo = p_embudo) THEN
    RAISE EXCEPTION 'Embudo desconocido: %', p_embudo USING ERRCODE = '22023';
  END IF;

  CASE p_periodo
    WHEN 'hoy' THEN
      v_desde := crm.inicio_de_hoy();
      v_hasta := now();
      v_prev_desde := v_desde - interval '1 day';
      v_prev_hasta := v_hasta - interval '1 day';
      v_unidad := 'hour';
    WHEN '7d' THEN
      v_desde := (v_hoy - 6)::timestamp AT TIME ZONE z;
      v_hasta := now();
      v_prev_desde := v_desde - interval '7 days';
      v_prev_hasta := v_desde;
      v_unidad := 'day';
    WHEN '30d' THEN
      v_desde := (v_hoy - 29)::timestamp AT TIME ZONE z;
      v_hasta := now();
      v_prev_desde := v_desde - interval '30 days';
      v_prev_hasta := v_desde;
      v_unidad := 'day';
    WHEN 'mes' THEN
      -- Sobre timestamp y no sobre date: date_trunc(date) pasa por
      -- timestamptz y cortaría el mes en UTC.
      v_mes := date_trunc('month', v_hoy::timestamp)::date;
      v_desde := (v_mes::timestamp - interval '1 month') AT TIME ZONE z;
      v_hasta := v_mes::timestamp AT TIME ZONE z;
      v_prev_desde := (v_mes::timestamp - interval '2 months') AT TIME ZONE z;
      v_prev_hasta := v_desde;
      v_unidad := 'day';
    ELSE
      RAISE EXCEPTION 'Periodo desconocido: % (hoy, 7d, 30d o mes)', p_periodo
        USING ERRCODE = '22023';
  END CASE;

  -- -------------------------------------------------------------------
  -- 1. Los indicadores, del periodo y del anterior
  -- -------------------------------------------------------------------
  WITH ventanas(k, desde, hasta) AS (
    VALUES ('actual', v_desde, v_hasta), ('anterior', v_prev_desde, v_prev_hasta)
  ),
  conv AS (
    SELECT v.k, a.contacto_id, min(a.ocurrido_at) AS primer_entrante
      FROM ventanas v
      JOIN crm.actividades a
        ON a.ocurrido_at >= v.desde AND a.ocurrido_at < v.hasta
     WHERE a.tipo = 'mensaje_entrante'
       AND a.contacto_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM crm.oportunidades o
                    WHERE o.contacto_id = a.contacto_id AND o.embudo = p_embudo)
     GROUP BY v.k, a.contacto_id
  ),
  resp AS (
    SELECT c.k, c.primer_entrante,
           (SELECT min(s.ocurrido_at) FROM crm.actividades s
             WHERE s.contacto_id = c.contacto_id
               AND s.tipo = 'mensaje_saliente'
               AND s.ocurrido_at >= c.primer_entrante) AS primera,
           (SELECT min(s.ocurrido_at) FROM crm.actividades s
             WHERE s.contacto_id = c.contacto_id
               AND s.tipo = 'mensaje_saliente'
               AND s.origen = 'humano'
               AND s.ocurrido_at >= c.primer_entrante) AS primera_humana
      FROM conv c
  ),
  k_conv AS (
    SELECT r.k,
           count(*) AS conversaciones,
           count(r.primera) AS atendidas,
           count(r.primera_humana) AS atendidas_humano,
           round((percentile_cont(0.5) WITHIN GROUP (
             ORDER BY extract(epoch FROM r.primera - r.primer_entrante)))::numeric / 60, 1)
             AS mediana_respuesta_min,
           round((percentile_cont(0.5) WITHIN GROUP (
             ORDER BY extract(epoch FROM r.primera_humana - r.primer_entrante)))::numeric / 60, 1)
             AS mediana_respuesta_humana_min
      FROM resp r
     GROUP BY r.k
  ),
  k_leads AS (
    SELECT v.k, count(o.id) AS leads_nuevos
      FROM ventanas v
      LEFT JOIN crm.oportunidades o
        ON o.embudo = p_embudo AND o.created_at >= v.desde AND o.created_at < v.hasta
     GROUP BY v.k
  ),
  k_cierres AS (
    SELECT v.k,
           count(o.id) FILTER (WHERE o.estado = 'ganada') AS ganadas,
           count(o.id) FILTER (WHERE o.estado = 'perdida'
             AND o.motivo_perdida NOT IN ('es_captacion', 'es_administrativa', 'duplicado')) AS perdidas
      FROM ventanas v
      LEFT JOIN crm.oportunidades o
        ON o.embudo = p_embudo AND o.cerrada_at >= v.desde AND o.cerrada_at < v.hasta
     GROUP BY v.k
  ),
  k_avances AS (
    SELECT v.k,
           count(DISTINCT t.oportunidad_id) FILTER (WHERE eh.orden > ed.orden
             AND NOT (ed.orden = 1 AND t.origen = 'sistema')) AS avanzaron,
           count(t.id) FILTER (WHERE eh.orden > ed.orden
             AND NOT (ed.orden = 1 AND t.origen = 'sistema')) AS avances
      FROM ventanas v
      LEFT JOIN crm.transiciones t
        ON t.ocurrido_at >= v.desde AND t.ocurrido_at < v.hasta
      LEFT JOIN crm.etapas ed ON ed.codigo = t.etapa_desde AND ed.embudo = p_embudo
      LEFT JOIN crm.etapas eh ON eh.codigo = t.etapa_hasta AND eh.embudo = p_embudo
     GROUP BY v.k
  ),
  k_citas AS (
    SELECT v.k,
           count(ci.id) AS citas_agendadas,
           count(ci.id) FILTER (WHERE ci.origen = 'n8n') AS citas_por_bot
      FROM ventanas v
      LEFT JOIN crm.v_citas ci
        ON p_embudo = 'comercial'
       AND ci.created_at >= v.desde AND ci.created_at < v.hasta
     GROUP BY v.k
  )
  SELECT jsonb_object_agg(v.k, jsonb_build_object(
           'leads_nuevos',                 l.leads_nuevos,
           'conversaciones',               coalesce(c.conversaciones, 0),
           'atendidas',                    coalesce(c.atendidas, 0),
           'atendidas_humano',             coalesce(c.atendidas_humano, 0),
           'mediana_respuesta_min',        c.mediana_respuesta_min,
           'mediana_respuesta_humana_min', c.mediana_respuesta_humana_min,
           'citas_agendadas',              ci.citas_agendadas,
           'citas_por_bot',                ci.citas_por_bot,
           'avanzaron',                    av.avanzaron,
           'avances',                      av.avances,
           'ganadas',                      ce.ganadas,
           'perdidas',                     ce.perdidas))
    INTO v_kpis
    FROM ventanas v
    JOIN k_leads l    ON l.k = v.k
    JOIN k_cierres ce ON ce.k = v.k
    JOIN k_avances av ON av.k = v.k
    JOIN k_citas ci   ON ci.k = v.k
    LEFT JOIN k_conv c ON c.k = v.k;

  -- -------------------------------------------------------------------
  -- 2. El embudo de los leads que entraron en el periodo
  -- -------------------------------------------------------------------
  WITH cohorte AS (
    SELECT o.id, o.estado,
           greatest(e.orden, coalesce((
             SELECT max(e2.orden)
               FROM crm.transiciones t
               JOIN crm.etapas e2 ON e2.codigo = t.etapa_hasta AND e2.embudo = p_embudo
              WHERE t.oportunidad_id = o.id), 0)) AS max_orden
      FROM crm.oportunidades o
      JOIN crm.etapas e ON e.codigo = o.etapa
     WHERE o.embudo = p_embudo
       AND o.created_at >= v_desde AND o.created_at < v_hasta
  )
  SELECT
    (SELECT coalesce(jsonb_agg(jsonb_build_object(
              'codigo',     e.codigo,
              'etiqueta',   e.etiqueta,
              'orden',      e.orden,
              'alcanzaron', (SELECT count(*) FROM cohorte c WHERE c.max_orden >= e.orden))
            ORDER BY e.orden), '[]'::jsonb)
       FROM crm.etapas e WHERE e.embudo = p_embudo),
    (SELECT jsonb_build_object(
              'total',    count(*),
              'abiertas', count(*) FILTER (WHERE c.estado = 'abierta'),
              'ganadas',  count(*) FILTER (WHERE c.estado = 'ganada'),
              'perdidas', count(*) FILTER (WHERE c.estado = 'perdida'))
       FROM cohorte c)
    INTO v_embudo, v_cohorte;

  -- -------------------------------------------------------------------
  -- 3. Dónde se mueren: perdidas del periodo, por etapa y por motivo
  -- -------------------------------------------------------------------
  WITH muertas AS (
    SELECT o.etapa, o.motivo_perdida
      FROM crm.oportunidades o
     WHERE o.embudo = p_embudo
       AND o.estado = 'perdida'
       AND o.cerrada_at >= v_desde AND o.cerrada_at < v_hasta
  )
  SELECT
    (SELECT coalesce(jsonb_agg(jsonb_build_object(
              'codigo', e.codigo, 'etiqueta', e.etiqueta, 'orden', e.orden,
              'perdidas', (SELECT count(*) FROM muertas m
                            WHERE m.etapa = e.codigo
                              AND m.motivo_perdida NOT IN ('es_captacion', 'es_administrativa', 'duplicado')))
            ORDER BY e.orden), '[]'::jsonb)
       FROM crm.etapas e WHERE e.embudo = p_embudo),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('motivo', x.motivo_perdida, 'cantidad', x.n)
                               ORDER BY x.n DESC), '[]'::jsonb)
       FROM (SELECT m.motivo_perdida, count(*) AS n FROM muertas m
              WHERE m.motivo_perdida NOT IN ('es_captacion', 'es_administrativa', 'duplicado')
              GROUP BY 1) x),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('motivo', x.motivo_perdida, 'cantidad', x.n)
                               ORDER BY x.n DESC), '[]'::jsonb)
       FROM (SELECT m.motivo_perdida, count(*) AS n FROM muertas m
              WHERE m.motivo_perdida IN ('es_captacion', 'es_administrativa', 'duplicado')
              GROUP BY 1) x)
    INTO v_muertes, v_motivos, v_reclasif;

  -- -------------------------------------------------------------------
  -- 4. Estancadas ahora mismo
  -- -------------------------------------------------------------------
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'codigo', e.codigo, 'etiqueta', e.etiqueta, 'orden', e.orden,
           'dias_pudricion', e.dias_pudricion,
           'abiertas',   (SELECT count(*) FROM crm.oportunidades o
                           WHERE o.embudo = p_embudo AND o.estado = 'abierta' AND o.etapa = e.codigo),
           'estancadas', (SELECT count(*) FROM crm.oportunidades o
                           WHERE o.embudo = p_embudo AND o.estado = 'abierta' AND o.etapa = e.codigo
                             AND e.dias_pudricion IS NOT NULL
                             AND o.etapa_at < now() - make_interval(days => e.dias_pudricion)))
         ORDER BY e.orden), '[]'::jsonb)
    INTO v_estancadas
    FROM crm.etapas e WHERE e.embudo = p_embudo;

  -- -------------------------------------------------------------------
  -- 5. La serie: por hora (hoy) o por día, en hora de Bogotá
  -- -------------------------------------------------------------------
  WITH cubetas AS (
    SELECT b AS inicio
      FROM generate_series(
             date_trunc(v_unidad, v_desde AT TIME ZONE z),
             date_trunc(v_unidad, (v_hasta - interval '1 second') AT TIME ZONE z),
             ('1 ' || v_unidad)::interval) b
  ),
  leads AS (
    SELECT date_trunc(v_unidad, o.created_at AT TIME ZONE z) AS b, count(*) AS n
      FROM crm.oportunidades o
     WHERE o.embudo = p_embudo AND o.created_at >= v_desde AND o.created_at < v_hasta
     GROUP BY 1
  ),
  msgs AS (
    SELECT date_trunc(v_unidad, a.ocurrido_at AT TIME ZONE z) AS b,
           count(DISTINCT a.contacto_id) FILTER (WHERE a.tipo = 'mensaje_entrante') AS conversaciones,
           count(*) FILTER (WHERE a.tipo = 'mensaje_saliente' AND a.origen = 'agente_ia') AS bot,
           count(*) FILTER (WHERE a.tipo = 'mensaje_saliente' AND a.origen = 'humano') AS humano
      FROM crm.actividades a
     WHERE a.ocurrido_at >= v_desde AND a.ocurrido_at < v_hasta
       AND a.tipo IN ('mensaje_entrante', 'mensaje_saliente')
       AND EXISTS (SELECT 1 FROM crm.oportunidades o
                    WHERE o.contacto_id = a.contacto_id AND o.embudo = p_embudo)
     GROUP BY 1
  ),
  citas AS (
    SELECT date_trunc(v_unidad, ci.created_at AT TIME ZONE z) AS b, count(*) AS n
      FROM crm.v_citas ci
     WHERE p_embudo = 'comercial'
       AND ci.created_at >= v_desde AND ci.created_at < v_hasta
     GROUP BY 1
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'inicio',         to_char(cu.inicio, 'YYYY-MM-DD"T"HH24:MI'),
           'leads',          coalesce(l.n, 0),
           'conversaciones', coalesce(m.conversaciones, 0),
           'mensajes_bot',   coalesce(m.bot, 0),
           'mensajes_humano', coalesce(m.humano, 0),
           'citas',          coalesce(ci.n, 0))
         ORDER BY cu.inicio), '[]'::jsonb)
    INTO v_serie
    FROM cubetas cu
    LEFT JOIN leads l  ON l.b = cu.inicio
    LEFT JOIN msgs m   ON m.b = cu.inicio
    LEFT JOIN citas ci ON ci.b = cu.inicio;

  -- -------------------------------------------------------------------
  -- 6. Por persona del equipo
  -- -------------------------------------------------------------------
  WITH act AS (
    SELECT a.creado_por AS usuario_id,
           count(*) FILTER (WHERE a.tipo = 'mensaje_saliente') AS mensajes,
           count(DISTINCT a.contacto_id) FILTER (WHERE a.tipo = 'mensaje_saliente') AS contactos,
           count(*) FILTER (WHERE a.tipo IN ('nota', 'llamada')) AS notas_llamadas
      FROM crm.actividades a
     WHERE a.ocurrido_at >= v_desde AND a.ocurrido_at < v_hasta
       AND a.origen = 'humano' AND a.creado_por IS NOT NULL
       AND EXISTS (SELECT 1 FROM crm.oportunidades o
                    WHERE o.contacto_id = a.contacto_id AND o.embudo = p_embudo)
     GROUP BY 1
  ),
  mov AS (
    SELECT t.usuario_id,
           count(*) FILTER (WHERE eh.orden > ed.orden) AS avances
      FROM crm.transiciones t
      JOIN crm.etapas ed ON ed.codigo = t.etapa_desde AND ed.embudo = p_embudo
      JOIN crm.etapas eh ON eh.codigo = t.etapa_hasta AND eh.embudo = p_embudo
     WHERE t.ocurrido_at >= v_desde AND t.ocurrido_at < v_hasta
       AND t.usuario_id IS NOT NULL
     GROUP BY 1
  ),
  cie AS (
    SELECT o.cerrada_por AS usuario_id,
           count(*) FILTER (WHERE o.estado = 'ganada') AS ganadas,
           count(*) FILTER (WHERE o.estado = 'perdida') AS perdidas
      FROM crm.oportunidades o
     WHERE o.embudo = p_embudo
       AND o.cerrada_at >= v_desde AND o.cerrada_at < v_hasta
       AND o.cerrada_por IS NOT NULL
     GROUP BY 1
  ),
  quienes AS (
    SELECT usuario_id FROM act UNION SELECT usuario_id FROM mov UNION SELECT usuario_id FROM cie
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'usuario_id',     q.usuario_id,
           'nombre',         coalesce(u.nombre_completo, u.email, 'Sin nombre'),
           'mensajes',       coalesce(a.mensajes, 0),
           'contactos',      coalesce(a.contactos, 0),
           'notas_llamadas', coalesce(a.notas_llamadas, 0),
           'avances',        coalesce(m.avances, 0),
           'ganadas',        coalesce(c.ganadas, 0),
           'perdidas',       coalesce(c.perdidas, 0))
         ORDER BY coalesce(a.contactos, 0) DESC, coalesce(a.mensajes, 0) DESC), '[]'::jsonb)
    INTO v_asesores
    FROM quienes q
    LEFT JOIN crm.v_asesores u ON u.id = q.usuario_id
    LEFT JOIN act a ON a.usuario_id = q.usuario_id
    LEFT JOIN mov m ON m.usuario_id = q.usuario_id
    LEFT JOIN cie c ON c.usuario_id = q.usuario_id;

  -- -------------------------------------------------------------------
  -- 7. Los movimientos más frecuentes entre etapas
  -- -------------------------------------------------------------------
  SELECT coalesce(jsonb_agg(x ORDER BY (x->>'cantidad')::int DESC), '[]'::jsonb)
    INTO v_flujos
    FROM (
      SELECT jsonb_build_object(
               'desde',     ed.etiqueta,
               'hasta',     eh.etiqueta,
               'avance',    eh.orden > ed.orden,
               'cantidad',  count(*),
               'por_equipo', count(*) FILTER (WHERE t.origen = 'humano')) AS x
        FROM crm.transiciones t
        JOIN crm.etapas ed ON ed.codigo = t.etapa_desde AND ed.embudo = p_embudo
        JOIN crm.etapas eh ON eh.codigo = t.etapa_hasta AND eh.embudo = p_embudo
       WHERE t.ocurrido_at >= v_desde AND t.ocurrido_at < v_hasta
       GROUP BY ed.etiqueta, eh.etiqueta, ed.orden, eh.orden
       ORDER BY count(*) DESC
       LIMIT 8
    ) f;

  -- -------------------------------------------------------------------
  -- 8. Mensajes y citas, desglosados
  -- -------------------------------------------------------------------
  SELECT jsonb_build_object(
           'entrantes',       count(*) FILTER (WHERE a.tipo = 'mensaje_entrante'),
           'salientes_bot',   count(*) FILTER (WHERE a.tipo = 'mensaje_saliente' AND a.origen = 'agente_ia'),
           'salientes_humano', count(*) FILTER (WHERE a.tipo = 'mensaje_saliente' AND a.origen = 'humano'),
           'salientes_sistema', count(*) FILTER (WHERE a.tipo = 'mensaje_saliente' AND a.origen = 'sistema'))
    INTO v_mensajes
    FROM crm.actividades a
   WHERE a.ocurrido_at >= v_desde AND a.ocurrido_at < v_hasta
     AND a.tipo IN ('mensaje_entrante', 'mensaje_saliente')
     AND EXISTS (SELECT 1 FROM crm.oportunidades o
                  WHERE o.contacto_id = a.contacto_id AND o.embudo = p_embudo);

  -- Las visitas cuya FECHA cae en el periodo: qué pasó con ellas.
  -- «Realizada» incluye la presunta (decisión 9: confirmada, fecha
  -- pasada, no cancelada), porque casi nadie marca la completada.
  SELECT jsonb_build_object(
           'programadas', count(*),
           'realizadas',  count(*) FILTER (WHERE ci.estado = 'completada'
                            OR (ci.estado = 'agendada' AND ci.confirmada_at IS NOT NULL AND ci.fecha < v_hoy)),
           'canceladas',  count(*) FILTER (WHERE ci.estado = 'cancelada'),
           'pendientes',  count(*) FILTER (WHERE ci.estado = 'agendada' AND ci.fecha >= v_hoy),
           'sin_confirmar', count(*) FILTER (WHERE ci.estado = 'agendada' AND ci.confirmada_at IS NULL AND ci.fecha < v_hoy))
    INTO v_citas
    FROM crm.v_citas ci
   WHERE p_embudo = 'comercial'
     AND ci.fecha >= (v_desde AT TIME ZONE z)::date
     AND ci.fecha <= ((v_hasta - interval '1 second') AT TIME ZONE z)::date;

  RETURN jsonb_build_object(
    'periodo', jsonb_build_object(
      'codigo', p_periodo,
      'desde',  to_char(v_desde AT TIME ZONE z, 'YYYY-MM-DD"T"HH24:MI'),
      'hasta',  to_char(v_hasta AT TIME ZONE z, 'YYYY-MM-DD"T"HH24:MI'),
      'unidad', v_unidad),
    'embudo_codigo', p_embudo,
    'kpis',          v_kpis,
    'embudo',        v_embudo,
    'cohorte',       v_cohorte,
    'perdidas_por_etapa',  v_muertes,
    'perdidas_por_motivo', v_motivos,
    'reclasificadas',      v_reclasif,
    'estancadas',    v_estancadas,
    'serie',         v_serie,
    'asesores',      v_asesores,
    'flujos',        v_flujos,
    'mensajes',      v_mensajes,
    'visitas',       v_citas);
END;
$analitica$;

COMMENT ON FUNCTION crm.analitica(text, text) IS
  'Analítica comercial de un periodo (hoy, 7d, 30d, mes) y un embudo, en un jsonb. SECURITY INVOKER: la RLS de quien mira decide. Definiciones en la migración 20261113100001.';

REVOKE ALL ON FUNCTION crm.analitica(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION crm.analitica(text, text) TO authenticated, service_role;
