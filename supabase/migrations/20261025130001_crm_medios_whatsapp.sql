-- =====================================================================
-- Fotos, audios y documentos de WhatsApp en el chat del CRM
--
-- LO QUE PIDIÓ SAMUEL (25 oct): que en el chat en vivo se vean las fotos
-- y los audios que mandan los clientes por la comercial (+57 312 229 5313).
--
-- LO QUE HABÍA: la plataforma guardaba «[el cliente mandó audio, que
-- todavía no sabemos leer]». Desde su migración 2026-10-25 cada mensaje con
-- medio trae `medio` (jsonb: tipo, mime, ruta en el bucket whatsapp_medios,
-- caption, voz, texto…), y `contenido` llega con la nota de voz transcrita
-- o la foto descrita.
--
-- LA PIEZA: crm.proyectar_mensaje copia `medio` a actividades.metadata.
-- Lo demás de la función queda igual que en 20261016120001. El CRM firma
-- las URLs con la sesión del usuario; el bucket solo deja leer la carpeta
-- de su inmobiliaria.
-- =====================================================================

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

    -- Solo líneas oficiales: lo que no llega por una línea de crm.lineas
    -- (el bot comercial por Kommo y n8n, que no trae wa_phone_number_id) no
    -- entra. Solo le sirve al freno de esa persona, si tiene uno: quién
    -- escribió por última vez y si alguien del equipo la atendió.
    IF crm.solo_lineas_oficiales(v_org)
       AND NOT (v_pnid IS NOT NULL AND EXISTS (
             SELECT 1 FROM crm.lineas l
              WHERE l.inmobiliaria_id = v_org
                AND l.wa_phone_number_id = v_pnid)) THEN
      IF v_tel IS NOT NULL AND NEW.rol IN ('usuario', 'asesor') THEN
        UPDATE crm.frenos_bot f
           SET ultimo_entrante_at = CASE WHEN NEW.rol = 'usuario'
                 THEN GREATEST(COALESCE(f.ultimo_entrante_at, NEW.created_at), NEW.created_at)
                 ELSE f.ultimo_entrante_at END,
               atendido_at = CASE WHEN NEW.rol = 'asesor'
                 THEN GREATEST(COALESCE(f.atendido_at, NEW.created_at), NEW.created_at)
                 ELSE f.atendido_at END
         WHERE f.inmobiliaria_id = v_org
           AND f.telefono_e164 = v_tel;
      END IF;
      RETURN NULL;
    END IF;

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
      )
        -- La foto, el audio o el documento (ver la migración 2026-10-25 de la
        -- plataforma). Se lee con to_jsonb para no depender de la columna.
        || CASE WHEN jsonb_typeof(to_jsonb(NEW) -> 'medio') = 'object'
                THEN jsonb_build_object('medio', to_jsonb(NEW) -> 'medio')
                ELSE '{}'::jsonb END,
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

