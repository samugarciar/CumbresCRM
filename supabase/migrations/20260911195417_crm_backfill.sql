-- =====================================================================
-- crm.backfill — llenar el CRM con el historial que ya existe.
--
-- Recorre tres fuentes y, por cada fila, resuelve la identidad de la
-- persona y le cuelga la actividad correspondiente:
--   · agente_comercial_conversaciones + _mensajes → timeline de WhatsApp
--   · citas                                      → visitas
--   · solicitudes_apertura                       → petición de horario
--
-- NO toca captacion_prospectos: sus prospectos casi nunca traen teléfono
-- (son anuncios FSBO donde el número no se publica) y pertenecen al
-- pipeline de captación, que es la fase 6.
--
-- ES IDEMPOTENTE. Correrlo dos veces no duplica nada: las identidades
-- tienen único por (inmobiliaria, tipo, valor) y las actividades por
-- (origen_tabla, origen_id). Se puede reejecutar sin miedo.
--
-- CÓMO SIMULARLO SIN ESCRIBIR
-- No hay parámetro de simulación a propósito: dos caminos de código se
-- desincronizan y acabarías simulando algo distinto de lo que ocurre.
-- La simulación la hace quien llama, revirtiendo la transacción:
--
--     BEGIN;
--     SELECT crm.backfill('<inmobiliaria_id>');
--     ROLLBACK;
--
-- Ver scripts/backfill-simulacion.sql.
--
-- Y si sale mal ya escrito, es reversible: solo toca el esquema `crm`.
--     TRUNCATE crm.actividades, crm.identidades, crm.contactos CASCADE;
-- =====================================================================

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
    v_ids := '[]'::jsonb;

    IF v_tel IS NOT NULL THEN
      v_ids := v_ids || jsonb_build_array(
        jsonb_build_object('tipo', 'telefono_e164', 'valor', v_tel));
    ELSE
      v_sin_tel := v_sin_tel + 1;
    END IF;

    IF r.kommo_lead_id IS NOT NULL THEN
      v_ids := v_ids || jsonb_build_array(
        jsonb_build_object('tipo', 'kommo_lead', 'valor', r.kommo_lead_id));
    END IF;

    IF r.kommo_contact_id IS NOT NULL THEN
      v_ids := v_ids || jsonb_build_array(
        jsonb_build_object('tipo', 'kommo_contact', 'valor', r.kommo_contact_id));
    END IF;

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
