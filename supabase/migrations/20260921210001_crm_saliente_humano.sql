-- =====================================================================
-- Que un mensaje de un asesor llegue al CRM como lo que es.
--
-- EL FALLO, Y POR QUÉ ERA PEOR QUE UN HUECO
-- El 21 sep se amplió `agente_comercial_mensajes.rol` para aceptar
-- 'asesor', que es lo que cierra el agujero de los CERO salientes
-- humanos. Pero la proyección hacia `crm` seguía razonando con DOS roles:
--
--     CASE WHEN rol = 'usuario' THEN 'humano' ELSE 'agente_ia' END
--
-- Ese ELSE se traga 'asesor'. O sea que el primer mensaje que escribiera
-- una persona desde el CRM no habría faltado en el timeline: habría
-- aparecido FIRMADO POR EL BOT.
--
-- Y el daño no se queda ahí. `crm.bot_atendido_desde()` decide si alguien
-- atendió un lead buscando salientes con `origen = 'humano'`. Con la
-- atribución equivocada nunca los habría encontrado, así que la caducidad
-- del silencio habría devuelto la voz al bot sobre conversaciones que un
-- asesor sí estaba llevando — exactamente lo que esa regla existe para
-- evitar.
--
-- Nada de esto había ocurrido todavía porque no hay ni un mensaje de
-- asesor: el canal propio aún no existe. Se arregla antes de que exista.
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
BEGIN
  BEGIN
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

    INSERT INTO crm.actividades (
      inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, metadata)
    VALUES (
      v_org,
      CASE WHEN NEW.rol = 'usuario' THEN 'mensaje_entrante' ELSE 'mensaje_saliente' END,
      -- TRES roles, no dos. El ELSE de antes mandaba TODO lo que no
      -- fuera del cliente a 'agente_ia', así que un mensaje escrito por
      -- un asesor no es que no apareciera: aparecía ATRIBUIDO AL BOT.
      -- Y crm.bot_atendido_desde() busca salientes con origen 'humano',
      -- o sea que la caducidad del silencio nunca habría visto que
      -- alguien atendió. El arreglo entero de los "cero salientes
      -- humanos" no habría funcionado, en silencio.
      CASE NEW.rol
        WHEN 'usuario' THEN 'humano'      -- lo escribió el cliente
        WHEN 'asesor'  THEN 'humano'      -- lo escribió una persona del equipo
        ELSE                'agente_ia'   -- lo escribió el bot
      END,
      v_contacto, NEW.contenido, NEW.created_at,
      jsonb_build_object('origen_tabla', 'agente_comercial_mensajes',
                         'origen_id', NEW.id::text))
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
