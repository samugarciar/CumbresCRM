-- =====================================================================
-- «Mi día» aprende de quién es cada cosa.
--
-- Va en una migración aparte de la propiedad del lead porque cambia la
-- FIRMA de una función que la aplicación ya llama: hay que tirarla y
-- recrearla, y eso merece leerse solo.
-- =====================================================================

-- Se tira la de un solo parámetro en vez de sobrecargar: con dos
-- versiones, una llamada por nombre de argumento se vuelve ambigua y
-- Postgres la rechaza en tiempo de ejecución, que es el peor momento.
DROP FUNCTION IF EXISTS crm.mi_dia(int);

CREATE OR REPLACE FUNCTION crm.mi_dia(
  p_limite int  DEFAULT 60,
  p_asesor uuid DEFAULT NULL)
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
      AND o.escalado_at > now() - crm.ventana_escalamiento()
      AND NOT EXISTS (SELECT 1 FROM crm.lecturas l
                       WHERE l.contacto_id = o.contacto_id
                         AND l.visto_hasta >= o.escalado_at)

    UNION ALL
    -- 1-bis · Un mensaje que NO llegó. Va con la máxima prioridad porque
    --         es el único caso en que el asesor cree que hizo su trabajo y
    --         no lo hizo: el mensaje salió de la pantalla y se quedó en el
    --         camino. Nadie lo descubre solo.
    SELECT 1::smallint, 'envio_fallido',
           'No le llegó el mensaje',
           COALESCE(c.nombre, 'Sin nombre') || ' · ' ||
             COALESCE(e.error, 'WhatsApp lo rechazó'),
           COALESCE(e.fallido_at, e.created_at), c.id, c.nombre, c.telefono_e164,
           NULL, NULL
    FROM crm.envios e
    JOIN crm.contactos c ON c.id = e.contacto_id AND c.deleted_at IS NULL
    WHERE e.estado = 'fallido'
      AND e.visto_at IS NULL
      AND COALESCE(e.fallido_at, e.created_at) > now() - interval '14 days'

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
           AND o.escalado_at > now() - crm.ventana_escalamiento()
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
  -- MÍO + DE NADIE, nunca «solo lo mío».
  --
  -- Hoy 1.296 de 1.296 oportunidades abiertas no tienen responsable: un
  -- filtro estricto le dejaría el día vacío a todo el mundo. Y aunque se
  -- llenaran, lo huérfano tiene que verlo alguien o no lo ve nadie —
  -- que es justo el agujero que esta pantalla vino a tapar.
  --
  -- Lo que SÍ desaparece es lo que ya tiene otro dueño. Eso es lo único
  -- que hacía falta para que dos asesores no le escriban a la misma
  -- persona el mismo día.
  SELECT t.prioridad, t.tipo, t.titulo, t.detalle, t.cuando,
         t.contacto_id, t.nombre, t.telefono_e164, t.tarea_id, t.cita_id
    FROM todo t
    LEFT JOIN crm.oportunidades o
      ON o.contacto_id = t.contacto_id AND o.estado = 'abierta'
   WHERE p_asesor IS NULL
      OR t.contacto_id IS NULL        -- tareas de la plataforma, sin lead
      OR o.asesor_id IS NULL          -- huérfano: lo ve todo el mundo
      OR o.asesor_id = p_asesor
  ORDER BY t.prioridad, t.cuando NULLS LAST
  LIMIT p_limite;
$dia$;

GRANT EXECUTE ON FUNCTION crm.mi_dia(int, uuid) TO authenticated;
