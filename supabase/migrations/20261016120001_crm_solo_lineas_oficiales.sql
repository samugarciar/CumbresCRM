-- =====================================================================
-- El CRM desde cero: solo lo que entra por una línea oficial (16 oct 2026)
--
-- LO QUE PIDIÓ SAMUEL
-- Que el CRM arranque limpio y que solo entre lo que llega por una línea
-- de WhatsApp conectada a Meta (las de crm.lineas) y lo que crea el
-- propio CRM (envíos de cartera, contactos a mano). Primero entra la
-- administrativa; la comercial (324), cuando se corte Kommo (paso 6).
--
-- LO QUE HABÍA
-- El reflejo del bot comercial que corre por Kommo y n8n: cada mensaje
-- del agente se copiaba al CRM (crm.proyectar_mensaje), y también cada
-- cita y cada solicitud de apertura. Al 16 oct: 2.128 contactos, 27.311
-- actividades, 2.672 oportunidades, 7.866 transiciones y 550
-- requerimientos. Hecho a mano en el CRM: 2 actividades, 2 transiciones
-- y 3 tareas, todas de prueba.
--
-- POR QUÉ NO BASTA CON BORRAR
-- El bot comercial le pregunta al CRM antes de cada respuesta si puede
-- hablar (crm.bot_puede_responder), y quien lo calla —cuando la persona
-- pide un asesor o alguien lo apaga a mano— es crm.contactos.bot_activo.
-- Borrar los contactos les devolvía la voz a los 39 que estaban
-- callados, y dejar de copiar lo de Kommo le quitaba el freno al
-- escalamiento hasta el paso 6.
--
-- LAS PIEZAS
--  1. crm.preferencias.solo_lineas_oficiales, por inmobiliaria.
--     Encendida, lo que llega sin una línea de crm.lineas no entra, y una
--     cita o una solicitud de apertura solo entra si la persona ya está
--     en el CRM. Apagada (el valor por defecto) todo sigue como antes: así
--     las pruebas de la proyección de siempre siguen probando lo mismo.
--  2. crm.frenos_bot: el freno del bot para quien no está en el CRM, por
--     teléfono. Lo pone el mismo escalamiento de siempre
--     (crm.sincronizar_escalamientos) y lo quita el mismo cron
--     (crm.reactivar_bots). crm.bot_puede_responder mira las dos cosas,
--     así que la plataforma no cambia. Solo «Bots callados» lo enseña,
--     para que alguien pueda volver a encender el bot
--     (crm.encender_bot_freno).
--  3. crm.archivar_era_kommo(): lleva los callados al freno, copia todo
--     lo de antes a crm_archivo —un esquema cerrado que la app no ve—, lo
--     borra del CRM y enciende la preferencia. El archivo se puede borrar
--     del todo después del corte del 324.
--
-- EN DOS PASOS
-- Esta migración no borra nada ni enciende nada: con la preferencia
-- apagada todo funciona como ayer. La limpieza es una decisión aparte que
-- Samuel toma a mano, desde el editor SQL, cuando la quiera:
--
--   SELECT crm.archivar_era_kommo('<id de la inmobiliaria>');
--
-- Devuelve cuántas filas movió de cada tabla.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1 · La preferencia
-- ---------------------------------------------------------------------
CREATE TABLE crm.preferencias (
  inmobiliaria_id       uuid PRIMARY KEY
                        REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,
  solo_lineas_oficiales boolean NOT NULL DEFAULT false,
  -- Desde cuándo. El freno solo reacciona a los escalamientos de después:
  -- los de antes ya los vio el CRM con sus contactos.
  solo_lineas_desde     timestamptz,
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT preferencias_solo_lineas_con_fecha
    CHECK (NOT solo_lineas_oficiales OR solo_lineas_desde IS NOT NULL)
);

COMMENT ON TABLE crm.preferencias IS
  'Lo que cada inmobiliaria decidió sobre cómo se alimenta su CRM. '
  'solo_lineas_oficiales: solo entra lo que llega por una línea de crm.lineas '
  'y lo que crea el propio CRM.';

ALTER TABLE crm.preferencias ENABLE ROW LEVEL SECURITY;

CREATE POLICY preferencias_select ON crm.preferencias
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());

REVOKE ALL ON crm.preferencias FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON crm.preferencias TO authenticated;

-- Sin fila, apagada: es el comportamiento de siempre.
CREATE FUNCTION crm.solo_lineas_oficiales(p_inmobiliaria_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SET search_path = ''
AS $$
  SELECT COALESCE(
    (SELECT p.solo_lineas_oficiales
       FROM crm.preferencias p
      WHERE p.inmobiliaria_id = p_inmobiliaria_id),
    false);
$$;

REVOKE ALL ON FUNCTION crm.solo_lineas_oficiales(uuid)
  FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
-- 2 · El freno de quien no está en el CRM
--
-- Una fila por teléfono, con las mismas columnas del freno de
-- crm.contactos para que las reglas se lean igual. Las tres que no tiene
-- un contacto las llena la proyección de mensajes, que sigue viendo pasar
-- todo lo de Kommo aunque ya no lo copie:
--  · escalado_at: el último escalamiento que ya se tuvo en cuenta;
--  · atendido_at: el último mensaje de alguien del equipo (rol 'asesor');
--  · ultimo_entrante_at: el último mensaje de la persona.
-- Así ni la vista ni los crones tienen que leer las tablas de la
-- plataforma.
-- ---------------------------------------------------------------------
CREATE TABLE crm.frenos_bot (
  inmobiliaria_id    uuid NOT NULL
                     REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,
  telefono_e164      text NOT NULL,
  -- public.agente_comercial_conversaciones, sin llave foránea: la tabla es
  -- de la plataforma y el CRM no la ata.
  conversacion_id    uuid,
  nombre             text,
  bot_activo         boolean NOT NULL DEFAULT true,
  bot_motivo         text,
  bot_caduca         boolean NOT NULL DEFAULT true,
  bot_cambiado_at    timestamptz NOT NULL DEFAULT now(),
  bot_cambiado_por   uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,
  escalado_at        timestamptz,
  atendido_at        timestamptz,
  ultimo_entrante_at timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (inmobiliaria_id, telefono_e164),
  CONSTRAINT frenos_bot_motivo
    CHECK (bot_motivo IS NULL OR bot_motivo IN ('escalamiento', 'manual')),
  CONSTRAINT frenos_bot_callado_con_motivo
    CHECK (bot_activo OR bot_motivo IS NOT NULL)
);

COMMENT ON TABLE crm.frenos_bot IS
  'El freno del bot comercial para teléfonos que no están en el CRM (la 324 por '
  'Kommo, hasta el paso 6). crm.bot_puede_responder lo consulta junto con '
  'crm.contactos.bot_activo.';

ALTER TABLE crm.frenos_bot ENABLE ROW LEVEL SECURITY;

CREATE POLICY frenos_bot_select ON crm.frenos_bot
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());

-- Encender o apagar el bot de alguien es cosa de quien atiende, como en la
-- ficha de un contacto.
CREATE POLICY frenos_bot_update ON crm.frenos_bot
  FOR UPDATE TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria()
         AND public.get_my_role() IN ('admin', 'asesor'))
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria()
              AND public.get_my_role() IN ('admin', 'asesor'));

REVOKE ALL ON crm.frenos_bot FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON crm.frenos_bot TO authenticated;
-- Solo las columnas del interruptor: el resto lo escriben las funciones.
GRANT UPDATE (bot_activo, bot_motivo, bot_cambiado_at, bot_cambiado_por)
  ON crm.frenos_bot TO authenticated;

-- El botón de «Bots callados». INVOKER: la RLS decide quién y de qué
-- inmobiliaria. Devuelve false si no había nada que encender (o si quien
-- lo pide no puede).
CREATE FUNCTION crm.encender_bot_freno(p_telefono text)
RETURNS boolean
LANGUAGE plpgsql SET search_path = ''
AS $$
DECLARE
  v_n integer;
BEGIN
  UPDATE crm.frenos_bot f
     SET bot_activo       = true,
         bot_motivo       = NULL,
         bot_cambiado_at  = now(),
         bot_cambiado_por = auth.uid()
   WHERE f.telefono_e164 = crm.normalizar_telefono(p_telefono)
     AND NOT f.bot_activo;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n > 0;
END $$;

REVOKE ALL ON FUNCTION crm.encender_bot_freno(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION crm.encender_bot_freno(text) TO authenticated;


-- ---------------------------------------------------------------------
-- 3 · ¿Esta persona ya está en el CRM?
--
-- Con las mismas identidades con las que crm.resolver_contacto la
-- buscaría. Con la preferencia encendida, una cita o una solicitud de
-- apertura no crea a nadie: hoy las dos vienen del bot comercial por
-- Kommo, y después del paso 6 la persona ya estará por la línea.
-- ---------------------------------------------------------------------
CREATE FUNCTION crm.ya_esta_en_el_crm(p_inmobiliaria_id uuid, p_identidades jsonb)
RETURNS boolean
LANGUAGE sql STABLE SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM jsonb_array_elements(COALESCE(p_identidades, '[]'::jsonb)) e
      JOIN crm.identidades i
        ON i.inmobiliaria_id = p_inmobiliaria_id
       AND i.tipo  = e ->> 'tipo'
       AND i.valor = e ->> 'valor'
      JOIN crm.contactos c
        ON c.id = i.contacto_id
       AND c.deleted_at IS NULL);
$$;

REVOKE ALL ON FUNCTION crm.ya_esta_en_el_crm(uuid, jsonb)
  FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
-- 4 · Las tres proyecciones
--
-- Iguales a las de antes salvo el corte del principio.
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

    -- Solo líneas oficiales: la cita entra si la persona ya está en el CRM.
    IF crm.solo_lineas_oficiales(NEW.inmobiliaria_id)
       AND NOT crm.ya_esta_en_el_crm(NEW.inmobiliaria_id, v_ids) THEN
      RETURN NULL;
    END IF;

    v_contacto := crm.resolver_contacto(
      NEW.inmobiliaria_id, v_ids, NEW.cliente_nombre, 'cita',
      'cliente', NEW.cliente_telefono);
    IF v_contacto IS NULL THEN
      PERFORM crm.registrar_fallo(
        NEW.inmobiliaria_id, 'cita', 'citas', NEW.id::text,
        jsonb_build_object(
          'motivo', 'no se pudo resolver el contacto',
          'cliente_telefono', NEW.cliente_telefono,
          'cliente_nombre', NEW.cliente_nombre,
          'fecha', NEW.fecha),
        'Sin identidad utilizable: el teléfono no normaliza y no hay correo');
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

    -- Solo líneas oficiales: la solicitud entra si la persona ya está en
    -- el CRM.
    IF crm.solo_lineas_oficiales(NEW.inmobiliaria_id)
       AND NOT crm.ya_esta_en_el_crm(NEW.inmobiliaria_id, v_ids) THEN
      RETURN NULL;
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


-- ---------------------------------------------------------------------
-- 5 · El freno, en las tres funciones que lo usan
-- ---------------------------------------------------------------------

-- Callado en cualquiera de los dos sitios, callado. Falla hacia «sí
-- responde» igual que antes: sin contacto y sin freno, el bot contesta.
CREATE OR REPLACE FUNCTION crm.bot_puede_responder(p_inmobiliaria_id uuid, p_telefono text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT COALESCE(
           (SELECT bool_and(c.bot_activo)
              FROM crm.contactos c
             WHERE c.inmobiliaria_id = p_inmobiliaria_id
               AND c.telefono_e164 = crm.normalizar_telefono(p_telefono)
               AND c.deleted_at IS NULL),
           true)
     AND COALESCE(
           (SELECT f.bot_activo
              FROM crm.frenos_bot f
             WHERE f.inmobiliaria_id = p_inmobiliaria_id
               AND f.telefono_e164 = crm.normalizar_telefono(p_telefono)),
           true);
$$;

-- La primera mitad es la de siempre (contactos con oportunidad comercial
-- abierta). La segunda es para quien no está en el CRM: cada escalamiento
-- nuevo, posterior a encender la preferencia y de las últimas 48 horas,
-- calla al bot de ese teléfono si estaba hablando. Si ya estaba callado
-- (a mano o por otro escalamiento) solo se anota el escalamiento: no se
-- reinicia la ventana.
CREATE OR REPLACE FUNCTION crm.sincronizar_escalamientos()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_n integer;
  v_f integer;
BEGIN
  WITH puente AS (
    SELECT a.contacto_id, m.conversacion_id
      FROM crm.actividades a
      JOIN public.agente_comercial_mensajes m
        ON m.id::text = a.metadata->>'origen_id'
     WHERE a.metadata->>'origen_tabla' = 'agente_comercial_mensajes'
       AND a.contacto_id IS NOT NULL
  ), primera AS (
    SELECT p.contacto_id, MIN(u.created_at) AS escalado_at
      FROM puente p
      JOIN public.agente_comercial_uso u ON u.conversacion_id = p.conversacion_id
     WHERE u.escalado
     GROUP BY p.contacto_id
  ), tocadas AS (
    UPDATE crm.oportunidades o
       SET escalado_at = pr.escalado_at, updated_at = now()
      FROM primera pr
     WHERE o.contacto_id = pr.contacto_id
       AND o.estado = 'abierta'
       -- Escalar es pedir un asesor comercial: el bot solo atiende ahí.
       AND o.embudo = 'comercial'
       AND o.escalado_at IS DISTINCT FROM pr.escalado_at
    RETURNING o.contacto_id, pr.escalado_at
  ), apagadas AS (
    UPDATE crm.contactos c
       SET bot_activo       = false,
           bot_motivo       = 'escalamiento',
           bot_cambiado_at  = now(),
           bot_cambiado_por = NULL   -- lo hizo el sistema, no una persona
      FROM tocadas t
     WHERE c.id = t.contacto_id
       AND c.bot_activo
       AND t.escalado_at > now() - interval '48 hours'
    RETURNING c.id AS contacto_id, c.inmobiliaria_id
  ), rastro AS (
    INSERT INTO crm.actividades
      (inmobiliaria_id, tipo, origen, contacto_id, cuerpo)
    SELECT a.inmobiliaria_id, 'sistema', 'sistema', a.contacto_id,
           'El bot dejó de responderle: pidió hablar con una persona.'
      FROM apagadas a
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_n FROM tocadas;

  WITH escalados AS (
    SELECT DISTINCT ON (c.inmobiliaria_id, crm.normalizar_telefono(c.telefono))
           c.inmobiliaria_id,
           crm.normalizar_telefono(c.telefono) AS telefono_e164,
           c.id AS conversacion_id,
           c.cliente_nombre,
           u.created_at AS escalado_at
      FROM public.agente_comercial_uso u
      JOIN public.agente_comercial_conversaciones c ON c.id = u.conversacion_id
      JOIN crm.preferencias p
        ON p.inmobiliaria_id = c.inmobiliaria_id
       AND p.solo_lineas_oficiales
     WHERE u.escalado
       AND u.created_at > p.solo_lineas_desde
       AND u.created_at > now() - interval '48 hours'
       AND crm.normalizar_telefono(c.telefono) IS NOT NULL
     ORDER BY c.inmobiliaria_id, crm.normalizar_telefono(c.telefono), u.created_at DESC
  ), fuera_del_crm AS (
    -- Quien tiene una oportunidad comercial abierta ya lo cubre la
    -- primera mitad.
    SELECT e.*
      FROM escalados e
     WHERE NOT EXISTS (
       SELECT 1
         FROM crm.contactos k
         JOIN crm.oportunidades o ON o.contacto_id = k.id
        WHERE k.inmobiliaria_id = e.inmobiliaria_id
          AND k.telefono_e164 = e.telefono_e164
          AND k.deleted_at IS NULL
          AND o.estado = 'abierta'
          AND o.embudo = 'comercial')
  ), frenados AS (
    INSERT INTO crm.frenos_bot AS f
      (inmobiliaria_id, telefono_e164, conversacion_id, nombre,
       bot_activo, bot_motivo, bot_caduca, bot_cambiado_at, escalado_at)
    SELECT e.inmobiliaria_id, e.telefono_e164, e.conversacion_id, e.cliente_nombre,
           false, 'escalamiento', true, now(), e.escalado_at
      FROM fuera_del_crm e
    ON CONFLICT (inmobiliaria_id, telefono_e164) DO UPDATE
       SET bot_activo       = false,
           bot_motivo       = CASE WHEN f.bot_activo THEN 'escalamiento' ELSE f.bot_motivo END,
           bot_caduca       = CASE WHEN f.bot_activo THEN true ELSE f.bot_caduca END,
           bot_cambiado_at  = CASE WHEN f.bot_activo THEN now() ELSE f.bot_cambiado_at END,
           bot_cambiado_por = CASE WHEN f.bot_activo THEN NULL ELSE f.bot_cambiado_por END,
           escalado_at      = EXCLUDED.escalado_at,
           conversacion_id  = EXCLUDED.conversacion_id,
           nombre           = COALESCE(EXCLUDED.nombre, f.nombre)
     WHERE f.escalado_at IS NULL OR EXCLUDED.escalado_at > f.escalado_at
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_f FROM frenados;

  RETURN v_n + v_f;
END $$;

-- Las mismas reglas para el freno: un escalamiento que caduca vuelve solo
-- pasada la ventana si nadie del equipo le escribió después; si alguien le
-- escribió, ya no vuelve solo (decisión 25). Sin contacto no hay rastro en
-- actividades.
CREATE OR REPLACE FUNCTION crm.reactivar_bots()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_n       integer;
  v_f       integer;
  v_ventana interval := crm.ventana_silencio_escalamiento();
  v_horas   integer  := round(EXTRACT(epoch FROM crm.ventana_silencio_escalamiento()) / 3600.0);
BEGIN
  WITH vencidos AS (
    UPDATE crm.contactos c
       SET bot_activo       = true,
           bot_motivo       = NULL,
           bot_cambiado_at  = now(),
           bot_cambiado_por = NULL
     WHERE c.deleted_at IS NULL
       AND NOT c.bot_activo
       AND c.bot_motivo = 'escalamiento'
       AND c.bot_caduca
       AND c.bot_cambiado_at < now() - v_ventana
       AND NOT crm.bot_atendido_desde(c.id, c.bot_cambiado_at)
    RETURNING c.id AS contacto_id, c.inmobiliaria_id
  ), rastro AS (
    INSERT INTO crm.actividades
      (inmobiliaria_id, tipo, origen, contacto_id, cuerpo)
    SELECT v.inmobiliaria_id, 'sistema', 'sistema', v.contacto_id,
           'El bot vuelve a responderle: pasaron ' || v_horas ||
           CASE WHEN v_horas = 1 THEN ' hora' ELSE ' horas' END ||
           ' desde que pidió hablar con una persona y nadie del equipo llegó.'
      FROM vencidos v
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_n FROM vencidos;

  WITH vencidos_freno AS (
    UPDATE crm.frenos_bot f
       SET bot_activo       = true,
           bot_motivo       = NULL,
           bot_cambiado_at  = now(),
           bot_cambiado_por = NULL
     WHERE NOT f.bot_activo
       AND f.bot_motivo = 'escalamiento'
       AND f.bot_caduca
       AND f.bot_cambiado_at < now() - v_ventana
       AND (f.atendido_at IS NULL OR f.atendido_at <= f.bot_cambiado_at)
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_f FROM vencidos_freno;

  RETURN v_n + v_f;
END $$;


-- ---------------------------------------------------------------------
-- 6 · «Bots callados» enseña también el freno
--
-- Las filas del freno no tienen contacto (contacto_id NULL): la pantalla
-- las enciende por teléfono con crm.encender_bot_freno.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW crm.v_bot_callado WITH (security_invoker = true) AS
 SELECT c.id AS contacto_id,
    c.inmobiliaria_id,
    c.nombre,
    c.telefono_e164,
    c.bot_motivo AS motivo,
    c.bot_cambiado_at AS callado_desde,
    c.bot_cambiado_por AS callado_por,
    u.nombre_completo AS callado_por_nombre,
    c.bot_caduca,
    aten.atendido,
        CASE
            WHEN c.bot_motivo = 'relevo'::text THEN c.bot_cambiado_at + crm.ventana_relevo()
            WHEN c.bot_motivo = 'escalamiento'::text AND c.bot_caduca AND NOT aten.atendido THEN c.bot_cambiado_at + crm.ventana_silencio_escalamiento()
            ELSE NULL::timestamp with time zone
        END AS vuelve_at,
    ( SELECT max(a.ocurrido_at) AS max
           FROM crm.actividades a
          WHERE a.contacto_id = c.id AND a.tipo = 'mensaje_entrante'::text) AS ultimo_entrante_at
   FROM crm.contactos c
     CROSS JOIN LATERAL ( SELECT c.bot_motivo = 'escalamiento'::text AND crm.bot_atendido_desde(c.id, c.bot_cambiado_at) AS atendido) aten
     LEFT JOIN crm.v_asesores u ON u.id = c.bot_cambiado_por
  WHERE c.deleted_at IS NULL AND NOT c.bot_activo
UNION ALL
 SELECT NULL::uuid AS contacto_id,
    f.inmobiliaria_id,
    f.nombre,
    f.telefono_e164,
    f.bot_motivo AS motivo,
    f.bot_cambiado_at AS callado_desde,
    f.bot_cambiado_por AS callado_por,
    u.nombre_completo AS callado_por_nombre,
    f.bot_caduca,
    aten.atendido,
        CASE
            WHEN f.bot_motivo = 'escalamiento'::text AND f.bot_caduca AND NOT aten.atendido THEN f.bot_cambiado_at + crm.ventana_silencio_escalamiento()
            ELSE NULL::timestamp with time zone
        END AS vuelve_at,
    f.ultimo_entrante_at
   FROM crm.frenos_bot f
     CROSS JOIN LATERAL ( SELECT f.bot_motivo = 'escalamiento'::text AND COALESCE(f.atendido_at > f.bot_cambiado_at, false) AS atendido) aten
     LEFT JOIN crm.v_asesores u ON u.id = f.bot_cambiado_por
  WHERE NOT f.bot_activo;

COMMENT ON VIEW crm.v_bot_callado IS
  'Todas las conversaciones con el bot callado (decisión 25), de contactos del '
  'CRM y del freno de quien no está en el CRM (contacto_id NULL).';


-- ---------------------------------------------------------------------
-- 7 · El archivo y la función que limpia
--
-- Las tablas de crm_archivo son copias sin llaves ni reglas: solo datos.
-- Nadie de la app las ve: el esquema no se le da a nadie, y PostgREST no
-- lo expone. Nacen vacías.
-- ---------------------------------------------------------------------
CREATE SCHEMA crm_archivo;
COMMENT ON SCHEMA crm_archivo IS
  'Lo que había en el CRM antes de pasar a solo líneas oficiales: el reflejo del '
  'bot comercial por Kommo. Cerrado. Se puede borrar del todo después del corte '
  'del 324 (paso 6).';

CREATE TABLE crm_archivo.contactos      (LIKE crm.contactos);
CREATE TABLE crm_archivo.identidades    (LIKE crm.identidades);
CREATE TABLE crm_archivo.actividades    (LIKE crm.actividades);
CREATE TABLE crm_archivo.oportunidades  (LIKE crm.oportunidades);
CREATE TABLE crm_archivo.transiciones   (LIKE crm.transiciones);
CREATE TABLE crm_archivo.requerimientos (LIKE crm.requerimientos);
CREATE TABLE crm_archivo.tareas         (LIKE crm.tareas);
CREATE TABLE crm_archivo.lecturas       (LIKE crm.lecturas);
CREATE TABLE crm_archivo.eventos        (LIKE crm.eventos);

REVOKE ALL ON SCHEMA crm_archivo FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL TABLES IN SCHEMA crm_archivo FROM PUBLIC, anon, authenticated, service_role;

-- Una vez por inmobiliaria, a mano (ver arriba). Se niega si ya hay
-- envíos: esto es para la era de Kommo, que no tenía, y borrar un contacto
-- se llevaría su historial de envíos sin archivar.
CREATE FUNCTION crm.archivar_era_kommo(p_inmobiliaria_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_res jsonb := '{}'::jsonb;
  v_n   integer;
BEGIN
  IF EXISTS (SELECT 1 FROM crm.envios e WHERE e.inmobiliaria_id = p_inmobiliaria_id)
     OR EXISTS (SELECT 1 FROM crm.envios_masivos m WHERE m.inmobiliaria_id = p_inmobiliaria_id) THEN
    RAISE EXCEPTION 'Esta inmobiliaria ya tiene envíos: archivarla borraría su historial'
      USING ERRCODE = '55000';
  END IF;

  -- 1. Los bots callados pasan al freno, con su conversación de la
  --    plataforma para que la proyección siga anotando quién escribe.
  INSERT INTO crm.frenos_bot
    (inmobiliaria_id, telefono_e164, conversacion_id, nombre,
     bot_activo, bot_motivo, bot_caduca, bot_cambiado_at, bot_cambiado_por,
     escalado_at, atendido_at, ultimo_entrante_at)
  SELECT DISTINCT ON (c.telefono_e164)
         c.inmobiliaria_id, c.telefono_e164,
         (SELECT conv.id
            FROM public.agente_comercial_conversaciones conv
           WHERE conv.inmobiliaria_id = c.inmobiliaria_id
             AND crm.normalizar_telefono(conv.telefono) = c.telefono_e164
           ORDER BY conv.updated_at DESC NULLS LAST
           LIMIT 1),
         c.nombre,
         false,
         CASE WHEN c.bot_motivo = 'escalamiento' THEN 'escalamiento' ELSE 'manual' END,
         c.bot_caduca,
         COALESCE(c.bot_cambiado_at, now()),
         c.bot_cambiado_por,
         (SELECT max(o.escalado_at) FROM crm.oportunidades o WHERE o.contacto_id = c.id),
         CASE WHEN c.bot_cambiado_at IS NOT NULL
               AND crm.bot_atendido_desde(c.id, c.bot_cambiado_at)
              THEN now() END,
         (SELECT max(a.ocurrido_at) FROM crm.actividades a
           WHERE a.contacto_id = c.id AND a.tipo = 'mensaje_entrante')
    FROM crm.contactos c
   WHERE c.inmobiliaria_id = p_inmobiliaria_id
     AND c.deleted_at IS NULL
     AND NOT c.bot_activo
     AND c.telefono_e164 IS NOT NULL
   ORDER BY c.telefono_e164, c.bot_cambiado_at DESC NULLS LAST
  ON CONFLICT (inmobiliaria_id, telefono_e164) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_res := v_res || jsonb_build_object('frenos', v_n);

  -- 2. Todo al archivo.
  INSERT INTO crm_archivo.contactos SELECT * FROM crm.contactos WHERE inmobiliaria_id = p_inmobiliaria_id;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_res := v_res || jsonb_build_object('contactos', v_n);
  INSERT INTO crm_archivo.identidades SELECT * FROM crm.identidades WHERE inmobiliaria_id = p_inmobiliaria_id;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_res := v_res || jsonb_build_object('identidades', v_n);
  INSERT INTO crm_archivo.actividades SELECT * FROM crm.actividades WHERE inmobiliaria_id = p_inmobiliaria_id;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_res := v_res || jsonb_build_object('actividades', v_n);
  INSERT INTO crm_archivo.oportunidades SELECT * FROM crm.oportunidades WHERE inmobiliaria_id = p_inmobiliaria_id;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_res := v_res || jsonb_build_object('oportunidades', v_n);
  INSERT INTO crm_archivo.transiciones SELECT * FROM crm.transiciones WHERE inmobiliaria_id = p_inmobiliaria_id;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_res := v_res || jsonb_build_object('transiciones', v_n);
  INSERT INTO crm_archivo.requerimientos SELECT * FROM crm.requerimientos WHERE inmobiliaria_id = p_inmobiliaria_id;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_res := v_res || jsonb_build_object('requerimientos', v_n);
  INSERT INTO crm_archivo.tareas SELECT * FROM crm.tareas WHERE inmobiliaria_id = p_inmobiliaria_id;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_res := v_res || jsonb_build_object('tareas', v_n);
  INSERT INTO crm_archivo.lecturas SELECT * FROM crm.lecturas WHERE inmobiliaria_id = p_inmobiliaria_id;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_res := v_res || jsonb_build_object('lecturas', v_n);
  INSERT INTO crm_archivo.eventos SELECT * FROM crm.eventos WHERE inmobiliaria_id = p_inmobiliaria_id;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_res := v_res || jsonb_build_object('eventos', v_n);

  -- 3. Fuera del CRM, los hijos primero.
  DELETE FROM crm.transiciones   WHERE inmobiliaria_id = p_inmobiliaria_id;
  DELETE FROM crm.oportunidades  WHERE inmobiliaria_id = p_inmobiliaria_id;
  DELETE FROM crm.actividades    WHERE inmobiliaria_id = p_inmobiliaria_id;
  DELETE FROM crm.requerimientos WHERE inmobiliaria_id = p_inmobiliaria_id;
  DELETE FROM crm.tareas         WHERE inmobiliaria_id = p_inmobiliaria_id;
  DELETE FROM crm.lecturas       WHERE inmobiliaria_id = p_inmobiliaria_id;
  DELETE FROM crm.eventos        WHERE inmobiliaria_id = p_inmobiliaria_id;
  DELETE FROM crm.identidades    WHERE inmobiliaria_id = p_inmobiliaria_id;
  DELETE FROM crm.contactos      WHERE inmobiliaria_id = p_inmobiliaria_id;

  -- 4. Desde ahora, solo líneas oficiales.
  INSERT INTO crm.preferencias
    (inmobiliaria_id, solo_lineas_oficiales, solo_lineas_desde)
  VALUES (p_inmobiliaria_id, true, now())
  ON CONFLICT (inmobiliaria_id) DO UPDATE
     SET solo_lineas_oficiales = true,
         solo_lineas_desde     = now(),
         updated_at            = now();

  RETURN v_res;
END $$;

-- service_role la conserva, como todo lo de crm (prueba 27): es el
-- servidor de la plataforma, y con su llave ya se puede borrar cualquier
-- tabla. Cerrarla aquí no protegería nada.
REVOKE ALL ON FUNCTION crm.archivar_era_kommo(uuid)
  FROM PUBLIC, anon, authenticated;
