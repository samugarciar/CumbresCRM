-- =====================================================================
-- La caducidad del silencio.
--
-- LA REGLA, APROBADA POR SAMUEL
--   · Silencio MANUAL —alguien dijo "yo me encargo"— no caduca nunca.
--   · Silencio AUTOMÁTICO —lo supuso el sistema al escalar— caduca a los
--     3 días si nadie del equipo hizo nada.
--
-- POR QUÉ HACE FALTA, CON EL NÚMERO DELANTE
-- 48 conversaciones escalaron en los últimos 7 días: el apagado
-- automático va a callar el bot en ~7 leads al día. Con una sola asesora
-- entrando a diario, muchos quedan con el bot mudo y sin nadie detrás —
-- el cliente pide una persona y no le contesta ni la persona ni el bot.
--
-- ⚠️ LA TENSIÓN QUE ESTO NO RESUELVE, Y HAY QUE TENERLA PRESENTE
-- Hoy las respuestas de los asesores se escriben en Kommo y NO llegan al
-- CRM: hay 7.819 mensajes salientes y todos son del bot. Así que "nadie
-- atendió" no se puede medir de verdad todavía, y esta caducidad va a
-- reactivar el bot alguna vez sobre una conversación que un humano SÍ
-- estaba llevando. Se mitiga avisando en «Mi día» desde el primer día,
-- pero no desaparece hasta la fase 5-B. El día que el CRM vea los
-- mensajes salientes humanos, la señal se vuelve exacta y ya está puesta
-- la línea que la usará.
-- =====================================================================

-- ---------------------------------------------------------------------
-- El conjunto de los callados, indexado aparte
--
-- Tanto «Mi día» como el cron diario preguntan solo por los que tienen
-- el bot apagado, que son poquísimos frente al total. Un índice parcial
-- los deja en su propia estructura en vez de barrer los 1.350 contactos
-- cada vez, y crece con los callados, no con la base de clientes.
-- ---------------------------------------------------------------------
CREATE INDEX contactos_bot_callado
  ON crm.contactos (inmobiliaria_id, bot_cambiado_at)
  WHERE deleted_at IS NULL AND NOT bot_activo;

-- ---------------------------------------------------------------------
-- ¿Alguien del equipo hizo algo por esta persona desde tal momento?
--
-- Cuentan solo los ACTOS DELIBERADOS: dejar una nota, crear una tarea,
-- mover el lead de etapa. Y el mensaje saliente humano, que hoy no
-- existe pero existirá — la cláusula ya está escrita para que la fase
-- 5-B no tenga que volver aquí.
--
-- NO cuenta abrir la ficha. Marcarla como leída pasa solo al entrar, así
-- que significa "le eché un ojo", no "lo atendí": si contara, un lead que
-- alguien mira cada día sin contestarle nunca mantendría el bot callado
-- para siempre.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.bot_atendido_desde(
  p_contacto_id uuid,
  p_desde       timestamptz)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $at$
  SELECT
    EXISTS (SELECT 1 FROM crm.actividades a
             WHERE a.contacto_id = p_contacto_id
               AND a.ocurrido_at > p_desde
               AND ((a.tipo = 'nota' AND a.creado_por IS NOT NULL)
                 OR (a.tipo = 'mensaje_saliente' AND a.origen = 'humano')))
    OR EXISTS (SELECT 1 FROM crm.tareas t
                WHERE t.contacto_id = p_contacto_id
                  AND t.created_at > p_desde)
    OR EXISTS (SELECT 1 FROM crm.transiciones tr
                JOIN crm.oportunidades o ON o.id = tr.oportunidad_id
               WHERE o.contacto_id = p_contacto_id
                 AND tr.origen = 'humano'
                 AND tr.ocurrido_at > p_desde);
$at$;

COMMENT ON FUNCTION crm.bot_atendido_desde(uuid, timestamptz) IS
  'Sustituto de "un humano atendió": actos deliberados en el CRM. Abrir la ficha NO cuenta. Se vuelve exacto con la fase 5-B.';

GRANT EXECUTE ON FUNCTION crm.bot_atendido_desde(uuid, timestamptz) TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- Devolverle la voz al bot cuando nadie llegó
--
-- Solo toca el silencio con motivo 'escalamiento'. El manual se queda
-- como está para siempre, y es deliberado: alguien dijo que se encargaba,
-- y reactivar el bot a su espalda podría meterlo en medio de una
-- negociación delicada.
--
-- Deja rastro en el historial, como todo lo que cambia el estado del bot.
-- Un bot que vuelve a hablar sin que conste por qué es exactamente el
-- tipo de cosa que nadie consigue explicar tres semanas después.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.reactivar_bots(p_dias smallint DEFAULT 3)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $re$
DECLARE
  v_n integer;
BEGIN
  WITH vencidos AS (
    UPDATE crm.contactos c
       SET bot_activo       = true,
           bot_motivo       = NULL,
           bot_cambiado_at  = now(),
           bot_cambiado_por = NULL
     WHERE c.deleted_at IS NULL
       AND NOT c.bot_activo
       AND c.bot_motivo = 'escalamiento'
       AND c.bot_cambiado_at < now() - make_interval(days => p_dias)
       AND NOT crm.bot_atendido_desde(c.id, c.bot_cambiado_at)
    RETURNING c.id AS contacto_id, c.inmobiliaria_id
  ), rastro AS (
    INSERT INTO crm.actividades
      (inmobiliaria_id, tipo, origen, contacto_id, cuerpo)
    SELECT v.inmobiliaria_id, 'sistema', 'sistema', v.contacto_id,
           'El bot vuelve a responderle: pasaron ' || p_dias ||
           ' días desde que pidió hablar con una persona y nadie del equipo llegó.'
      FROM vencidos v
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_n FROM vencidos;
  RETURN v_n;
END $re$;

COMMENT ON FUNCTION crm.reactivar_bots(smallint) IS
  'Devuelve la voz al bot en los leads que escalaron hace más de N días sin que nadie los atendiera. El silencio manual NUNCA caduca.';

-- ---------------------------------------------------------------------
-- «Mi día» aprende a avisar, y por eso se reescribe entera
--
-- Se avisa DESDE EL PRIMER DÍA, no al vencer el plazo: la reactivación
-- automática tiene que ser la red de seguridad, no la sorpresa. El asesor
-- tiene tres días para llegar antes que el bot.
--
-- La rama nueva entra como prioridad 7 y «estancada» pasa a 8. Va al
-- bloque de "se está enfriando" y no al de urgencia a propósito: las
-- primeras 48 horas ya salen arriba como «escalado», y este proyecto ya
-- se peleó dos veces con alertas que gritaban tanto que dejaron de
-- leerse.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.mi_dia(p_limite int DEFAULT 60)
RETURNS TABLE (
  prioridad    smallint,
  tipo         text,
  titulo       text,
  detalle      text,
  cuando       timestamptz,
  contacto_id  uuid,
  nombre       text,
  telefono_e164 text,
  tarea_id     uuid,
  cita_id      uuid
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $dia$
  -- Las columnas se nombran aquí: un UNION las deja anónimas y el
  -- ORDER BY de abajo no tendría a qué agarrarse.
  WITH todo (prioridad, tipo, titulo, detalle, cuando,
             contacto_id, nombre, telefono_e164, tarea_id, cita_id) AS (
    -- 1 · Pidió una persona y nadie ha llegado. Lo único de esta lista
    --     que se pierde por no mirarlo a tiempo.
    SELECT 1::smallint, 'escalado'::text,
           'Pidió hablar con una persona'::text,
           c.nombre || ' escribió y sigue esperando'::text,
           o.escalado_at, c.id, c.nombre, c.telefono_e164,
           NULL::uuid, NULL::uuid
    FROM crm.oportunidades o
    JOIN crm.contactos c ON c.id = o.contacto_id AND c.deleted_at IS NULL
    WHERE o.estado = 'abierta'
      AND o.escalado_at IS NOT NULL
      AND o.escalado_at > now() - interval '48 hours'
      AND NOT EXISTS (SELECT 1 FROM crm.lecturas l
                       WHERE l.contacto_id = o.contacto_id
                         AND l.visto_hasta >= o.escalado_at)

    UNION ALL
    -- 2 · Visitas de hoy. Tienen hora: o se atienden o se pierden.
    SELECT 2::smallint, 'visita_hoy',
           'Visita ' || to_char(ci.hora_inicio, 'HH24:MI'),
           COALESCE(ci.cliente_nombre, 'Sin nombre') || ' · ' ||
             COALESCE(i.titulo, 'inmueble'),
           (ci.fecha + ci.hora_inicio) AT TIME ZONE 'America/Bogota',
           a.contacto_id, c.nombre, c.telefono_e164, NULL, ci.id
    FROM public.citas ci
    LEFT JOIN public.inmuebles i ON i.id = ci.inmueble_id
    LEFT JOIN crm.actividades a ON a.cita_id = ci.id AND a.tipo = 'visita_agendada'
    LEFT JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE ci.estado = 'agendada' AND ci.fecha = current_date

    UNION ALL
    -- 3 · Tareas vencidas. Se prometieron y no se hicieron.
    SELECT 3::smallint, 'tarea_vencida', t.titulo,
           COALESCE(c.nombre, 'Sin contacto'),
           t.vence_at, t.contacto_id, c.nombre, c.telefono_e164, t.id, NULL
    FROM crm.tareas t
    LEFT JOIN crm.contactos c ON c.id = t.contacto_id
    WHERE t.completada_at IS NULL AND t.vence_at < date_trunc('day', now())

    UNION ALL
    -- 4 · Visitas que pasaron sin cerrar. En producción llevaban 527
    --     citas y CERO marcadas: el dato se pierde cada día que pasa.
    SELECT 4::smallint, 'visita_sin_cerrar',
           'Cerrar la visita del ' || to_char(ci.fecha, 'DD/MM'),
           COALESCE(ci.cliente_nombre, 'Sin nombre'),
           (ci.fecha + ci.hora_fin) AT TIME ZONE 'America/Bogota',
           a.contacto_id, c.nombre, c.telefono_e164, NULL, ci.id
    FROM public.citas ci
    LEFT JOIN crm.actividades a ON a.cita_id = ci.id AND a.tipo = 'visita_agendada'
    LEFT JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE ci.estado = 'agendada'
      AND ci.fecha < current_date
      AND ci.fecha >= current_date - 14   -- más atrás ya es historia

    UNION ALL
    -- 5 · Tareas de hoy.
    SELECT 5::smallint, 'tarea_hoy', t.titulo,
           COALESCE(c.nombre, 'Sin contacto'),
           t.vence_at, t.contacto_id, c.nombre, c.telefono_e164, t.id, NULL
    FROM crm.tareas t
    LEFT JOIN crm.contactos c ON c.id = t.contacto_id
    WHERE t.completada_at IS NULL
      AND t.vence_at >= date_trunc('day', now())
      AND t.vence_at <  date_trunc('day', now()) + interval '1 day'

    UNION ALL
    -- 6 · Tareas de la plataforma de inventario. Se LEEN, no se tocan:
    --     son de otro repo. Pero el asesor no debería tener dos sitios
    --     donde mirar, que es justo lo que esta pantalla viene a evitar.
    SELECT 6::smallint, 'tarea_plataforma', pt.titulo,
           COALESCE(pt.evento_titulo, 'Plataforma de inventario'),
           pt.created_at, NULL, NULL, NULL, NULL, NULL
    FROM public.tareas pt
    WHERE pt.estado = 'pendiente'

    UNION ALL
    -- 7 · El bot lleva días callado y nadie ha atendido a la persona.
    --     Esta es la red de seguridad de la caducidad: el bot vuelve solo
    --     a los 3 días, y esto está para que un humano llegue antes.
    --
    --     Las primeras 48 horas ya salen arriba como «escalado» mientras
    --     nadie abra la ficha, así que esas se excluyen: decir dos veces
    --     lo mismo en la misma pantalla es cómo se pierde la confianza en
    --     una lista de tareas.
    --
    --     La antigüedad no va en el título: `cuando` la pinta sola como
    --     «hace 2 días», igual que en el resto de la pantalla.
    SELECT 7::smallint, 'bot_callado',
           'El bot está callado y nadie ha llegado',
           COALESCE(c.nombre, 'Sin nombre') || ' pidió hablar con una persona',
           c.bot_cambiado_at, c.id, c.nombre, c.telefono_e164,
           NULL, NULL
    FROM crm.contactos c
    WHERE c.deleted_at IS NULL
      AND NOT c.bot_activo
      AND c.bot_motivo = 'escalamiento'
      AND NOT crm.bot_atendido_desde(c.id, c.bot_cambiado_at)
      AND NOT EXISTS (
        SELECT 1 FROM crm.oportunidades o
         WHERE o.contacto_id = c.id
           AND o.estado = 'abierta'
           AND o.escalado_at > now() - interval '48 hours'
           AND NOT EXISTS (SELECT 1 FROM crm.lecturas l
                            WHERE l.contacto_id = c.id
                              AND l.visto_hasta >= o.escalado_at))

    UNION ALL
    -- 8 · Estancadas. Importan, pero seguirán ahí mañana: van al final a
    --     propósito, para que no tapen lo que sí se pierde hoy.
    SELECT 8::smallint, 'estancada',
           'Lleva demasiado quieta',
           v.nombre || ' · ' || v.etapa_etiqueta,
           v.ultima_actividad_at, v.contacto_id, v.nombre, v.telefono_e164,
           NULL, NULL
    FROM crm.v_oportunidades v
    WHERE v.estado = 'abierta' AND v.estancada
  )
  SELECT * FROM todo
  ORDER BY prioridad, cuando NULLS LAST
  LIMIT p_limite;
$dia$;

GRANT EXECUTE ON FUNCTION crm.mi_dia(int) TO authenticated;

-- ---------------------------------------------------------------------
-- A diario, no cada cinco minutos: el plazo se mide en días.
-- A las 8, antes del cierre de fantasmas de las 9.
-- ---------------------------------------------------------------------
DO $agenda$
BEGIN
  PERFORM cron.schedule(
    'crm_reactivar_bots', '0 8 * * *',
    $trabajo$SELECT crm.reactivar_bots(3);$trabajo$);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron no disponible; habrá que agendar crm.reactivar_bots() a mano: %', SQLERRM;
END $agenda$;
