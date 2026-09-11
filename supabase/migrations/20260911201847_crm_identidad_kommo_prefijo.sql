-- =====================================================================
-- La convención `kommo-<contact_id>`, reconocida explícitamente.
--
-- QUÉ SE DESCUBRIÓ (11 sep 2026)
-- Cuando un contacto de Kommo llega con `custom_fields_values` en null,
-- n8n escribe a propósito `telefono = 'kommo-<kommo_contact_id>'` para que
-- la conversación y su debounce no se rompan. Está en el commit 7c92e17
-- del repo CumbresStateInventory (11 ago 2026), y la primera fila así
-- aparece 69 segundos después de ese commit.
--
-- La correspondencia es exacta: 226 de 226 filas cumplen
-- `kommo-<N>` ⇔ `kommo_contact_id = N`.
--
-- El CRM ya las unificaba bien, porque la columna `kommo_contact_id`
-- viene poblada en todas. Esto añade una segunda vía: extraer el id del
-- propio prefijo. Así la identidad no depende de que esa columna esté
-- llena, y la convención queda escrita donde se usa en vez de vivir solo
-- en la cabeza de quien la encontró.
--
-- Ojo: `crm.normalizar_telefono('kommo-49999153')` devuelve NULL —quita
-- los no-dígitos y quedan 8, que sin marca internacional no se aceptan—
-- así que el id NUNCA se convierte en llave de teléfono. Medido en
-- tests/04_normalizar_telefono.sql.
-- =====================================================================

CREATE OR REPLACE FUNCTION crm.identidades_de_conversacion(
  p_telefono text,
  p_kommo_lead text,
  p_kommo_contact text
)
RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path = ''
AS $$
  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb)
  FROM (
    SELECT jsonb_build_object(
             'tipo', 'telefono_e164',
             'valor', crm.normalizar_telefono(p_telefono)) AS x
     WHERE crm.normalizar_telefono(p_telefono) IS NOT NULL

    UNION ALL
    SELECT jsonb_build_object('tipo', 'kommo_lead', 'valor', p_kommo_lead)
     WHERE p_kommo_lead IS NOT NULL

    UNION ALL
    SELECT jsonb_build_object('tipo', 'kommo_contact', 'valor', p_kommo_contact)
     WHERE p_kommo_contact IS NOT NULL

    -- La segunda vía: el id va dentro del propio valor de `telefono`.
    -- Si coincide con la columna, resolver_contacto lo ignora por el
    -- ON CONFLICT; si la columna viniera vacía, esto lo salva.
    UNION ALL
    SELECT jsonb_build_object(
             'tipo', 'kommo_contact',
             'valor', (regexp_match(p_telefono, '^kommo-([0-9]+)$'))[1])
     WHERE p_telefono ~ '^kommo-[0-9]+$'
  ) t;
$$;

COMMENT ON FUNCTION crm.identidades_de_conversacion(text, text, text) IS
  'Todas las identidades que se pueden extraer de una conversación del agente, incluida la convención kommo-<contact_id> que escribe n8n.';

GRANT EXECUTE ON FUNCTION crm.identidades_de_conversacion(text, text, text)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- El trigger de mensajes pasa a usar el helper.
-- El razonamiento completo del patrón a prueba de fallos está en
-- 20260911195419_crm_proyeccion.sql; aquí solo cambia cómo se arman las
-- identidades.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.proyectar_mensaje()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_org      uuid;
  v_contacto uuid;
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

    v_contacto := crm.resolver_contacto(
      v_org,
      crm.identidades_de_conversacion(
        v_conv.telefono, v_conv.kommo_lead_id, v_conv.kommo_contact_id),
      v_conv.cliente_nombre, 'whatsapp', 'cliente', v_conv.telefono);

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

-- ---------------------------------------------------------------------
-- Y el backfill igual. Mismo cuerpo que en
-- 20260911195417_crm_backfill.sql —donde está toda la documentación del
-- porqué— con el bloque de identidades sustituido por el helper.
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
      inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, metadata)
    SELECT
      p_inmobiliaria_id,
      CASE WHEN m.rol = 'usuario' THEN 'mensaje_entrante' ELSE 'mensaje_saliente' END,
      -- Lo que escribió el cliente es de un humano; lo que contestó el
      -- bot va marcado como tal. Un timeline que no los distingue miente.
      CASE WHEN m.rol = 'usuario' THEN 'humano' ELSE 'agente_ia' END,
      v_contacto, m.contenido, m.created_at,
      jsonb_build_object('origen_tabla', 'agente_comercial_mensajes',
                         'origen_id', m.id::text)
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

COMMENT ON FUNCTION crm.backfill(uuid) IS
  'Llena el CRM desde el historial existente. Idempotente. Para simular: BEGIN; SELECT crm.backfill(...); ROLLBACK;';
