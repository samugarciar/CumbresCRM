-- =====================================================================
-- No mandar al vacío, y enterarse cuando pase.
--
-- DOS HALLAZGOS DE LA INVESTIGACIÓN DE LA API DE META (17 sep 2026)
-- que obligan a cambiar cosas ya construidas. Ver
-- [[7. La API de WhatsApp de Meta]] en el vault.
--
-- 1. LA ALERTA DE ESCALAMIENTO ERA IMPOSIBLE POR CONSTRUCCIÓN.
--    La ventana de WhatsApp dura 24 horas desde el último mensaje DEL
--    CLIENTE. Nuestra alerta saltaba a las 48. Cuando el asesor la abría
--    y escribía, la ventana llevaba un día cerrada y Meta devolvía el
--    error 131047: el cliente no recibía nada.
--    48 > 24 SIEMPRE. Era una alerta cuya acción fallaba el 100% de las
--    veces. Hoy no se nota porque el canal es Kommo; el día que el CRM
--    envíe, se nota entero. Baja a 8 horas, decidido por Samuel.
--    Y es mejor producto por su cuenta: un lead que pidió hablar con una
--    persona y espera dos días ya se perdió.
--
-- 2. HAY QUE SABER SI LA VENTANA ESTÁ ABIERTA ANTES DE ESCRIBIR.
--    Sin eso, el asesor descubre el límite cuando el mensaje falla — en
--    la calle, en un celular, atendiendo a alguien.
-- =====================================================================

-- ---------------------------------------------------------------------
-- El umbral, UNA sola vez
--
-- Estaba escrito a mano en el tablero y en «Mi día». Este proyecto ya se
-- quemó con un valor duplicado en dos capas: se arregló en una y siguió
-- mal en la otra. Ahora hay un solo sitio donde cambiarlo.
--
-- Por qué 8 y no 24, que es lo que dura la ventana: la alerta tiene que
-- saltar con tiempo de sobra para que alguien la vea Y actúe dentro de la
-- ventana, no justo al borde. Ocho horas es una jornada.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.ventana_escalamiento()
RETURNS interval
LANGUAGE sql IMMUTABLE SET search_path = ''
AS $ve$ SELECT interval '8 hours'; $ve$;

COMMENT ON FUNCTION crm.ventana_escalamiento() IS
  'Cuánto tiempo sigue siendo "reciente" un escalamiento. 8 h, por debajo de la ventana de 24 h de WhatsApp: pasada esa, el asesor ya no puede escribir texto libre.';

GRANT EXECUTE ON FUNCTION crm.ventana_escalamiento() TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- La ventana de 24 horas de WhatsApp, como dato
--
-- Devuelve CUÁNDO se cierra. En el pasado = cerrada. NULL = esta persona
-- nunca nos ha escrito, así que nunca hubo ventana.
--
-- Se calcula del último mensaje ENTRANTE, que es lo único que la abre:
-- que nosotros escribamos no la mueve. Sale del índice
-- (contacto_id, ocurrido_at DESC) que ya existe.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.ventana_whatsapp(p_contacto_id uuid)
RETURNS timestamptz
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $vw$
  SELECT max(a.ocurrido_at) + interval '24 hours'
    FROM crm.actividades a
   WHERE a.contacto_id = p_contacto_id
     AND a.tipo = 'mensaje_entrante';
$vw$;

COMMENT ON FUNCTION crm.ventana_whatsapp(uuid) IS
  'Cuándo se cierra la ventana de 24 h de WhatsApp para esta persona. En el pasado = cerrada, solo plantillas aprobadas. NULL = nunca escribió.';

GRANT EXECUTE ON FUNCTION crm.ventana_whatsapp(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- Que un envío pueda decir que NO llegó
--
-- `estado` tenía tres valores y le faltaba el medio: Meta informa sent,
-- delivered, read y failed por webhook, y "enviado" no es "entregado".
-- Un mensaje aceptado por la API y no entregado es exactamente el caso
-- que hay que cazar.
--
-- `error_codigo` aparte del texto porque los códigos de Meta se pueden
-- tratar: 131047 es ventana cerrada, 131049 es tope de marketing. Un
-- texto libre no se puede programar, y mostrar "error 131047" a un asesor
-- tampoco sirve: hay que traducirlo.
--
-- `visto_at` para que la alerta se pueda apagar. Una alerta que no se
-- puede cerrar se convierte en ruido, y aquí ya pasó dos veces.
-- ---------------------------------------------------------------------
ALTER TABLE crm.envios
  DROP CONSTRAINT IF EXISTS envios_estado_check;

ALTER TABLE crm.envios
  ADD CONSTRAINT envios_estado_check
    CHECK (estado IN ('pendiente', 'enviado', 'entregado', 'leido', 'fallido'));

ALTER TABLE crm.envios
  ADD COLUMN wa_message_id text,
  ADD COLUMN error_codigo  integer,
  ADD COLUMN entregado_at  timestamptz,
  ADD COLUMN leido_at      timestamptz,
  ADD COLUMN fallido_at    timestamptz,
  ADD COLUMN visto_at      timestamptz;

-- Con lo que Meta manda en el webhook se encuentra la fila. Parcial
-- porque hasta que haya transporte todas son NULL.
CREATE UNIQUE INDEX envios_wa_message_id
  ON crm.envios (wa_message_id) WHERE wa_message_id IS NOT NULL;

-- Lo que la alerta busca: fallidos sin mirar. Se mantiene diminuto.
CREATE INDEX envios_fallidos_sin_ver
  ON crm.envios (inmobiliaria_id, fallido_at DESC)
  WHERE estado = 'fallido' AND visto_at IS NULL;

-- ---------------------------------------------------------------------
-- Lo que llamará el webhook de Meta cuando exista
--
-- Se escribe ahora, con el transporte todavía sin decidir del todo,
-- porque la forma no depende de él: Meta manda un id de mensaje y un
-- estado, y esto los guarda. La fase 5-B enchufa, no diseña.
--
-- El estado solo AVANZA. Los acuses de WhatsApp llegan desordenados, y
-- sin esta guarda un 'sent' que llega tarde borraría un 'delivered' ya
-- registrado. Mismo criterio que el avance de etapa en el pipeline.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.registrar_estado_envio(
  p_wa_message_id text,
  p_estado        text,
  p_error_codigo  integer DEFAULT NULL,
  p_error         text    DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $ree$
DECLARE
  v_orden constant jsonb :=
    '{"pendiente":0,"enviado":1,"entregado":2,"leido":3,"fallido":4}'::jsonb;
  v_tocadas integer;
BEGIN
  IF NOT (v_orden ? p_estado) THEN
    RAISE EXCEPTION 'Estado de envío desconocido: %', p_estado;
  END IF;

  UPDATE crm.envios e
     SET estado       = p_estado,
         error_codigo = COALESCE(p_error_codigo, e.error_codigo),
         error        = COALESCE(p_error, e.error),
         entregado_at = CASE WHEN p_estado = 'entregado' THEN now() ELSE e.entregado_at END,
         leido_at     = CASE WHEN p_estado = 'leido'     THEN now() ELSE e.leido_at END,
         fallido_at   = CASE WHEN p_estado = 'fallido'   THEN now() ELSE e.fallido_at END
   WHERE e.wa_message_id = p_wa_message_id
     AND (v_orden ->> p_estado)::int > (v_orden ->> e.estado)::int;

  GET DIAGNOSTICS v_tocadas = ROW_COUNT;
  RETURN v_tocadas > 0;
END $ree$;

COMMENT ON FUNCTION crm.registrar_estado_envio(text, text, integer, text) IS
  'Contrato del webhook de Meta: apunta el acuse de un envío. El estado solo avanza — los acuses llegan desordenados.';

GRANT EXECUTE ON FUNCTION crm.registrar_estado_envio(text, text, integer, text) TO service_role;

-- ---------------------------------------------------------------------
-- Dar por vista una alerta de envío fallido
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.marcar_envio_visto(p_envio_id uuid)
RETURNS void
LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $mev$
  UPDATE crm.envios SET visto_at = now()
   WHERE id = p_envio_id AND visto_at IS NULL;
$mev$;

GRANT EXECUTE ON FUNCTION crm.marcar_envio_visto(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- El tablero, con el umbral ya nombrado
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

GRANT EXECUTE ON FUNCTION crm.tablero(int, text, uuid, boolean, text) TO authenticated;

-- ---------------------------------------------------------------------
-- «Mi día», con el umbral nombrado y una alerta nueva arriba del todo
--
-- El envío fallido entra como prioridad 1 porque es el único caso de la
-- lista en que el asesor CREE que hizo su trabajo y no lo hizo. Todo lo
-- demás es algo pendiente que se ve pendiente; esto es algo hecho que se
-- ve hecho y no llegó.
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
  SELECT * FROM todo
  ORDER BY prioridad, cuando NULLS LAST
  LIMIT p_limite;
$dia$;

GRANT EXECUTE ON FUNCTION crm.mi_dia(int) TO authenticated;
