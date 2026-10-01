-- =====================================================================
-- La ventana de 24 h, por número. Preparada para cuando la plataforma
-- diga por qué número entra cada mensaje.
--
-- EL PROBLEMA (visto el 1 oct al probar la caja con dos líneas)
-- En WhatsApp la ventana de 24 h es de un NÚMERO con una persona: que
-- alguien le escriba a la línea administrativa no abre la de la
-- comercial. El CRM la calculaba por persona, con cualquier mensaje. Con
-- una sola línea viva da igual; con dos, la caja dejaría mandar texto
-- libre por una línea cerrada, Meta respondería 131047 y el envío
-- fallaría delante del asesor.
--
-- LO QUE HACE FALTA DE LA PLATAFORMA, Y LO QUE ESTA MIGRACIÓN DEJA LISTO
-- El número tiene que venir con cada mensaje: una columna
-- `wa_phone_number_id` en public.agente_comercial_mensajes, que es de la
-- plataforma. Hoy no existe. Esta migración deja el CRM listo para el día
-- que exista, SIN depender de que exista:
--   · crm.actividades.wa_phone_number_id, y la proyección —en vivo y en
--     el reintento— que lo copia si viene;
--   · crm.ventana_whatsapp y crm.puede_escribir_libre aceptan el número;
--   · crm.encolar_envio comprueba la ventana DE ESA LÍNEA, y anota en
--     crm.envios por cuál se encoló.
-- Mientras la plataforma no mande el número, todo se comporta exactamente
-- como antes.
--
-- LOS MENSAJES SIN NÚMERO CUENTAN PARA TODAS LAS LÍNEAS
-- Son los de antes de que la plataforma mande el número, cuando había un
-- solo número. Contarlos para todas es lo que hace hoy el CRM, y se
-- arregla solo: a las 24 h de que la plataforma empiece a mandarlo, ya no
-- abren ninguna ventana. La alternativa —no contarlos— cerraría de golpe
-- la ventana de todas las conversaciones el día del cambio.
--
-- DE PASO: el reintento atribuía al bot los mensajes de un asesor
-- crm.backfill, que es lo que usa crm.reintentar_eventos, conservaba el
-- CASE de antes del 21 sep. Como hay que tocar esa misma sentencia para
-- el número, se arregla aquí.
--
-- Tres funciones cambian de firma —un parámetro más, con DEFAULT, al
-- final—: se borran las viejas en la misma transacción para no dejar dos.
-- =====================================================================

ALTER TABLE crm.actividades
  ADD COLUMN wa_phone_number_id text;

COMMENT ON COLUMN crm.actividades.wa_phone_number_id IS
  'phone_number_id de Meta del número por el que entró o salió el mensaje. NULL en lo anterior a que la plataforma lo mande: cuenta para todas las líneas.';

ALTER TABLE crm.envios
  ADD COLUMN wa_phone_number_id text;

COMMENT ON COLUMN crm.envios.wa_phone_number_id IS
  'Por qué línea se encoló el envío (su phone_number_id). NULL = sin línea elegida: la plataforma usa su número por defecto.';


-- ---------------------------------------------------------------------
-- La proyección en vivo: igual que la del 21 sep, más el número.
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
BEGIN
  BEGIN
    -- Por qué número entró o salió el mensaje. Se lee por to_jsonb y no
    -- como NEW.wa_phone_number_id a propósito: hoy esa columna NO existe
    -- en public.agente_comercial_mensajes, y nombrarla directamente
    -- rompería la proyección de TODOS los mensajes. Así vale NULL hasta
    -- que la plataforma la cree, y el número entra solo desde ese día.
    -- Va DENTRO del bloque protegido, como todo lo de la proyección.
    v_pnid := NULLIF(btrim(to_jsonb(NEW) ->> 'wa_phone_number_id'), '');

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
      inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, metadata,
      wa_phone_number_id)
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
                         'origen_id', NEW.id::text),
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



-- ---------------------------------------------------------------------
-- El backfill, que también es el reintento: el número y los tres roles.
-- Todo lo demás, idéntico a 20260911201847.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.backfill(p_inmobiliaria_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  r            record;
  v_contacto   uuid;
  v_ids        jsonb;
  v_tel        text;
  v_antes_c    bigint;
  v_antes_a    bigint;
  v_saltadas   bigint := 0;
  v_sin_tel    bigint := 0;
BEGIN
  SELECT count(*) INTO v_antes_c FROM crm.contactos
   WHERE inmobiliaria_id = p_inmobiliaria_id;
  SELECT count(*) INTO v_antes_a FROM crm.actividades
   WHERE inmobiliaria_id = p_inmobiliaria_id;

  -- ===================================================================
  -- 1. Conversaciones de WhatsApp
  --
  -- La fuente más rica: trae nombre, ids de Kommo y todo el historial de
  -- mensajes. También es donde están las 225 personas sin teléfono
  -- utilizable, que entran con su identidad de Kommo.
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

    INSERT INTO crm.actividades (
      inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, metadata,
      wa_phone_number_id)
    SELECT
      p_inmobiliaria_id,
      CASE WHEN m.rol = 'usuario' THEN 'mensaje_entrante' ELSE 'mensaje_saliente' END,
      -- Los TRES roles, igual que crm.proyectar_mensaje desde el 21 sep.
      -- Aquí se había quedado el ELSE de antes, y esta función es la que
      -- usa crm.reintentar_eventos: un mensaje de un asesor cuya
      -- proyección fallara y se reintentara entraba ATRIBUIDO AL BOT.
      CASE m.rol
        WHEN 'usuario' THEN 'humano'
        WHEN 'asesor'  THEN 'humano'
        ELSE                'agente_ia'
      END,
      v_contacto, m.contenido, m.created_at,
      jsonb_build_object('origen_tabla', 'agente_comercial_mensajes',
                         'origen_id', m.id::text),
      -- Mismo motivo que en la proyección: la columna aún no existe.
      NULLIF(btrim(to_jsonb(m) ->> 'wa_phone_number_id'), '')
      FROM public.agente_comercial_mensajes m
     WHERE m.conversacion_id = r.id
    ON CONFLICT DO NOTHING;
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
  --
  -- La señal de compra más fuerte del negocio: pidieron ver algo y no
  -- había horario que ofrecerles.
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
-- La ventana, por número
-- ---------------------------------------------------------------------
DROP FUNCTION crm.encolar_envio(uuid, text, uuid, uuid);
DROP FUNCTION crm.puede_escribir_libre(uuid);
DROP FUNCTION crm.ventana_whatsapp(uuid);

CREATE FUNCTION crm.ventana_whatsapp(
  p_contacto_id        uuid,
  p_wa_phone_number_id text DEFAULT NULL)
RETURNS timestamptz
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $vw$
  SELECT max(a.ocurrido_at) + interval '24 hours'
    FROM crm.actividades a
   WHERE a.contacto_id = p_contacto_id
     AND a.tipo = 'mensaje_entrante'
     -- Sin número pedido: cualquier línea, como siempre. Con número: los
     -- de ese número y los que no traen ninguno (ver la cabecera).
     AND (p_wa_phone_number_id IS NULL
          OR a.wa_phone_number_id IS NULL
          OR a.wa_phone_number_id = p_wa_phone_number_id);
$vw$;

COMMENT ON FUNCTION crm.ventana_whatsapp(uuid, text) IS
  'Cuándo se cierra la ventana de 24 h de WhatsApp para esta persona, en esa línea si se da su phone_number_id. En el pasado = cerrada, solo plantillas. NULL = nunca escribió.';

GRANT EXECUTE ON FUNCTION crm.ventana_whatsapp(uuid, text) TO authenticated, service_role;

CREATE FUNCTION crm.puede_escribir_libre(
  p_contacto_id        uuid,
  p_wa_phone_number_id text DEFAULT NULL)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $pel$
  SELECT COALESCE(crm.ventana_whatsapp(p_contacto_id, p_wa_phone_number_id) > now(), false);
$pel$;

COMMENT ON FUNCTION crm.puede_escribir_libre(uuid, text) IS
  'Si la ventana de 24 h de WhatsApp sigue abierta para esta persona, en esa línea si se da. Fuera de ella solo caben plantillas aprobadas por Meta.';

GRANT EXECUTE ON FUNCTION crm.puede_escribir_libre(uuid, text) TO authenticated, service_role;

CREATE FUNCTION crm.encolar_envio(
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

  -- Una plantilla sirve fuera de la ventana SOLO si Meta la aprobó. Una
  -- en borrador es texto libre con otro nombre.
  IF p_plantilla_id IS NOT NULL THEN
    SELECT (p.estado_meta = 'aprobada') INTO v_aprobada
      FROM crm.plantillas p WHERE p.id = p_plantilla_id AND p.activa;
    v_aprobada := COALESCE(v_aprobada, false);
  END IF;

  -- LA REGLA: texto libre fuera de la ventana revienta. Con línea, la
  -- ventana es la de ESA línea.
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

COMMENT ON FUNCTION crm.encolar_envio(uuid, text, uuid, uuid, text) IS
  'Encola un mensaje en crm.envios. RECHAZA texto libre fuera de la ventana de 24 h, la de esa línea si se da. No entrega nada: lo manda la plataforma.';

GRANT EXECUTE ON FUNCTION crm.encolar_envio(uuid, text, uuid, uuid, text) TO authenticated;
