-- =====================================================================
-- Tarea 1: Enrutamiento por línea, captación sin línea propia,
-- casos a mano, tablero por embudo, aislamiento de lo comercial
-- y deduplicación de historial.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Captación sin línea propia: usa la línea de administrativa
-- ---------------------------------------------------------------------
ALTER TABLE crm.embudos
  ADD COLUMN IF NOT EXISTS usa_linea_de text REFERENCES crm.embudos(codigo);

UPDATE crm.embudos
   SET usa_linea_de = 'administrativa'
 WHERE codigo = 'captacion';

COMMENT ON COLUMN crm.embudos.usa_linea_de IS
  'Si este embudo no tiene línea propia, qué embudo le presta su línea de WhatsApp.';

-- ---------------------------------------------------------------------
-- 2. Permitir motivo 'es_captacion' al cerrar un caso administrativo
-- ---------------------------------------------------------------------
ALTER TABLE crm.oportunidades
  DROP CONSTRAINT IF EXISTS oportunidades_motivo_perdida_check;

ALTER TABLE crm.oportunidades
  ADD CONSTRAINT oportunidades_motivo_perdida_check
  CHECK (motivo_perdida IN (
    'precio', 'zona', 'disponibilidad', 'requisitos',
    'no_responde', 'arrendo_con_otro', 'duplicado', 'otro', 'es_captacion'
  ));

ALTER TABLE crm.eventos
  DROP CONSTRAINT IF EXISTS eventos_tipo_check;

ALTER TABLE crm.eventos
  ADD CONSTRAINT eventos_tipo_check
  CHECK (tipo IN (
    'mensaje_whatsapp', 'cita', 'solicitud_apertura', 'backfill',
    'linea_no_configurada', 'duplicado_historial', 'pipeline', 'pipeline_administrativa'
  ));

-- ---------------------------------------------------------------------
-- 3. Índices de rendimiento para enrutamiento y deduplicación en masa
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS oportunidades_abiertas_embudo
  ON crm.oportunidades (contacto_id, embudo)
  WHERE estado = 'abierta';

CREATE INDEX IF NOT EXISTS lineas_wa_pnid_activa
  ON crm.lineas (wa_phone_number_id)
  WHERE activa;

CREATE INDEX IF NOT EXISTS actividades_dedup
  ON crm.actividades (contacto_id, tipo, ocurrido_at);

-- ---------------------------------------------------------------------
-- 4. Botón «Es una captación» (transaccional, SECURITY INVOKER)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.convertir_a_captacion(p_contacto_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $capt$
DECLARE
  v_op_admin        crm.oportunidades%ROWTYPE;
  v_captacion_id    uuid;
  v_org             uuid;
  v_tiene_comercial boolean;
  v_nuevo_tipo      text;
BEGIN
  SELECT c.inmobiliaria_id INTO v_org
    FROM crm.contactos c
   WHERE c.id = p_contacto_id AND c.deleted_at IS NULL;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Contacto no encontrado o no autorizado';
  END IF;

  -- 1 · Buscar caso administrativo abierto
  SELECT * INTO v_op_admin
    FROM crm.oportunidades o
   WHERE o.contacto_id = p_contacto_id
     AND o.estado = 'abierta'
     AND o.embudo = 'administrativa';

  IF v_op_admin.id IS NULL THEN
    RAISE EXCEPTION 'El contacto no tiene un caso administrativo abierto';
  END IF;

  -- 2 · Cerrar el caso administrativo sin que cuente como pérdida comercial
  UPDATE crm.oportunidades
     SET estado         = 'perdida',
         motivo_perdida = 'es_captacion',
         cerrada_at     = now(),
         cerrada_por    = (SELECT auth.uid()),
         updated_at     = now()
   WHERE id = v_op_admin.id;

  INSERT INTO crm.transiciones
    (inmobiliaria_id, oportunidad_id, etapa_desde, etapa_hasta,
     estado_hasta, origen, motivo, usuario_id)
  VALUES (v_org, v_op_admin.id, v_op_admin.etapa, NULL,
          'perdida', 'humano', 'Reclasificado como captación', (SELECT auth.uid()));

  -- 3 · Abrir el prospecto de captación en 'prospecto'
  INSERT INTO crm.oportunidades (
    inmobiliaria_id, contacto_id, embudo, etapa, asesor_id
  ) VALUES (
    v_org, p_contacto_id, 'captacion', 'prospecto', (SELECT c.asesor_id FROM crm.contactos c WHERE c.id = p_contacto_id)
  )
  RETURNING id INTO v_captacion_id;

  INSERT INTO crm.transiciones (
    inmobiliaria_id, oportunidad_id, etapa_hasta, estado_hasta, origen, motivo, usuario_id
  ) VALUES (
    v_org, v_captacion_id, 'prospecto', 'abierta', 'humano', 'Reclasificado como captación', (SELECT auth.uid())
  );

  -- 4 · Cambiar el tipo de contacto a 'propietario', o a 'ambos' si ya tenía una oportunidad comercial
  SELECT EXISTS (
    SELECT 1 FROM crm.oportunidades o
     WHERE o.contacto_id = p_contacto_id AND o.embudo = 'comercial'
  ) INTO v_tiene_comercial;

  IF v_tiene_comercial THEN
    v_nuevo_tipo := 'ambos';
  ELSE
    v_nuevo_tipo := 'propietario';
  END IF;

  UPDATE crm.contactos
     SET tipo = v_nuevo_tipo, updated_at = now()
   WHERE id = p_contacto_id;

  -- 5 · Dejar rastro en el historial del contacto
  INSERT INTO crm.actividades (
    inmobiliaria_id, tipo, origen, contacto_id,
    cuerpo, metadata, creado_por, ocurrido_at
  ) VALUES (
    v_org, 'sistema', 'humano', p_contacto_id,
    'Caso administrativo reclasificado como prospecto de captación',
    jsonb_build_object(
      'oportunidad_id', v_captacion_id,
      'caso_administrativo_cerrado_id', v_op_admin.id
    ),
    (SELECT auth.uid()), now()
  );

  RETURN v_captacion_id;
END $capt$;

COMMENT ON FUNCTION crm.convertir_a_captacion(uuid) IS
  'Cierra un caso administrativo como es_captacion, abre un prospecto de captación y actualiza el tipo del contacto a propietario o ambos.';

GRANT EXECUTE ON FUNCTION crm.convertir_a_captacion(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 5. Abrir caso administrativo a mano (SECURITY INVOKER)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.abrir_caso_administrativo(p_contacto_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $adm$
DECLARE
  v_org uuid;
  v_id  uuid;
BEGIN
  SELECT c.inmobiliaria_id INTO v_org
    FROM crm.contactos c
   WHERE c.id = p_contacto_id AND c.deleted_at IS NULL;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Contacto no encontrado o no autorizado';
  END IF;

  SELECT o.id INTO v_id
    FROM crm.oportunidades o
   WHERE o.contacto_id = p_contacto_id
     AND o.estado = 'abierta'
     AND o.embudo = 'administrativa';

  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  INSERT INTO crm.oportunidades (
    inmobiliaria_id, contacto_id, embudo, etapa, asesor_id
  ) VALUES (
    v_org, p_contacto_id, 'administrativa', 'al_dia', (SELECT c.asesor_id FROM crm.contactos c WHERE c.id = p_contacto_id)
  )
  RETURNING id INTO v_id;

  INSERT INTO crm.transiciones (
    inmobiliaria_id, oportunidad_id, etapa_hasta, estado_hasta, origen, motivo, usuario_id
  ) VALUES (
    v_org, v_id, 'al_dia', 'abierta', 'humano', 'Caso administrativo abierto manualmente', (SELECT auth.uid())
  );

  INSERT INTO crm.actividades (
    inmobiliaria_id, tipo, origen, contacto_id,
    cuerpo, metadata, creado_por, ocurrido_at
  ) VALUES (
    v_org, 'sistema', 'humano', p_contacto_id,
    'Caso administrativo abierto manualmente',
    jsonb_build_object('oportunidad_id', v_id),
    (SELECT auth.uid()), now()
  );

  RETURN v_id;
END $adm$;

COMMENT ON FUNCTION crm.abrir_caso_administrativo(uuid) IS
  'Abre un caso administrativo a mano para un contacto si no tiene uno abierto.';

GRANT EXECUTE ON FUNCTION crm.abrir_caso_administrativo(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 6. Enrutamiento por línea al llegar una actividad
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.pipeline_al_llegar_actividad()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $pipe$
DECLARE
  v_pnid   text;
  v_embudo text;
BEGIN
  IF NEW.contacto_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Actividades internas (sistema, nota) no abren ni mueven oportunidades comerciales.
  IF NEW.tipo IN ('sistema', 'nota') THEN
    RETURN NULL;
  END IF;

  -- Actividades que no son mensajes (citas, llamadas, solicitudes)
  -- siguen la ruta comercial estándar.
  IF NEW.tipo NOT IN ('mensaje_entrante', 'mensaje_saliente') THEN
    BEGIN
      PERFORM crm.recalcular_oportunidad(NEW.contacto_id);
    EXCEPTION WHEN OTHERS THEN
      BEGIN
        PERFORM crm.registrar_fallo(
          NEW.inmobiliaria_id, 'pipeline', 'crm.actividades', NEW.id::text,
          jsonb_build_object('contacto_id', NEW.contacto_id), SQLERRM);
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END;
    RETURN NULL;
  END IF;

  v_pnid := NULLIF(btrim(NEW.wa_phone_number_id), '');

  -- Mensaje sin número (Kommo/n8n histórico): embudo comercial como hoy.
  IF v_pnid IS NULL THEN
    BEGIN
      PERFORM crm.recalcular_oportunidad(NEW.contacto_id);
    EXCEPTION WHEN OTHERS THEN
      BEGIN
        PERFORM crm.registrar_fallo(
          NEW.inmobiliaria_id, 'pipeline', 'crm.actividades', NEW.id::text,
          jsonb_build_object('contacto_id', NEW.contacto_id), SQLERRM);
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END;
    RETURN NULL;
  END IF;

  -- Buscar a qué embudo pertenece la línea
  SELECT l.embudo INTO v_embudo
    FROM crm.lineas l
   WHERE l.wa_phone_number_id = v_pnid
     AND l.inmobiliaria_id = NEW.inmobiliaria_id
     AND l.activa
   LIMIT 1;

  IF v_embudo IS NULL THEN
    -- Número que no está en crm.lineas: no abrir nada y dejar rastro en crm.eventos
    BEGIN
      PERFORM crm.registrar_fallo(
        NEW.inmobiliaria_id, 'linea_no_configurada', 'crm.actividades', NEW.id::text,
        jsonb_build_object('contacto_id', NEW.contacto_id, 'wa_phone_number_id', v_pnid),
        'El número de WhatsApp no está configurado en crm.lineas');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    RETURN NULL;
  END IF;

  IF v_embudo = 'comercial' THEN
    BEGIN
      PERFORM crm.recalcular_oportunidad(NEW.contacto_id);
    EXCEPTION WHEN OTHERS THEN
      BEGIN
        PERFORM crm.registrar_fallo(
          NEW.inmobiliaria_id, 'pipeline', 'crm.actividades', NEW.id::text,
          jsonb_build_object('contacto_id', NEW.contacto_id), SQLERRM);
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END;
  ELSIF v_embudo = 'administrativa' THEN
    -- Abrir un caso administrativo en al_dia si no hay uno abierto.
    -- NUNCA abrir ni avanzar una oportunidad comercial por este mensaje.
    BEGIN
      PERFORM crm.abrir_oportunidad(NEW.contacto_id, 'administrativa');
    EXCEPTION WHEN OTHERS THEN
      BEGIN
        PERFORM crm.registrar_fallo(
          NEW.inmobiliaria_id, 'pipeline_administrativa', 'crm.actividades', NEW.id::text,
          jsonb_build_object('contacto_id', NEW.contacto_id), SQLERRM);
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END;
  END IF;

  RETURN NULL;
END $pipe$;

-- ---------------------------------------------------------------------
-- 7. Evidencia comercial: excluir mensajes de líneas no comerciales
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

    -- La visita PRESUNTA: estaba confirmada, la fecha pasó y nadie la canceló.
    COALESCE((
      SELECT 5::smallint
        FROM crm.actividades a2
        JOIN public.citas ci ON ci.id = a2.cita_id
       WHERE a2.contacto_id = p_contacto_id
         AND a2.cita_id IS NOT NULL
         AND ci.confirmada_at IS NOT NULL
         AND ci.estado = 'agendada'
         AND ci.fecha < current_date
       LIMIT 1
    ), 1)::smallint
  );
$evidencia$;

-- ---------------------------------------------------------------------
-- 8. Deduplicación de historial en proyección (segunda red)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.proyectar_mensaje()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_org      uuid;
  v_contacto uuid;
  v_ids      jsonb := '[]'::jsonb;
  v_tel      text;
  v_conv     record;
  v_pnid     text;
  v_wamid    text;
  v_tipo     text;
  v_dup_id   bigint;
BEGIN
  BEGIN
    v_pnid := NULLIF(btrim(to_jsonb(NEW) ->> 'wa_phone_number_id'), '');
    v_wamid := NULLIF(btrim(to_jsonb(NEW) ->> 'wa_message_id'), '');

    SELECT c.inmobiliaria_id, c.telefono, c.cliente_nombre,
           c.kommo_lead_id, c.kommo_contact_id
      INTO v_conv
      FROM public.agente_comercial_conversaciones c
     WHERE c.id = NEW.conversacion_id;

    IF NOT FOUND THEN
      RETURN NULL;
    END IF;

    v_org := v_conv.inmobiliaria_id;
    v_tel := crm.normalizar_telefono(v_conv.telefono);

    IF v_tel IS NOT NULL THEN
      v_ids := v_ids || jsonb_build_array(
        jsonb_build_object('tipo', 'telefono_e164', 'valor', v_tel));
    END IF;
    IF v_conv.kommo_lead_id IS NOT NULL THEN
      v_ids := v_ids || jsonb_build_array(
        jsonb_build_object('tipo', 'kommo_lead', 'valor', v_conv.kommo_lead_id));
    END IF;
    IF v_conv.kommo_contact_id IS NOT NULL THEN
      v_ids := v_ids || jsonb_build_array(
        jsonb_build_object('tipo', 'kommo_contact', 'valor', v_conv.kommo_contact_id));
    END IF;

    v_contacto := crm.resolver_contacto(
      v_org, v_ids, v_conv.cliente_nombre, 'whatsapp', 'cliente', v_conv.telefono);

    IF v_contacto IS NULL THEN
      RETURN NULL;
    END IF;

    v_tipo := CASE WHEN NEW.rol = 'usuario' THEN 'mensaje_entrante' ELSE 'mensaje_saliente' END;

    -- Red contra duplicados del historial:
    -- Si trae wamid y coincide con otra actividad del mismo contacto sin wamid,
    -- en la misma dirección (agente y asesor cuentan ambos como mensaje_saliente),
    -- con el mismo texto y a ±2 minutos, no la proyectamos y dejamos rastro.
    IF v_wamid IS NOT NULL THEN
      SELECT a.id INTO v_dup_id
        FROM crm.actividades a
       WHERE a.contacto_id = v_contacto
         AND a.tipo = v_tipo
         AND (a.metadata ->> 'wa_message_id') IS NULL
         AND a.cuerpo = NEW.contenido
         AND a.ocurrido_at >= (NEW.created_at - interval '2 minutes')
         AND a.ocurrido_at <= (NEW.created_at + interval '2 minutes')
       LIMIT 1;

      IF v_dup_id IS NOT NULL THEN
        PERFORM crm.registrar_fallo(
          v_org, 'duplicado_historial', 'agente_comercial_mensajes', NEW.id::text,
          jsonb_build_object(
            'contacto_id', v_contacto,
            'wa_message_id', v_wamid,
            'actividad_existente_id', v_dup_id
          ),
          'Mensaje con wamid coincide con actividad previa sin wamid (deduplicado)');
        RETURN NULL;
      END IF;
    END IF;

    INSERT INTO crm.actividades (
      inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, metadata,
      wa_phone_number_id)
    VALUES (
      v_org,
      v_tipo,
      CASE NEW.rol
        WHEN 'usuario' THEN 'humano'
        WHEN 'asesor'  THEN 'humano'
        ELSE                'agente_ia'
      END,
      v_contacto, NEW.contenido, NEW.created_at,
      jsonb_build_object(
        'origen_tabla', 'agente_comercial_mensajes',
        'origen_id', NEW.id::text,
        'wa_message_id', v_wamid
      ),
      v_pnid)
    ON CONFLICT DO NOTHING;

    UPDATE crm.contactos
       SET ultima_actividad_at = GREATEST(
             COALESCE(ultima_actividad_at, NEW.created_at), NEW.created_at)
     WHERE id = v_contacto;

  EXCEPTION WHEN OTHERS THEN
    PERFORM crm.registrar_fallo(
      v_org, 'mensaje_whatsapp', 'agente_comercial_mensajes', NEW.id::text,
      jsonb_build_object('conversacion_id', NEW.conversacion_id), SQLERRM);
  END;

  RETURN NULL;
END $$;

-- Deduplicación también en el backfill
CREATE OR REPLACE FUNCTION crm.backfill(p_inmobiliaria_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  r            record;
  m            record;
  v_contacto   uuid;
  v_ids        jsonb;
  v_tel        text;
  v_antes_c    bigint;
  v_antes_a    bigint;
  v_saltadas   bigint := 0;
  v_sin_tel    bigint := 0;
  v_pnid       text;
  v_wamid      text;
  v_tipo       text;
  v_dup_id     bigint;
BEGIN
  SELECT count(*) INTO v_antes_c FROM crm.contactos
   WHERE inmobiliaria_id = p_inmobiliaria_id;
  SELECT count(*) INTO v_antes_a FROM crm.actividades
   WHERE inmobiliaria_id = p_inmobiliaria_id;

  -- ===================================================================
  -- 1. Conversaciones de WhatsApp
  -- ===================================================================
  FOR r IN
    SELECT c.id, c.telefono, c.cliente_nombre,
           c.kommo_lead_id, c.kommo_contact_id
      FROM public.agente_comercial_conversaciones c
     WHERE c.inmobiliaria_id = p_inmobiliaria_id
     ORDER BY c.created_at
  LOOP
    v_tel := crm.normalizar_telefono(r.telefono);
    IF v_tel IS NULL THEN
      v_sin_tel := v_sin_tel + 1;
    END IF;

    -- Incluye la convención kommo-<contact_id> que escribe n8n.
    v_ids := crm.identidades_de_conversacion(
      r.telefono, r.kommo_lead_id, r.kommo_contact_id);

    v_contacto := crm.resolver_contacto(
      p_inmobiliaria_id, v_ids, r.cliente_nombre, 'whatsapp', 'cliente', r.telefono);

    IF v_contacto IS NULL THEN
      v_saltadas := v_saltadas + 1;
      CONTINUE;
    END IF;

    -- Iterar mensajes de la conversación
    FOR m IN
      SELECT msg.id, msg.rol, msg.contenido, msg.created_at,
             to_jsonb(msg) ->> 'wa_phone_number_id' AS wa_phone_number_id,
             to_jsonb(msg) ->> 'wa_message_id'      AS wa_message_id
        FROM public.agente_comercial_mensajes msg
       WHERE msg.conversacion_id = r.id
       ORDER BY msg.created_at ASC
    LOOP
      v_pnid  := NULLIF(btrim(m.wa_phone_number_id), '');
      v_wamid := NULLIF(btrim(m.wa_message_id), '');
      v_tipo  := CASE WHEN m.rol = 'usuario' THEN 'mensaje_entrante' ELSE 'mensaje_saliente' END;

      -- Deduplicación en backfill:
      IF v_wamid IS NOT NULL THEN
        SELECT a.id INTO v_dup_id
          FROM crm.actividades a
         WHERE a.contacto_id = v_contacto
           AND a.tipo = v_tipo
           AND (a.metadata ->> 'wa_message_id') IS NULL
           AND a.cuerpo = m.contenido
           AND a.ocurrido_at >= (m.created_at - interval '2 minutes')
           AND a.ocurrido_at <= (m.created_at + interval '2 minutes')
         LIMIT 1;

        IF v_dup_id IS NOT NULL THEN
          CONTINUE;
        END IF;
      END IF;

      INSERT INTO crm.actividades (
        inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, metadata,
        wa_phone_number_id)
      VALUES (
        p_inmobiliaria_id,
        v_tipo,
        CASE m.rol
          WHEN 'usuario' THEN 'humano'
          WHEN 'asesor'  THEN 'humano'
          ELSE                'agente_ia'
        END,
        v_contacto, m.contenido, m.created_at,
        jsonb_build_object(
          'origen_tabla', 'agente_comercial_mensajes',
          'origen_id', m.id::text,
          'wa_message_id', v_wamid
        ),
        v_pnid)
      ON CONFLICT DO NOTHING;
    END LOOP;
  END LOOP;

  -- ===================================================================
  -- 2. Visitas
  -- ===================================================================
  FOR r IN
    SELECT c.id, c.inmueble_id, c.cliente_telefono, c.cliente_nombre,
           c.cliente_email, c.estado, c.fecha, c.hora_inicio, c.created_at
      FROM public.citas c
     WHERE c.inmobiliaria_id = p_inmobiliaria_id
     ORDER BY c.created_at
  LOOP
    v_tel := crm.normalizar_telefono(r.cliente_telefono);
    v_ids := '[]'::jsonb;

    IF v_tel IS NOT NULL THEN
      v_ids := v_ids || jsonb_build_array(
        jsonb_build_object('tipo', 'telefono_e164', 'valor', v_tel));
    END IF;

    IF r.cliente_email IS NOT NULL AND r.cliente_email <> '' THEN
      v_ids := v_ids || jsonb_build_array(
        jsonb_build_object('tipo', 'email', 'valor', lower(trim(r.cliente_email))));
    END IF;

    v_contacto := crm.resolver_contacto(
      p_inmobiliaria_id, v_ids, r.cliente_nombre, 'cita', 'cliente', r.cliente_telefono);

    IF v_contacto IS NULL THEN
      v_saltadas := v_saltadas + 1;
      CONTINUE;
    END IF;

    INSERT INTO crm.actividades (
      inmobiliaria_id, tipo, origen, contacto_id, inmueble_id, cita_id,
      cuerpo, ocurrido_at, metadata)
    VALUES (
      p_inmobiliaria_id, 'visita_agendada', 'sistema', v_contacto,
      r.inmueble_id, r.id,
      NULL, r.created_at,
      jsonb_build_object('origen_tabla', 'citas', 'origen_id', r.id::text,
                         'fecha', r.fecha, 'hora', r.hora_inicio))
    ON CONFLICT DO NOTHING;

    -- El desenlace de la visita es otro hecho, con su propia fecha.
    IF r.estado IN ('completada', 'cancelada') THEN
      INSERT INTO crm.actividades (
        inmobiliaria_id, tipo, origen, contacto_id, inmueble_id, cita_id,
        ocurrido_at, metadata)
      VALUES (
        p_inmobiliaria_id,
        CASE r.estado WHEN 'completada' THEN 'visita_realizada'
                      ELSE 'visita_cancelada' END,
        'sistema', v_contacto, r.inmueble_id, r.id,
        (r.fecha + r.hora_inicio)::timestamptz,
        jsonb_build_object('origen_tabla', 'citas',
                           'origen_id', r.id::text || ':' || r.estado))
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;

  -- ===================================================================
  -- 3. Solicitudes de apertura de agenda
  -- ===================================================================
  FOR r IN
    SELECT s.id, s.inmueble_id, s.cliente_telefono, s.cliente_nombre,
           s.cliente_email, s.fecha, s.hora_inicio, s.estado, s.created_at
      FROM public.solicitudes_apertura s
     WHERE s.inmobiliaria_id = p_inmobiliaria_id
     ORDER BY s.created_at
  LOOP
    v_tel := crm.normalizar_telefono(r.cliente_telefono);
    v_ids := '[]'::jsonb;

    IF v_tel IS NOT NULL THEN
      v_ids := v_ids || jsonb_build_array(
        jsonb_build_object('tipo', 'telefono_e164', 'valor', v_tel));
    END IF;

    v_contacto := crm.resolver_contacto(
      p_inmobiliaria_id, v_ids, r.cliente_nombre, 'solicitud_apertura',
      'cliente', r.cliente_telefono);

    IF v_contacto IS NULL THEN
      v_saltadas := v_saltadas + 1;
      CONTINUE;
    END IF;

    INSERT INTO crm.actividades (
      inmobiliaria_id, tipo, origen, contacto_id, inmueble_id,
      ocurrido_at, metadata)
    VALUES (
      p_inmobiliaria_id, 'solicitud_apertura', 'sistema', v_contacto,
      r.inmueble_id, r.created_at,
      jsonb_build_object('origen_tabla', 'solicitudes_apertura',
                         'origen_id', r.id::text,
                         'fecha_pedida', r.fecha, 'hora_pedida', r.hora_inicio,
                         'estado', r.estado))
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- ===================================================================
  -- 4. Refrescar el orden de la bandeja
  -- ===================================================================
  UPDATE crm.contactos c
     SET ultima_actividad_at = (
           SELECT max(a.ocurrido_at) FROM crm.actividades a
            WHERE a.contacto_id = c.id)
   WHERE c.inmobiliaria_id = p_inmobiliaria_id;

  RETURN jsonb_build_object(
    'contactos_creados',   (SELECT count(*) FROM crm.contactos
                              WHERE inmobiliaria_id = p_inmobiliaria_id) - v_antes_c,
    'contactos_totales',   (SELECT count(*) FROM crm.contactos
                              WHERE inmobiliaria_id = p_inmobiliaria_id),
    'actividades_creadas', (SELECT count(*) FROM crm.actividades
                              WHERE inmobiliaria_id = p_inmobiliaria_id) - v_antes_a,
    'sin_telefono_usable', v_sin_tel,
    'filas_saltadas',      v_saltadas
  );
END $$;

-- ---------------------------------------------------------------------
-- 9. crm.encolar_envio(): respeta usa_linea_de
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.encolar_envio(
  p_contacto_id        uuid,
  p_cuerpo             text,
  p_plantilla_id       uuid DEFAULT NULL,
  p_inmueble_id        uuid DEFAULT NULL,
  p_wa_phone_number_id text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $enc$
DECLARE
  v_inmobiliaria uuid;
  v_aprobada boolean := false;
  v_pnid text := NULLIF(btrim(p_wa_phone_number_id), '');
  v_id uuid;
BEGIN
  SELECT c.inmobiliaria_id INTO v_inmobiliaria
    FROM crm.contactos c
   WHERE c.id = p_contacto_id AND c.deleted_at IS NULL;

  IF v_inmobiliaria IS NULL THEN
    RAISE EXCEPTION 'Ese contacto no existe o no es tuyo';
  END IF;

  IF btrim(COALESCE(p_cuerpo, '')) = '' THEN
    RAISE EXCEPTION 'No se puede mandar un mensaje vacío';
  END IF;

  -- La línea tiene que ser una línea activa de esta inmobiliaria. Corre
  -- con el rol de quien llama: la RLS de crm.lineas ya esconde las ajenas.
  IF v_pnid IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM crm.lineas l
        WHERE l.wa_phone_number_id = v_pnid
          AND l.inmobiliaria_id = v_inmobiliaria
          AND l.activa) THEN
    RAISE EXCEPTION 'Esa línea no es de esta inmobiliaria o no está activa'
      USING ERRCODE = '22023';
  END IF;

  -- Una plantilla sirve fuera de la ventana SOLO si Meta la aprobó.
  IF p_plantilla_id IS NOT NULL THEN
    SELECT (p.estado_meta = 'aprobada') INTO v_aprobada
      FROM crm.plantillas p WHERE p.id = p_plantilla_id AND p.activa;
    v_aprobada := COALESCE(v_aprobada, false);
  END IF;

  -- Texto libre fuera de la ventana revienta. La ventana es la de la línea elegida.
  IF NOT crm.puede_escribir_libre(p_contacto_id, v_pnid) AND NOT v_aprobada THEN
    RAISE EXCEPTION 'Fuera de la ventana de 24 h solo se puede enviar una plantilla aprobada por Meta'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO crm.envios
    (inmobiliaria_id, contacto_id, plantilla_id, inmueble_id,
     cuerpo, canal, estado, enviado_por, wa_phone_number_id)
  VALUES (v_inmobiliaria, p_contacto_id, p_plantilla_id, p_inmueble_id,
          p_cuerpo, 'meta', 'pendiente', auth.uid(), v_pnid)
  RETURNING id INTO v_id;

  RETURN v_id;
END $enc$;

-- ---------------------------------------------------------------------
-- 10. Vista v_oportunidades con embudo
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW crm.v_oportunidades WITH (security_invoker = true) AS
  SELECT
    o.id,
    o.inmobiliaria_id,
    o.contacto_id,
    o.etapa,
    e.etiqueta       AS etapa_etiqueta,
    e.orden          AS etapa_orden,
    o.estado,
    o.zona,
    o.escalado_at,
    o.asesor_id,
    o.motivo_perdida,
    o.inmueble_id,
    o.cerrada_at,
    o.etapa_at,
    o.created_at,
    c.nombre,
    c.telefono_e164,
    c.ultima_actividad_at,
    (o.estado = 'abierta'
     AND e.dias_pudricion IS NOT NULL
     AND COALESCE(c.ultima_actividad_at, o.etapa_at)
           < now() - make_interval(days => e.dias_pudricion)) AS estancada,
    CASE
      WHEN o.etapa <> 'visita_realizada' THEN NULL
      WHEN EXISTS (SELECT 1 FROM crm.actividades a
                     JOIN public.citas ci ON ci.id = a.cita_id
                    WHERE a.contacto_id = o.contacto_id
                      AND a.tipo = 'visita_realizada'
                      AND ci.completada_por IS NOT NULL) THEN 'confirmada'
      WHEN EXISTS (SELECT 1 FROM crm.actividades a
                    WHERE a.contacto_id = o.contacto_id
                      AND a.tipo = 'visita_realizada') THEN 'retroactiva'
      ELSE 'presunta'
    END AS visita_realizada_origen,
    o.embudo
  FROM crm.oportunidades o
  JOIN crm.etapas e    ON e.codigo = o.etapa AND e.embudo = o.embudo
  JOIN crm.contactos c ON c.id = o.contacto_id
  WHERE c.deleted_at IS NULL;

-- ---------------------------------------------------------------------
-- 11. Tablero por embudo
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS crm.tablero(int, text, uuid, boolean, text);

CREATE OR REPLACE FUNCTION crm.tablero(
  p_limite         int     DEFAULT 40,
  p_zona           text    DEFAULT NULL,
  p_asesor         uuid    DEFAULT NULL,
  p_solo_pendiente boolean DEFAULT NULL,
  p_texto          text    DEFAULT NULL,
  p_embudo         text    DEFAULT 'comercial')
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
      (v.escalado_at IS NOT NULL AND EXISTS (
        SELECT 1 FROM crm.lecturas l
         WHERE l.contacto_id = v.contacto_id
           AND l.visto_hasta >= v.escalado_at
      )) AS atendido
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
  'El tablero kanban por embudo (comercial por defecto), limitado por etapa para no saturar la vista.';

GRANT EXECUTE ON FUNCTION crm.tablero(int, text, uuid, boolean, text, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 12. Lo comercial, solo para lo comercial
-- ---------------------------------------------------------------------

-- A · crm.publico_marketing (alimenta reactivables y reactivables_total)
CREATE OR REPLACE FUNCTION crm.publico_marketing(
  p_dias_silencio int DEFAULT 14,
  p_limite        int DEFAULT 100)
RETURNS TABLE (
  contacto_id         uuid,
  nombre              text,
  telefono_e164       text,
  ultima_actividad_at timestamptz,
  dias_callado        int
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $pm$
  SELECT c.id, c.nombre, c.telefono_e164, c.ultima_actividad_at,
         EXTRACT(day FROM now() - c.ultima_actividad_at)::int
    FROM crm.contactos c
   WHERE c.deleted_at IS NULL
     AND c.consentimiento
     AND NOT c.opt_out
     AND c.telefono_e164 IS NOT NULL
     -- Solo clientes o ambos: nunca propietarios puros
     AND c.tipo IN ('cliente', 'ambos')
     -- Nunca inquilinos con contrato vigente (caso administrativo abierto)
     AND NOT EXISTS (
       SELECT 1 FROM crm.oportunidades o
        WHERE o.contacto_id = c.id
          AND o.embudo = 'administrativa'
          AND o.estado = 'abierta'
     )
     AND c.ultima_actividad_at < now() - make_interval(days => p_dias_silencio)
   ORDER BY c.ultima_actividad_at ASC
   LIMIT p_limite;
$pm$;

-- B · crm.coincidencias
CREATE OR REPLACE FUNCTION crm.coincidencias(
  p_minimo        smallint DEFAULT 50,
  p_por_inmueble  int      DEFAULT 5,
  p_limite        int      DEFAULT 20,
  p_inmueble_id   uuid     DEFAULT NULL,
  p_frescura_max  smallint DEFAULT 1)
RETURNS TABLE (
  inmueble_id      uuid,
  titulo           text,
  barrio           text,
  ciudad           text,
  precio           numeric,
  habitaciones     integer,
  tipo_inmueble    text,
  tipo_transaccion text,
  disponible_desde timestamptz,
  total_clientes   bigint,
  contacto_id      uuid,
  requerimiento_id uuid,
  nombre           text,
  telefono_e164    text,
  puntaje          smallint,
  especificidad    smallint,
  frescura         smallint,
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
      v.habitaciones, v.tipo_inmueble, v.tipo_transaccion,
      COALESCE(cat.disponible_desde, v.created_at) AS disponible_desde,
      r.id AS requerimiento_id, r.contacto_id,
      crm.puntaje(
        r.ciudad, r.barrios, r.tipo_inmueble, r.tipo_transaccion,
        r.precio_max, r.habitaciones_min,
        v.ciudad, v.barrio, v.tipo_inmueble, v.tipo_transaccion,
        v.precio, v.habitaciones, v.estado) AS puntaje,
      num_nonnulls(r.ciudad, r.barrios, r.tipo_inmueble, r.tipo_transaccion,
                   r.precio_max, r.habitaciones_min)::smallint AS especificidad,
      crm.frescura(c.ultima_actividad_at) AS frescura,
      c.ultima_actividad_at,
      btrim(concat_ws(', ',
        array_to_string(r.tipo_inmueble, ' o '),
        CASE WHEN r.barrios IS NOT NULL THEN 'en ' || array_to_string(r.barrios, ' o ')
             WHEN r.ciudad  IS NOT NULL THEN 'en ' || r.ciudad END,
        CASE WHEN r.habitaciones_min IS NOT NULL THEN r.habitaciones_min || '+ hab' END,
        CASE WHEN r.precio_max IS NOT NULL
             THEN 'hasta $' || replace(to_char(r.precio_max, 'FM999G999G999'), ',', '.') END
      )) AS pidio
    FROM crm.v_inmuebles v
    LEFT JOIN crm.catalogo cat ON cat.inmueble_id = v.id
    JOIN crm.requerimientos r
      ON r.inmobiliaria_id = v.inmobiliaria_id AND r.activo
    JOIN crm.contactos c ON c.id = r.contacto_id AND c.deleted_at IS NULL
    WHERE v.estado = 'disponible'
      AND (p_inmueble_id IS NULL OR v.id = p_inmueble_id)
      -- Solo clientes comerciales, nunca propietarios puros ni inquilinos administrativos
      AND c.tipo IN ('cliente', 'ambos')
      AND NOT EXISTS (
        SELECT 1 FROM crm.oportunidades o
         WHERE o.contacto_id = c.id
           AND o.embudo = 'administrativa'
           AND o.estado = 'abierta'
      )
  ), filtrados AS (
    SELECT p.*,
           row_number() OVER (PARTITION BY p.inmueble_id
                              ORDER BY p.frescura, p.puntaje DESC,
                                       p.especificidad DESC) AS n,
           count(*)     OVER (PARTITION BY p.inmueble_id) AS total_clientes
    FROM pares p
    WHERE p.puntaje >= p_minimo
      AND (p_frescura_max IS NULL OR p.frescura <= p_frescura_max)
  ), elegidos AS (
    SELECT DISTINCT inmueble_id, disponible_desde
    FROM filtrados
    ORDER BY disponible_desde DESC
    LIMIT p_limite
  )
  SELECT
    f.inmueble_id, f.titulo, f.barrio, f.ciudad, f.precio, f.habitaciones,
    f.tipo_inmueble, f.tipo_transaccion, f.disponible_desde, f.total_clientes,
    f.contacto_id, f.requerimiento_id, c.nombre, c.telefono_e164,
    f.puntaje, f.especificidad, f.frescura, f.pidio,
    o.id, o.etapa, f.ultima_actividad_at
  FROM filtrados f
  JOIN elegidos e ON e.inmueble_id = f.inmueble_id
  JOIN crm.contactos c ON c.id = f.contacto_id
  LEFT JOIN crm.oportunidades o
         ON o.contacto_id = f.contacto_id AND o.estado = 'abierta'
        AND o.embudo = 'comercial'
  WHERE f.n <= p_por_inmueble
  ORDER BY f.disponible_desde DESC, f.n;
$co$;

-- C · crm.inmuebles_para
CREATE OR REPLACE FUNCTION crm.inmuebles_para(
  p_contacto_id uuid,
  p_minimo      smallint DEFAULT 50,
  p_limite      int      DEFAULT 10,
  p_rotar       boolean  DEFAULT true)
RETURNS TABLE (
  inmueble_id      uuid,
  titulo           text,
  barrio           text,
  ciudad           text,
  precio           numeric,
  habitaciones     integer,
  tipo_inmueble    text,
  puntaje          smallint,
  disponible_desde timestamptz
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $inmuebles$
  SELECT v.id, v.titulo, v.barrio, v.ciudad, v.precio, v.habitaciones,
         v.tipo_inmueble,
         crm.puntaje(
           r.ciudad, r.barrios, r.tipo_inmueble, r.tipo_transaccion,
           r.precio_max, r.habitaciones_min,
           v.ciudad, v.barrio, v.tipo_inmueble, v.tipo_transaccion,
           v.precio, v.habitaciones, v.estado) AS puntaje,
         COALESCE(cat.disponible_desde, v.created_at) AS disponible_desde
  FROM crm.requerimientos r
  JOIN crm.contactos c ON c.id = r.contacto_id AND c.deleted_at IS NULL
  CROSS JOIN crm.v_inmuebles v
  LEFT JOIN crm.catalogo cat ON cat.inmueble_id = v.id
  WHERE r.contacto_id = p_contacto_id
    AND r.activo
    AND r.inmobiliaria_id = v.inmobiliaria_id
    AND v.estado = 'disponible'
    -- Solo clientes o ambos
    AND c.tipo IN ('cliente', 'ambos')
    -- Nunca inquilinos con contrato administrativo activo salvo que tengan oportunidad comercial abierta
    AND (
      NOT EXISTS (
        SELECT 1 FROM crm.oportunidades o
         WHERE o.contacto_id = c.id
           AND o.embudo = 'administrativa'
           AND o.estado = 'abierta'
      )
      OR EXISTS (
        SELECT 1 FROM crm.oportunidades o2
         WHERE o2.contacto_id = c.id
           AND o2.embudo = 'comercial'
           AND o2.estado = 'abierta'
      )
    )
    AND crm.puntaje(
          r.ciudad, r.barrios, r.tipo_inmueble, r.tipo_transaccion,
          r.precio_max, r.habitaciones_min,
          v.ciudad, v.barrio, v.tipo_inmueble, v.tipo_transaccion,
          v.precio, v.habitaciones, v.estado) >= p_minimo
  ORDER BY
    CASE WHEN p_rotar THEN COALESCE(cat.disponible_desde, v.created_at) END ASC,
    CASE WHEN NOT p_rotar THEN COALESCE(cat.disponible_desde, v.created_at) END DESC,
    crm.puntaje(
      r.ciudad, r.barrios, r.tipo_inmueble, r.tipo_transaccion,
      r.precio_max, r.habitaciones_min,
      v.ciudad, v.barrio, v.tipo_inmueble, v.tipo_transaccion,
      v.precio, v.habitaciones, v.estado) DESC
  LIMIT p_limite;
$inmuebles$;

-- D · crm.mi_dia
CREATE OR REPLACE FUNCTION crm.mi_dia(
  p_limite int  DEFAULT 60,
  p_asesor uuid DEFAULT NULL)
RETURNS TABLE (
  prioridad     smallint,
  tipo          text,
  titulo        text,
  detalle       text,
  cuando        timestamptz,
  contacto_id   uuid,
  nombre        text,
  telefono_e164 text,
  tarea_id      uuid,
  cita_id       uuid
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $dia$
  WITH todo (prioridad, tipo, titulo, detalle, cuando,
             contacto_id, nombre, telefono_e164, tarea_id, cita_id) AS (
    -- 1 · Escalamiento comercial
    SELECT 1::smallint, 'escalado'::text,
           'Pidió hablar con una persona'::text,
           c.nombre || ' escribió y sigue esperando'::text,
           o.escalado_at, c.id, c.nombre, c.telefono_e164,
           NULL::uuid, NULL::uuid
    FROM crm.oportunidades o
    JOIN crm.contactos c ON c.id = o.contacto_id AND c.deleted_at IS NULL
    WHERE o.estado = 'abierta'
      AND o.embudo = 'comercial'
      AND o.escalado_at IS NOT NULL
      AND o.escalado_at > now() - crm.ventana_escalamiento()
      AND NOT EXISTS (SELECT 1 FROM crm.lecturas l
                       WHERE l.contacto_id = o.contacto_id
                         AND l.visto_hasta >= o.escalado_at)

    UNION ALL
    -- 1-bis · Envío fallido
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
    -- 2 · Visitas de hoy
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
    -- 3 · Tareas vencidas
    SELECT 3::smallint, 'tarea_vencida', t.titulo,
           COALESCE(c.nombre, 'Sin contacto'),
           t.vence_at, t.contacto_id, c.nombre, c.telefono_e164, t.id, NULL
    FROM crm.tareas t
    LEFT JOIN crm.contactos c ON c.id = t.contacto_id
    WHERE t.completada_at IS NULL AND t.vence_at < date_trunc('day', now())

    UNION ALL
    -- 4 · Visitas que pasaron sin cerrar
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
      AND ci.fecha >= current_date - 14

    UNION ALL
    -- 5 · Tareas de hoy
    SELECT 5::smallint, 'tarea_hoy', t.titulo,
           COALESCE(c.nombre, 'Sin contacto'),
           t.vence_at, t.contacto_id, c.nombre, c.telefono_e164, t.id, NULL
    FROM crm.tareas t
    LEFT JOIN crm.contactos c ON c.id = t.contacto_id
    WHERE t.completada_at IS NULL
      AND t.vence_at >= date_trunc('day', now())
      AND t.vence_at <  date_trunc('day', now()) + interval '1 day'

    UNION ALL
    -- 6 · Tareas de la plataforma de inventario
    SELECT 6::smallint, 'tarea_plataforma', pt.titulo,
           COALESCE(pt.evento_titulo, 'Plataforma de inventario'),
           pt.created_at, NULL, NULL, NULL, NULL, NULL
    FROM public.tareas pt
    WHERE pt.estado = 'pendiente'

    UNION ALL
    -- 7 · Bot callado comercial
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
           AND o.embudo = 'comercial'
           AND o.escalado_at > now() - crm.ventana_escalamiento()
           AND NOT EXISTS (SELECT 1 FROM crm.lecturas l
                            WHERE l.contacto_id = c.id
                              AND l.visto_hasta >= o.escalado_at))

    UNION ALL
    -- 8 · Estancadas: SOLO comerciales
    SELECT 8::smallint, 'estancada',
           'Lleva demasiado quieta',
           v.nombre || ' · ' || v.etapa_etiqueta,
           v.ultima_actividad_at, v.contacto_id, v.nombre, v.telefono_e164,
           NULL, NULL
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
   ORDER BY t.prioridad ASC, t.cuando ASC NULLS LAST
   LIMIT p_limite;
$dia$;

-- E · crm.cerrar_fantasmas
CREATE OR REPLACE FUNCTION crm.cerrar_fantasmas(p_dias int DEFAULT 30)
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
            AND ci.fecha >= current_date
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
