-- =====================================================================
-- Proyección en vivo: de `public` hacia `crm`.
--
-- ⚠️ ESTOS TRIGGERS SE CUELGAN DE TABLAS DE PRODUCCIÓN.
--
-- Es la primera vez en el proyecto que el CRM toca algo de `public`, y
-- por eso cada uno está construido alrededor de una sola idea:
--
--   UN FALLO DEL CRM NO PUEDE IMPEDIR QUE EL NEGOCIO GUARDE SUS DATOS.
--
-- Un trigger que lanza excepción aborta la transacción de quien lo
-- disparó. Si el trigger de proyección falla al guardar un mensaje de
-- WhatsApp, el agente comercial se queda MUDO con un cliente real, en
-- vivo, y nadie se entera. Inaceptable.
--
-- La estructura de los tres es idéntica:
--
--   BEGIN
--     … proyectar …
--   EXCEPTION WHEN OTHERS THEN
--     BEGIN
--       … registrar el fallo en crm.eventos …
--     EXCEPTION WHEN OTHERS THEN
--       NULL;   -- ni el registro del fallo funcionó. Se traga. El
--               -- negocio sigue. Es la última línea de defensa.
--     END;
--   END;
--
-- El patrón está medido contra su alternativa en
-- supabase/tests/02_patron_proyeccion.sql, y estos triggers concretos
-- se prueban en 05_proyeccion_real.sql.
--
-- NOTA: los triggers solo LEEN de `public` (NEW y una consulta de
-- contexto). No escriben una sola fila ahí. La regla se mantiene.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Registrar un fallo sin poder fallar
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.registrar_fallo(
  p_inmobiliaria uuid, p_tipo text, p_tabla text,
  p_fila text, p_payload jsonb, p_error text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  INSERT INTO crm.eventos (
    inmobiliaria_id, tipo, tabla_origen, fila_origen_id,
    payload, estado, intentos, error)
  VALUES (p_inmobiliaria, p_tipo, p_tabla, p_fila,
          COALESCE(p_payload, '{}'::jsonb), 'fallido', 1, p_error)
  ON CONFLICT (tabla_origen, fila_origen_id, tipo) DO UPDATE
    SET intentos = crm.eventos.intentos + 1,
        error    = EXCLUDED.error,
        estado   = 'fallido';
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

-- ---------------------------------------------------------------------
-- 1. Mensajes de WhatsApp
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
      CASE WHEN NEW.rol = 'usuario' THEN 'humano' ELSE 'agente_ia' END,
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

CREATE TRIGGER crm_proyectar_mensaje
  AFTER INSERT ON public.agente_comercial_mensajes
  FOR EACH ROW EXECUTE FUNCTION crm.proyectar_mensaje();

-- ---------------------------------------------------------------------
-- 2. Visitas
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.proyectar_cita()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_contacto uuid;
  v_ids      jsonb := '[]'::jsonb;
  v_tel      text;
  v_tipo     text;
BEGIN
  BEGIN
    v_tel := crm.normalizar_telefono(NEW.cliente_telefono);

    IF v_tel IS NOT NULL THEN
      v_ids := v_ids || jsonb_build_array(
        jsonb_build_object('tipo', 'telefono_e164', 'valor', v_tel));
    END IF;
    IF NEW.cliente_email IS NOT NULL AND NEW.cliente_email <> '' THEN
      v_ids := v_ids || jsonb_build_array(
        jsonb_build_object('tipo', 'email', 'valor', lower(trim(NEW.cliente_email))));
    END IF;

    v_contacto := crm.resolver_contacto(
      NEW.inmobiliaria_id, v_ids, NEW.cliente_nombre, 'cita',
      'cliente', NEW.cliente_telefono);

    IF v_contacto IS NULL THEN
      RETURN NULL;
    END IF;

    v_tipo := CASE NEW.estado
                WHEN 'completada' THEN 'visita_realizada'
                WHEN 'cancelada'  THEN 'visita_cancelada'
                ELSE 'visita_agendada'
              END;

    INSERT INTO crm.actividades (
      inmobiliaria_id, tipo, origen, contacto_id, inmueble_id, cita_id,
      ocurrido_at, metadata)
    VALUES (
      NEW.inmobiliaria_id, v_tipo, 'sistema', v_contacto,
      NEW.inmueble_id, NEW.id,
      CASE WHEN TG_OP = 'INSERT' THEN NEW.created_at
           ELSE now() END,
      jsonb_build_object(
        'origen_tabla', 'citas',
        -- El desenlace es un hecho distinto del agendamiento, así que
        -- lleva su propia llave y ambos conviven en el timeline.
        'origen_id', NEW.id::text ||
          CASE WHEN v_tipo = 'visita_agendada' THEN '' ELSE ':' || NEW.estado END,
        'fecha', NEW.fecha, 'hora', NEW.hora_inicio))
    ON CONFLICT DO NOTHING;

    UPDATE crm.contactos
       SET ultima_actividad_at = GREATEST(COALESCE(ultima_actividad_at, now()), now())
     WHERE id = v_contacto;

  EXCEPTION WHEN OTHERS THEN
    PERFORM crm.registrar_fallo(
      NEW.inmobiliaria_id, 'cita', 'citas', NEW.id::text,
      jsonb_build_object('estado', NEW.estado), SQLERRM);
  END;

  RETURN NULL;
END $$;

CREATE TRIGGER crm_proyectar_cita
  AFTER INSERT OR UPDATE OF estado ON public.citas
  FOR EACH ROW EXECUTE FUNCTION crm.proyectar_cita();

-- ---------------------------------------------------------------------
-- 3. Solicitudes de apertura de agenda
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.proyectar_solicitud()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_contacto uuid;
  v_ids      jsonb := '[]'::jsonb;
  v_tel      text;
BEGIN
  BEGIN
    v_tel := crm.normalizar_telefono(NEW.cliente_telefono);

    IF v_tel IS NOT NULL THEN
      v_ids := v_ids || jsonb_build_array(
        jsonb_build_object('tipo', 'telefono_e164', 'valor', v_tel));
    END IF;

    v_contacto := crm.resolver_contacto(
      NEW.inmobiliaria_id, v_ids, NEW.cliente_nombre, 'solicitud_apertura',
      'cliente', NEW.cliente_telefono);

    IF v_contacto IS NULL THEN
      RETURN NULL;
    END IF;

    INSERT INTO crm.actividades (
      inmobiliaria_id, tipo, origen, contacto_id, inmueble_id,
      ocurrido_at, metadata)
    VALUES (
      NEW.inmobiliaria_id, 'solicitud_apertura', 'sistema', v_contacto,
      NEW.inmueble_id, NEW.created_at,
      jsonb_build_object('origen_tabla', 'solicitudes_apertura',
                         'origen_id', NEW.id::text,
                         'fecha_pedida', NEW.fecha,
                         'hora_pedida', NEW.hora_inicio,
                         'estado', NEW.estado))
    ON CONFLICT DO NOTHING;

    UPDATE crm.contactos
       SET ultima_actividad_at = GREATEST(COALESCE(ultima_actividad_at, now()), now())
     WHERE id = v_contacto;

  EXCEPTION WHEN OTHERS THEN
    PERFORM crm.registrar_fallo(
      NEW.inmobiliaria_id, 'solicitud_apertura', 'solicitudes_apertura',
      NEW.id::text, '{}'::jsonb, SQLERRM);
  END;

  RETURN NULL;
END $$;

CREATE TRIGGER crm_proyectar_solicitud
  AFTER INSERT ON public.solicitudes_apertura
  FOR EACH ROW EXECUTE FUNCTION crm.proyectar_solicitud();

-- ---------------------------------------------------------------------
-- Reintentos
--
-- Corre en su propia transacción, aparte de cualquier cosa del negocio:
-- si falla, no arrastra a nadie.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.reintentar_eventos(p_limite int DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  e            record;
  v_ok         int := 0;
  v_fallidos   int := 0;
BEGIN
  FOR e IN
    SELECT * FROM crm.eventos
     WHERE estado = 'fallido' AND intentos < 10
     ORDER BY created_at
     LIMIT p_limite
  LOOP
    BEGIN
      IF e.tipo = 'mensaje_whatsapp' THEN
        -- Re-disparar la proyección es más simple y más seguro que
        -- duplicar su lógica aquí: las actividades son idempotentes.
        PERFORM crm.backfill(e.inmobiliaria_id);
      END IF;

      UPDATE crm.eventos
         SET estado = 'ok', procesado_at = now(), error = NULL
       WHERE id = e.id;
      v_ok := v_ok + 1;

    EXCEPTION WHEN OTHERS THEN
      UPDATE crm.eventos
         SET intentos = intentos + 1,
             error    = SQLERRM,
             estado   = CASE WHEN intentos + 1 >= 10 THEN 'abandonado' ELSE 'fallido' END
       WHERE id = e.id;
      v_fallidos := v_fallidos + 1;
    END;
  END LOOP;

  RETURN jsonb_build_object('reprocesados', v_ok, 'siguen_fallando', v_fallidos);
END $$;

-- Agendar el reintento. Va en un bloque tolerante porque pg_cron puede
-- no estar disponible según el entorno, y eso no debe tumbar la migración.
DO $$
BEGIN
  PERFORM cron.schedule(
    'crm_reintentar_eventos', '* * * * *',
    $cron$SELECT crm.reintentar_eventos();$cron$);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron no disponible; el reintento habrá que agendarlo a mano: %', SQLERRM;
END $$;
