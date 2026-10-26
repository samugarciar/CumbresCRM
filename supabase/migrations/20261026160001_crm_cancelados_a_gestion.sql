-- =====================================================================
-- Envíos masivos: lo que no salió por cancelar también se gestiona a mano
-- (26 oct 2026)
--
-- 20261026150001 dejó fuera de la gestión manual las filas de un envío
-- cancelado («lo que no salió no se convierte en trabajo de nadie; si
-- Samuel lo quiere, es una línea»). Samuel lo quiere: si alguien cancela
-- un envío a mitad de camino, la gente a la que todavía no le había
-- salido el mensaje queda en el seguimiento de quien lo lanzó, igual que
-- las demás.
--
-- Solo si el envío se alcanzó a lanzar (lanzado_at). Descartar un
-- borrador también lo deja «cancelado», y ahí no había nada que le fuera
-- a llegar a nadie: suele ser un archivo equivocado.
--
-- Cambian dos funciones, nada más:
--  · crm.pendientes_gestion_envio: el motivo nuevo 'cancelado', «Se
--    canceló el envío antes de mandarle el mensaje». Mismo cuerpo de
--    20261026150001 con esa rama y el JOIN al envío para leer lanzado_at.
--  · crm.mi_dia: la de 20261026150001 con un grupo más en el detalle del
--    renglón del envío («N sin enviar (se canceló el envío)»). Nada más.
--
-- CREATE OR REPLACE conserva los GRANT. La firma no cambia. Idempotente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1 · Quién necesita gestión manual: también lo cancelado tras lanzar
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.pendientes_gestion_envio(p_envio_masivo_id uuid)
RETURNS TABLE (
  destinatario_id       uuid,
  fila                  int,
  nombre                text,
  telefono_crudo        text,
  telefono_e164         text,
  contacto_id           uuid,
  datos                 jsonb,
  resultado             text,
  motivo                text,
  motivo_legible        text,
  detalle               text,
  gestionado            boolean,
  gestionado_at         timestamptz,
  gestionado_por        uuid,
  gestionado_por_nombre text,
  gestion_nota          text
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $pge$
  SELECT d.id,
         r.fila,
         d.nombre,
         d.telefono_crudo,
         d.telefono_e164,
         d.contacto_id,
         r.datos,
         r.resultado,
         x.motivo,
         CASE x.motivo
           WHEN 'sin_telefono'      THEN 'Sin número de WhatsApp en el archivo'
           WHEN 'telefono_invalido' THEN 'El número del archivo no es válido'
           WHEN 'faltan_datos'      THEN 'Le faltan datos para la plantilla'
           WHEN 'fallido'           THEN 'WhatsApp no lo entregó'
           WHEN 'sin_confirmar'     THEN 'La plataforma no confirmó el envío'
           WHEN 'sin_entregar'      THEN 'Se envió hace más de 24 horas y no le ha llegado'
           WHEN 'cancelado'         THEN 'Se canceló el envío antes de mandarle el mensaje'
         END,
         CASE x.motivo
           WHEN 'faltan_datos' THEN r.detalle
           WHEN 'fallido'      THEN concat_ws(' ', r.error, '(' || r.error_codigo || ')')
         END,
         d.gestionado_at IS NOT NULL,
         d.gestionado_at,
         d.gestionado_por,
         u.nombre_completo,
         d.gestion_nota
    FROM crm.resultados_envio_masivo(p_envio_masivo_id) r
    JOIN crm.envios_masivos_destinatarios d
      ON d.envio_masivo_id = p_envio_masivo_id AND d.fila = r.fila
    JOIN crm.envios_masivos m ON m.id = p_envio_masivo_id
    LEFT JOIN crm.envios e ON e.id = d.envio_id
    LEFT JOIN crm.v_asesores u ON u.id = d.gestionado_por
   CROSS JOIN LATERAL (
     SELECT CASE
       WHEN r.resultado = 'excluido'
        AND r.motivo IN ('sin_telefono', 'telefono_invalido', 'faltan_datos') THEN r.motivo
       WHEN r.resultado IN ('fallido', 'sin_confirmar') THEN r.resultado
       -- Cancelado después de lanzarlo: le iba a llegar y no le llegó.
       -- Un borrador descartado no le carga trabajo a nadie.
       WHEN r.resultado = 'cancelado' AND m.lanzado_at IS NOT NULL THEN 'cancelado'
       -- Enviado sin acuse de entrega en 24 horas. Si la plataforma no
       -- anotó cuándo salió, cuenta desde que el despachador lo tomó.
       WHEN r.resultado = 'enviado'
        AND COALESCE(r.enviado_at, e.tomado_at, e.created_at) < now() - interval '24 hours'
         THEN 'sin_entregar'
     END AS motivo
   ) x
   WHERE x.motivo IS NOT NULL
   ORDER BY r.fila;
$pge$;

COMMENT ON FUNCTION crm.pendientes_gestion_envio(uuid) IS
  'Las personas de un envío masivo que hay que gestionar a mano: sin número, número inválido o sin datos; '
  'fallidas en Meta; sin confirmar de la plataforma (10 min); enviadas sin entregar en 24 h; y las que '
  'no alcanzaron a salir porque el envío se canceló después de lanzarlo. No entran repetidas, bajas ni '
  'frecuencia. Sale de crm.resultados_envio_masivo; dice si ya se gestionó.';

-- ---------------------------------------------------------------------
-- 2 · Mi día: el detalle cuenta los que no salieron por cancelar
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.mi_dia(p_limite integer DEFAULT 60, p_asesor uuid DEFAULT NULL)
RETURNS TABLE(prioridad smallint, tipo text, titulo text, detalle text, cuando timestamptz,
              contacto_id uuid, nombre text, telefono_e164 text, tarea_id uuid, cita_id uuid)
LANGUAGE sql STABLE SET search_path = ''
AS $mi_dia$
  WITH yo AS (
    -- El día de una admin trae todas las tareas del CRM; el de un asesor,
    -- las suyas y las que no tienen a nadie asignado. Se mira el rol de
    -- p_asesor (el dueño del día), no el de quien llama: una admin que mira
    -- el día de un asesor ve lo que ve él.
    SELECT EXISTS (
      SELECT 1 FROM crm.v_asesores u
       WHERE u.id = p_asesor AND u.rol = 'admin'
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
    -- 5-bis · Envío masivo con gente para gestionar a mano: solo en el
    --     día de quien lo lanzó. Las personas salen de
    --     crm.pendientes_gestion_envio (sin número, número inválido o sin
    --     datos, falló, sin confirmar, sin entregar en 24 h, o no salió
    --     porque se canceló el envío). Se va cuando
    --     no queda ninguna o cuando la purga borra los datos del envío.
    --     El id del envío viaja en cita_id: la firma no cambia.
    SELECT 5::smallint, 'gestion_envio_masivo',
           'Envío "' || m.nombre || '": ' || g.n
             || CASE WHEN g.n = 1 THEN ' persona para gestionar a mano'
                     ELSE ' personas para gestionar a mano' END,
           g.detalle,
           m.lanzado_at, NULL, NULL, NULL, NULL, m.id, NULL
    FROM crm.envios_masivos m
    CROSS JOIN LATERAL (
      SELECT count(*) AS n,
             concat_ws(' · ',
               NULLIF(count(*) FILTER (WHERE p.motivo IN ('sin_telefono', 'telefono_invalido')), 0)
                 || ' sin número válido',
               NULLIF(count(*) FILTER (WHERE p.motivo = 'faltan_datos'), 0)
                 || ' con datos incompletos',
               NULLIF(count(*) FILTER (WHERE p.motivo = 'fallido'), 0)
                 || ' con error de WhatsApp',
               NULLIF(count(*) FILTER (WHERE p.motivo IN ('sin_confirmar', 'sin_entregar')), 0)
                 || ' sin confirmación de entrega',
               NULLIF(count(*) FILTER (WHERE p.motivo = 'cancelado'), 0)
                 || ' sin enviar (se canceló el envío)') AS detalle
        FROM crm.pendientes_gestion_envio(m.id) p
       WHERE NOT p.gestionado
    ) g
    WHERE m.lanzado_at IS NOT NULL
      AND m.datos_borrados_at IS NULL
      AND (p_asesor IS NULL OR m.lanzado_por = p_asesor)
      AND g.n > 0

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
