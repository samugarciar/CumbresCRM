-- =====================================================================
-- «Hoy» es el de Colombia, no el de la base (26 oct 2026)
--
-- LO QUE PASABA
-- La base corre en UTC. current_date y date_trunc('day', now()) dan el
-- día de Greenwich, que en Colombia empieza a las 7 p. m. Desde esa hora
-- y hasta la medianoche, «Mi día» enseñaba como «de hoy» las visitas de
-- MAÑANA, daba por vencidas las tareas que vencían esa noche y escondía
-- las visitas de hoy que aún no se cerraban. Lo mismo, con menos ruido,
-- en crm.orden_por_evidencia (la visita presunta) y en
-- crm.cerrar_fantasmas (no cierra a quien tiene una visita por delante).
--
-- LAS PIEZAS
--  1. crm.hoy() y crm.inicio_de_hoy(): el día de Bogotá y su medianoche
--     como timestamptz. Toda función nueva que necesite «hoy» las usa.
--  2. mi_dia, orden_por_evidencia y cerrar_fantasmas las usan en vez de
--     current_date y date_trunc('day', now()). Revisado con grep sobre
--     pg_proc: no queda ninguna otra función de crm con current_date
--     (en_horario_envio ya convierte con la zona del horario).
--  3. De paso, en mi_dia:
--     · las tareas del CRM que ve un asesor son las suyas y las que no
--       tienen a nadie asignado; la admin las ve todas. Antes Julián veía
--       «Mandar plomero…», que es de Mariana;
--     · el detalle ya no queda vacío cuando el contacto no tiene nombre:
--       coalesce(nombre, teléfono, 'Sin nombre');
--     · un escalado cuenta como atendido solo si alguien del equipo HIZO
--       algo después de que pidió una persona (crm.bot_atendido_desde:
--       un mensaje, una nota, una tarea, un cambio de etapa). Abrir la
--       ficha (crm.lecturas) ya no cuenta: mirar no es atender.
--  4. La misma regla de atendido en crm.tablero.
--
-- Mismas firmas y mismos permisos. Idempotente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Hoy, en Bogotá
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.hoy()
RETURNS date
LANGUAGE sql STABLE SET search_path = ''
AS $hoy$ SELECT (now() AT TIME ZONE 'America/Bogota')::date; $hoy$;

COMMENT ON FUNCTION crm.hoy() IS
  'El día de hoy en Colombia. La base corre en UTC: current_date cambia de día a las 7 p. m. de Bogotá.';

REVOKE ALL ON FUNCTION crm.hoy() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION crm.hoy() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION crm.inicio_de_hoy()
RETURNS timestamptz
LANGUAGE sql STABLE SET search_path = ''
AS $inicio$ SELECT crm.hoy()::timestamp AT TIME ZONE 'America/Bogota'; $inicio$;

COMMENT ON FUNCTION crm.inicio_de_hoy() IS
  'La medianoche de hoy en Colombia, como timestamptz. Reemplaza a date_trunc(''day'', now()), que corta en UTC.';

REVOKE ALL ON FUNCTION crm.inicio_de_hoy() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION crm.inicio_de_hoy() TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- 2. Mi día
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.mi_dia(p_limite integer DEFAULT 60, p_asesor uuid DEFAULT NULL)
RETURNS TABLE(prioridad smallint, tipo text, titulo text, detalle text, cuando timestamptz,
              contacto_id uuid, nombre text, telefono_e164 text, tarea_id uuid, cita_id uuid)
LANGUAGE sql STABLE SET search_path = ''
AS $mi_dia$
  WITH yo AS (
    -- La admin ve todas las tareas del CRM; un asesor, las suyas y las
    -- que no tienen a nadie asignado.
    SELECT EXISTS (
      SELECT 1 FROM crm.v_asesores u
       WHERE u.id = (SELECT auth.uid()) AND u.rol = 'admin'
    ) AS es_admin
  ),
  todo (prioridad, tipo, titulo, detalle, cuando,
        contacto_id, nombre, telefono_e164, tarea_id, cita_id, asignado_a) AS (
    -- 1 · Escalamiento comercial: pidió una persona y nadie del equipo ha
    --     hecho nada desde entonces. Abrir la ficha no cuenta.
    SELECT 1::smallint, 'escalado'::text,
           'Pidió hablar con una persona'::text,
           COALESCE(c.nombre, c.telefono_e164, 'Sin nombre') || ' escribió y sigue esperando'::text,
           o.escalado_at, c.id, c.nombre, c.telefono_e164,
           NULL::uuid, NULL::uuid, NULL::uuid
    FROM crm.oportunidades o
    JOIN crm.contactos c ON c.id = o.contacto_id AND c.deleted_at IS NULL
    WHERE o.estado = 'abierta'
      AND o.embudo = 'comercial'
      AND o.escalado_at IS NOT NULL
      AND o.escalado_at > now() - crm.ventana_escalamiento()
      AND NOT crm.bot_atendido_desde(c.id, o.escalado_at)

    UNION ALL
    -- 1-bis · Envío fallido
    SELECT 1::smallint, 'envio_fallido',
           'No le llegó el mensaje',
           COALESCE(c.nombre, c.telefono_e164, 'Sin nombre') || ' · ' ||
             COALESCE(e.error, 'WhatsApp lo rechazó'),
           COALESCE(e.fallido_at, e.created_at), c.id, c.nombre, c.telefono_e164,
           NULL, NULL, NULL
    FROM crm.envios e
    JOIN crm.contactos c ON c.id = e.contacto_id AND c.deleted_at IS NULL
    WHERE e.estado = 'fallido'
      AND e.visto_at IS NULL
      AND COALESCE(e.fallido_at, e.created_at) > now() - interval '14 days'

    UNION ALL
    -- 2 · Visitas de hoy (hoy en Bogotá)
    SELECT 2::smallint, 'visita_hoy',
           'Visita ' || to_char(ci.hora_inicio, 'HH24:MI'),
           COALESCE(ci.cliente_nombre, c.nombre, c.telefono_e164, 'Sin nombre') || ' · ' ||
             COALESCE(i.titulo, 'inmueble'),
           (ci.fecha + ci.hora_inicio) AT TIME ZONE 'America/Bogota',
           a.contacto_id, c.nombre, c.telefono_e164, NULL, ci.id, NULL
    FROM public.citas ci
    LEFT JOIN public.inmuebles i ON i.id = ci.inmueble_id
    LEFT JOIN crm.actividades a ON a.cita_id = ci.id AND a.tipo = 'visita_agendada'
    LEFT JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE ci.estado = 'agendada' AND ci.fecha = crm.hoy()

    UNION ALL
    -- 3 · Tareas vencidas (antes de la medianoche de Bogotá)
    SELECT 3::smallint, 'tarea_vencida', t.titulo,
           COALESCE(c.nombre, c.telefono_e164, 'Sin contacto'),
           t.vence_at, t.contacto_id, c.nombre, c.telefono_e164, t.id, NULL, t.asignado_a
    FROM crm.tareas t
    LEFT JOIN crm.contactos c ON c.id = t.contacto_id
    WHERE t.completada_at IS NULL
      AND t.vence_at < crm.inicio_de_hoy()
      AND (p_asesor IS NULL OR t.asignado_a IS NULL OR t.asignado_a = p_asesor
           OR (SELECT es_admin FROM yo))

    UNION ALL
    -- 4 · Visitas que pasaron sin cerrar (antes de hoy en Bogotá)
    SELECT 4::smallint, 'visita_sin_cerrar',
           'Cerrar la visita del ' || to_char(ci.fecha, 'DD/MM'),
           COALESCE(ci.cliente_nombre, c.nombre, c.telefono_e164, 'Sin nombre'),
           (ci.fecha + ci.hora_fin) AT TIME ZONE 'America/Bogota',
           a.contacto_id, c.nombre, c.telefono_e164, NULL, ci.id, NULL
    FROM public.citas ci
    LEFT JOIN crm.actividades a ON a.cita_id = ci.id AND a.tipo = 'visita_agendada'
    LEFT JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE ci.estado = 'agendada'
      AND ci.fecha < crm.hoy()
      AND ci.fecha >= crm.hoy() - 14

    UNION ALL
    -- 5 · Tareas de hoy (entre las dos medianoches de Bogotá)
    SELECT 5::smallint, 'tarea_hoy', t.titulo,
           COALESCE(c.nombre, c.telefono_e164, 'Sin contacto'),
           t.vence_at, t.contacto_id, c.nombre, c.telefono_e164, t.id, NULL, t.asignado_a
    FROM crm.tareas t
    LEFT JOIN crm.contactos c ON c.id = t.contacto_id
    WHERE t.completada_at IS NULL
      AND t.vence_at >= crm.inicio_de_hoy()
      AND t.vence_at <  crm.inicio_de_hoy() + interval '1 day'
      AND (p_asesor IS NULL OR t.asignado_a IS NULL OR t.asignado_a = p_asesor
           OR (SELECT es_admin FROM yo))

    UNION ALL
    -- 6 · Tareas de la plataforma de inventario
    SELECT 6::smallint, 'tarea_plataforma', pt.titulo,
           COALESCE(pt.evento_titulo, 'Plataforma de inventario'),
           pt.created_at, NULL, NULL, NULL, NULL, NULL, NULL
    FROM public.tareas pt
    WHERE pt.estado = 'pendiente'

    UNION ALL
    -- 7 · Bot callado comercial que nadie ha atendido y que no sale ya
    --     arriba como escalamiento reciente.
    SELECT 7::smallint, 'bot_callado',
           'El bot está callado y nadie ha llegado',
           COALESCE(c.nombre, c.telefono_e164, 'Sin nombre') || ' pidió hablar con una persona',
           c.bot_cambiado_at, c.id, c.nombre, c.telefono_e164,
           NULL, NULL, NULL
    FROM crm.contactos c
    WHERE c.deleted_at IS NULL
      AND NOT c.bot_activo
      AND c.bot_motivo = 'escalamiento'
      AND NOT crm.bot_atendido_desde(c.id, c.bot_cambiado_at)
      AND NOT EXISTS (
        SELECT 1 FROM crm.oportunidades o
         WHERE o.contacto_id = c.id
           AND o.estado = 'abierta'
           AND o.embudo = 'comercial'
           AND o.escalado_at > now() - crm.ventana_escalamiento()
           AND NOT crm.bot_atendido_desde(c.id, o.escalado_at))

    UNION ALL
    -- 8 · Estancadas: SOLO comerciales
    SELECT 8::smallint, 'estancada',
           'Lleva demasiado quieta',
           COALESCE(v.nombre, v.telefono_e164, 'Sin nombre') || ' · ' || v.etapa_etiqueta,
           v.ultima_actividad_at, v.contacto_id, v.nombre, v.telefono_e164,
           NULL, NULL, NULL
    FROM crm.v_oportunidades v
    WHERE v.estado = 'abierta'
      AND v.embudo = 'comercial'
      AND v.estancada
  )
  SELECT t.prioridad, t.tipo, t.titulo, t.detalle, t.cuando,
         t.contacto_id, t.nombre, t.telefono_e164, t.tarea_id, t.cita_id
    FROM todo t
    LEFT JOIN crm.oportunidades o
      ON o.contacto_id = t.contacto_id AND o.estado = 'abierta'
     AND o.embudo = 'comercial'
   WHERE p_asesor IS NULL
      OR o.asesor_id IS NULL
      OR o.asesor_id = p_asesor
      -- Una tarea asignada a quien mira (o cualquiera, si es la admin) se
      -- ve aunque la oportunidad del contacto la lleve otro.
      OR (t.tarea_id IS NOT NULL
          AND (t.asignado_a = p_asesor OR (SELECT es_admin FROM yo)))
   ORDER BY t.prioridad ASC, t.cuando ASC NULLS LAST
   LIMIT p_limite;
$mi_dia$;

COMMENT ON FUNCTION crm.mi_dia(int, uuid) IS
  'El día de quien mira, por prioridad. «Hoy» es el de Bogotá (crm.hoy). Tareas: las suyas y las sin '
  'asignar (la admin, todas). Un escalado está atendido solo si alguien hizo algo después (crm.bot_atendido_desde).';

-- ---------------------------------------------------------------------
-- 3. La visita presunta, con el día de Bogotá
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.orden_por_evidencia(p_contacto_id uuid)
RETURNS smallint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $evidencia$
  SELECT GREATEST(
    1::smallint,   -- nuevo: existir ya es el primer peldaño

    COALESCE((
      SELECT MAX(CASE
        WHEN a.tipo = 'visita_realizada' THEN 5
        WHEN a.tipo = 'visita_agendada'  THEN 4
        WHEN a.tipo IN ('llamada', 'solicitud_apertura') THEN 2
        -- Mensajes: solo cuentan si fueron por la línea comercial o son de Kommo (sin número).
        WHEN a.tipo IN ('mensaje_entrante', 'mensaje_saliente') AND (
          a.wa_phone_number_id IS NULL OR EXISTS (
            SELECT 1 FROM crm.lineas l
             WHERE l.wa_phone_number_id = a.wa_phone_number_id
               AND l.embudo = 'comercial'
          )
        ) THEN 2
        ELSE 1
      END) FROM crm.actividades a WHERE a.contacto_id = p_contacto_id
    ), 1)::smallint,

    -- CALIFICADO (3): dijo qué busca.
    COALESCE((
      SELECT 3::smallint FROM crm.requerimientos r
       WHERE r.contacto_id = p_contacto_id AND r.activo LIMIT 1
    ), 1)::smallint,

    -- La visita PRESUNTA: estaba confirmada, la fecha pasó (en Bogotá) y
    -- nadie la canceló.
    COALESCE((
      SELECT 5::smallint
        FROM crm.actividades a2
        JOIN public.citas ci ON ci.id = a2.cita_id
       WHERE a2.contacto_id = p_contacto_id
         AND a2.cita_id IS NOT NULL
         AND ci.confirmada_at IS NOT NULL
         AND ci.estado = 'agendada'
         AND ci.fecha < crm.hoy()
       LIMIT 1
    ), 1)::smallint
  );
$evidencia$;

-- ---------------------------------------------------------------------
-- 4. Los fantasmas: no se cierra a quien tiene una visita hoy o después
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.cerrar_fantasmas(p_dias integer DEFAULT 30)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $fantasmas$
DECLARE
  v_n integer := 0;
  v_op record;
BEGIN
  FOR v_op IN
    SELECT o.id, o.inmobiliaria_id, o.etapa, o.contacto_id
      FROM crm.oportunidades o
      JOIN crm.contactos c ON c.id = o.contacto_id
     WHERE o.estado = 'abierta'
       AND o.embudo = 'comercial'
       AND c.deleted_at IS NULL
       AND COALESCE(c.ultima_actividad_at, o.created_at)
             < now() - make_interval(days => p_dias)
       AND NOT EXISTS (
         SELECT 1 FROM crm.transiciones t
          WHERE t.oportunidad_id = o.id
            AND t.origen = 'humano'
            AND t.ocurrido_at > now() - make_interval(days => p_dias)
       )
       -- Solo mensajes comerciales (o Kommo sin número) cuentan como turno del cliente
       AND NOT EXISTS (
         SELECT 1 FROM crm.actividades a
          WHERE a.contacto_id = o.contacto_id
            AND a.tipo = 'mensaje_entrante'
            AND (a.wa_phone_number_id IS NULL OR EXISTS (
              SELECT 1 FROM crm.lineas l
               WHERE l.wa_phone_number_id = a.wa_phone_number_id
                 AND l.embudo = 'comercial'
            ))
            AND a.ocurrido_at > COALESCE((
              SELECT max(a2.ocurrido_at) FROM crm.actividades a2
               WHERE a2.contacto_id = o.contacto_id
                 AND a2.tipo = 'mensaje_saliente'
                 AND (a2.wa_phone_number_id IS NULL OR EXISTS (
                   SELECT 1 FROM crm.lineas l2
                    WHERE l2.wa_phone_number_id = a2.wa_phone_number_id
                      AND l2.embudo = 'comercial'
                 ))
            ), '-infinity'::timestamptz)
       )
       AND NOT EXISTS (
         SELECT 1 FROM crm.actividades a
           JOIN public.citas ci ON ci.id = a.cita_id
          WHERE a.contacto_id = o.contacto_id
            AND ci.estado = 'agendada'
            AND ci.fecha >= crm.hoy()
       )
  LOOP
    BEGIN
      UPDATE crm.oportunidades
         SET estado         = 'perdida',
             motivo_perdida = 'no_responde',
             cerrada_at     = now(),
             cerrada_por    = NULL,
             updated_at     = now()
       WHERE id = v_op.id;

      INSERT INTO crm.transiciones
        (inmobiliaria_id, oportunidad_id, etapa_desde, etapa_hasta,
         estado_hasta, origen, motivo, usuario_id)
      VALUES (v_op.inmobiliaria_id, v_op.id, v_op.etapa, NULL,
              'perdida', 'sistema', '30 días de silencio', NULL);

      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;

  RETURN v_n;
END $fantasmas$;

-- ---------------------------------------------------------------------
-- 5. El tablero: atendido es que alguien hizo algo, no que abrió la ficha
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.tablero(
  p_limite         integer DEFAULT 40,
  p_zona           text    DEFAULT NULL,
  p_asesor         uuid    DEFAULT NULL,
  p_solo_pendiente boolean DEFAULT NULL,
  p_texto          text    DEFAULT NULL,
  p_embudo         text    DEFAULT 'comercial')
RETURNS TABLE(id uuid, contacto_id uuid, etapa text, etapa_orden smallint, nombre text,
              telefono_e164 text, zona text, ultima_actividad_at timestamptz,
              etapa_at timestamptz, escalado_at timestamptz, escalado_sin_atender boolean,
              escalado_atendido boolean, estancada boolean, visita_realizada_origen text,
              total_en_etapa bigint)
LANGUAGE sql STABLE SET search_path = ''
AS $tablero$
  WITH base AS (
    SELECT
      v.*,
      (v.escalado_at IS NOT NULL
       AND crm.bot_atendido_desde(v.contacto_id, v.escalado_at)) AS atendido
    FROM crm.v_oportunidades v
    WHERE v.estado = 'abierta'
      AND v.embudo = p_embudo
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
      (b.escalado_at IS NOT NULL
       AND NOT b.atendido
       AND b.escalado_at > now() - crm.ventana_escalamiento()) AS escalado_sin_atender
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

COMMENT ON FUNCTION crm.tablero(int, text, uuid, boolean, text, text) IS
  'El tablero kanban por embudo. Un escalado está atendido si alguien del equipo hizo algo después '
  '(crm.bot_atendido_desde); abrir la ficha no cuenta.';
