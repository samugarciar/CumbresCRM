-- =====================================================================
-- WhatsApp: la gente con «@» que no nos ha dado su número (28 oct 2026)
--
-- EL CASO QUE LO TRAE
-- Desde 2026 una persona puede tener nombre de usuario en WhatsApp y
-- esconder su número. Entonces Meta no manda el teléfono: manda solo el
-- BSUID (business-scoped user ID), un identificador de esa persona para
-- nuestro portafolio, con la forma «CO.13491208655302741918» (país, punto,
-- hasta 128 letras o números; los padres llevan ENT: «US.ENT.1181…»).
-- Los mensajes de @DavidRodas27 se perdieron el 28 oct: el webhook de la
-- plataforma daba por hecho que el teléfono siempre venía.
--
-- La plataforma ahora lleva esa conversación con el BSUID donde iría el
-- teléfono (public.agente_comercial_conversaciones.telefono) y le contesta
-- con `recipient`. Aquí, la persona tiene que existir en el CRM:
--  · crm.identidades admite el tipo 'whatsapp_bsuid';
--  · crm.resolver_contacto lo conoce, justo después del teléfono;
--  · crm.proyectar_mensaje, si la conversación no trae un teléfono sino un
--    BSUID, se lo da como identidad (y no lo guarda como teléfono crudo);
--  · crm.bot_puede_responder y crm.registrar_relevo la encuentran también
--    por su BSUID: apagarle el bot a mano y el relevo funcionan igual.
--
-- Cuerpos tomados de producción el 28 oct (pg_get_functiondef), con solo
-- esos cambios. CREATE OR REPLACE conserva los permisos. Idempotente.
-- =====================================================================

ALTER TABLE crm.identidades
  DROP CONSTRAINT IF EXISTS identidades_tipo_check,
  ADD CONSTRAINT identidades_tipo_check CHECK (tipo = ANY (ARRAY[
    'telefono_e164'::text, 'whatsapp_bsuid'::text, 'whatsapp_username'::text, 'kommo_lead'::text,
    'kommo_contact'::text, 'email'::text, 'meta_psid'::text, 'otro'::text]));


-- ---------------------------------------------------------------------
-- 1 · resolver_contacto: el BSUID, justo después del teléfono
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.resolver_contacto(p_inmobiliaria_id uuid, p_identidades jsonb, p_nombre text DEFAULT NULL::text, p_origen text DEFAULT NULL::text, p_tipo_contacto text DEFAULT 'cliente'::text, p_telefono_crudo text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_orden constant text[] := ARRAY[
    'telefono_e164', 'whatsapp_bsuid', 'whatsapp_username', 'kommo_lead',
    'kommo_contact', 'email', 'meta_psid', 'otro'
  ];
  v_tipo      text;
  v_contacto  uuid;
  v_ident     jsonb;
  v_nuevo     boolean := false;
  v_otro      uuid;
BEGIN
  IF p_identidades IS NULL OR jsonb_array_length(p_identidades) = 0 THEN
    RETURN NULL;
  END IF;

  FOREACH v_tipo IN ARRAY v_orden LOOP
    SELECT i.contacto_id INTO v_contacto
      FROM crm.identidades i
      JOIN jsonb_array_elements(p_identidades) e
        ON e->>'tipo' = i.tipo AND e->>'valor' = i.valor
     WHERE i.inmobiliaria_id = p_inmobiliaria_id
       AND i.tipo = v_tipo
     LIMIT 1;
    EXIT WHEN v_contacto IS NOT NULL;
  END LOOP;

  IF v_contacto IS NULL THEN
    INSERT INTO crm.contactos (inmobiliaria_id, nombre, origen, tipo, telefono_crudo)
    VALUES (p_inmobiliaria_id, p_nombre, p_origen,
            COALESCE(p_tipo_contacto, 'cliente'), p_telefono_crudo)
    RETURNING id INTO v_contacto;
    v_nuevo := true;
  ELSE
    -- EL CAMBIO: el nombre se elige por calidad, no por orden de llegada.
    -- El resto sigue siendo "lo primero que se supo gana", porque para
    -- origen y teléfono crudo el dato más viejo es el que alguien
    -- verificó a mano.
    UPDATE crm.contactos
       SET nombre         = crm.mejor_nombre(nombre, p_nombre),
           origen         = COALESCE(origen, p_origen),
           telefono_crudo = COALESCE(telefono_crudo, p_telefono_crudo)
     WHERE id = v_contacto;
  END IF;

  FOR v_ident IN SELECT * FROM jsonb_array_elements(p_identidades) LOOP
    INSERT INTO crm.identidades (inmobiliaria_id, contacto_id, tipo, valor, origen)
    VALUES (p_inmobiliaria_id, v_contacto,
            v_ident->>'tipo', v_ident->>'valor', p_origen)
    ON CONFLICT (inmobiliaria_id, tipo, valor) DO NOTHING;

    -- LA CARRERA (26 oct). Dos mensajes de un número nuevo que entran a la
    -- vez: las dos transacciones buscaban la identidad, no la encontraban y
    -- creaban cada una su contacto; la segunda identidad chocaba con la de
    -- la primera y su mensaje quedaba colgado de un contacto sin teléfono.
    -- El índice único hace esperar a la segunda hasta que la primera
    -- termina; si entonces resulta que la identidad ya es de OTRO contacto,
    -- el que esta llamada acaba de crear sobra: se borra (aún no tiene nada
    -- más que sus identidades) y se resuelve otra vez, ahora encontrándolo.
    -- Sin candados: el backfill resuelve miles de personas en una sola
    -- transacción y no puede llenar la tabla de candados.
    IF v_nuevo AND NOT FOUND THEN
      SELECT i.contacto_id INTO v_otro
        FROM crm.identidades i
       WHERE i.inmobiliaria_id = p_inmobiliaria_id
         AND i.tipo  = v_ident->>'tipo'
         AND i.valor = v_ident->>'valor';
      IF v_otro IS NOT NULL AND v_otro <> v_contacto THEN
        DELETE FROM crm.contactos WHERE id = v_contacto;
        RETURN crm.resolver_contacto(p_inmobiliaria_id, p_identidades, p_nombre,
                                     p_origen, p_tipo_contacto, p_telefono_crudo);
      END IF;
    END IF;
  END LOOP;

  RETURN v_contacto;
END $function$;

-- ---------------------------------------------------------------------
-- 2 · proyectar_mensaje: sin teléfono, la identidad es el BSUID
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.proyectar_mensaje()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_org      uuid;
  v_contacto uuid;
  v_ids      jsonb := '[]'::jsonb;
  v_tel      text;
  v_bsuid    text;
  v_conv     record;
  v_pnid     text;
  v_wamid    text;
  v_tipo     text;
  v_dup_id   bigint;
  v_cuerpo   text;
  v_escalado boolean := false;
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
    -- Quien tiene «@» en WhatsApp y no nos ha dado el número llega con su
    -- BSUID en lugar del teléfono (20261028100001): esa es su identidad.
    IF v_tel IS NULL AND btrim(v_conv.telefono) ~ '^[A-Z]{2}\.(ENT\.)?[A-Za-z0-9]{1,128}$' THEN
      v_bsuid := btrim(v_conv.telefono);
      v_ids := v_ids || jsonb_build_array(
        jsonb_build_object('tipo', 'whatsapp_bsuid', 'valor', v_bsuid));
    END IF;
    -- Con solo líneas oficiales, aquí solo llega lo que entró por una línea
    -- de crm.lineas (la guarda de arriba corta lo demás). Esa persona es la
    -- de ESE teléfono: el lead y el contacto de Kommo que arrastre la
    -- conversación son de la era anterior y no se le pegan (26 oct). Las
    -- identidades que ya tenga no se tocan.
    IF NOT crm.solo_lineas_oficiales(v_org) THEN
      IF v_conv.kommo_lead_id IS NOT NULL THEN
        v_ids := v_ids || jsonb_build_array(
          jsonb_build_object('tipo', 'kommo_lead', 'valor', v_conv.kommo_lead_id));
      END IF;
      IF v_conv.kommo_contact_id IS NOT NULL THEN
        v_ids := v_ids || jsonb_build_array(
          jsonb_build_object('tipo', 'kommo_contact', 'valor', v_conv.kommo_contact_id));
      END IF;
    END IF;

    v_contacto := crm.resolver_contacto(
      v_org, v_ids, v_conv.cliente_nombre, 'whatsapp', 'cliente',
      CASE WHEN v_bsuid IS NULL THEN v_conv.telefono END);

    IF v_contacto IS NULL THEN
      RETURN NULL;
    END IF;

    v_tipo := CASE WHEN NEW.rol = 'usuario' THEN 'mensaje_entrante' ELSE 'mensaje_saliente' END;

    -- El agente guarda su borrador CRUDO, con la etiqueta [ESCALAR] al
    -- principio cuando pide un asesor (la lee n8n y la memoria del bot). Al
    -- cliente nunca le llega; en el chat del CRM tampoco se enseña: se quita
    -- y queda dicho en metadata.escalado.
    v_cuerpo := NEW.contenido;
    IF NEW.rol = 'agente' AND NEW.contenido ~* '^\s*\[ESCALAR\]' THEN
      v_cuerpo   := regexp_replace(NEW.contenido, '^\s*\[ESCALAR\]\s*', '', 'i');
      v_escalado := true;
    END IF;

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
         AND a.cuerpo = v_cuerpo
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
      v_contacto, v_cuerpo, NEW.created_at,
      jsonb_build_object(
        'origen_tabla', 'agente_comercial_mensajes',
        'origen_id', NEW.id::text,
        'wa_message_id', v_wamid
      )
        -- La foto, el audio o el documento (ver la migración 2026-10-25 de la
        -- plataforma). Se lee con to_jsonb para no depender de la columna.
        || CASE WHEN jsonb_typeof(to_jsonb(NEW) -> 'medio') = 'object'
                THEN jsonb_build_object('medio', to_jsonb(NEW) -> 'medio')
                ELSE '{}'::jsonb END
        || CASE WHEN v_escalado THEN '{"escalado": true}'::jsonb ELSE '{}'::jsonb END,
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
END $function$;

-- ---------------------------------------------------------------------
-- 3 · bot_puede_responder: también por BSUID
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.bot_puede_responder(p_inmobiliaria_id uuid, p_telefono text, p_wa_phone_number_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT COALESCE(
           (SELECT bool_and(c.bot_activo)
              FROM crm.contactos c
             WHERE c.inmobiliaria_id = p_inmobiliaria_id
               AND (c.telefono_e164 = crm.normalizar_telefono(p_telefono)
                    OR c.id IN (SELECT i.contacto_id
                                  FROM crm.identidades i
                                 WHERE i.inmobiliaria_id = p_inmobiliaria_id
                                   AND i.tipo = 'whatsapp_bsuid'
                                   AND i.valor = btrim(p_telefono)))
               AND c.deleted_at IS NULL),
           true)
     AND (
           -- Entró por una línea oficial: el freno de la 324 no aplica.
           EXISTS (SELECT 1
                     FROM crm.lineas l
                    WHERE p_wa_phone_number_id IS NOT NULL
                      AND l.wa_phone_number_id = p_wa_phone_number_id
                      AND l.inmobiliaria_id = p_inmobiliaria_id
                      AND l.activa)
           OR COALESCE(
                (SELECT f.bot_activo
                   FROM crm.frenos_bot f
                  WHERE f.inmobiliaria_id = p_inmobiliaria_id
                    AND f.telefono_e164 = crm.normalizar_telefono(p_telefono)),
                true)
         );
$function$;

-- ---------------------------------------------------------------------
-- 4 · registrar_relevo: también por BSUID
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.registrar_relevo(p_wa_phone_number_id text, p_telefono text, p_ocurrido_at timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_inmobiliaria uuid;
  v_bot_atiende  boolean;
  -- Un reloj adelantado no puede estirar el relevo hacia el futuro.
  v_momento      timestamptz := LEAST(COALESCE(p_ocurrido_at, now()), now());
  v_contacto     crm.contactos%ROWTYPE;
  v_duracion     text := crm.duracion_legible(crm.ventana_relevo());
BEGIN
  SELECT l.inmobiliaria_id, e.bot_atiende INTO v_inmobiliaria, v_bot_atiende
    FROM crm.lineas l
    JOIN crm.embudos e ON e.codigo = l.embudo
   WHERE l.wa_phone_number_id = p_wa_phone_number_id
     AND l.activa;

  IF v_inmobiliaria IS NULL OR NOT v_bot_atiende THEN
    RETURN false;
  END IF;

  -- La FRESCURA, no la ventana: la segunda red contra el historial que
  -- Meta reproduce al conectar (20261001150001). Con la ventana en 1 h la
  -- guarda de abajo es más estricta, pero esta sigue protegiendo si un día
  -- la ventana sube por encima de las 6 h.
  IF v_momento < now() - crm.frescura_relevo() THEN
    RETURN false;
  END IF;

  -- Un relevo que nace vencido no se abre: un eco atrasado más de una
  -- ventana callaría al bot solo para devolverle la voz en la siguiente
  -- pasada del cron, con dos avisos en el historial. Y sobre un relevo
  -- abierto no movería nada que importe.
  IF v_momento <= now() - crm.ventana_relevo() THEN
    RETURN false;
  END IF;

  SELECT * INTO v_contacto
    FROM crm.contactos c
   WHERE c.inmobiliaria_id = v_inmobiliaria
     AND (c.telefono_e164 = crm.normalizar_telefono(p_telefono)
          OR c.id IN (SELECT i.contacto_id
                        FROM crm.identidades i
                       WHERE i.inmobiliaria_id = v_inmobiliaria
                         AND i.tipo = 'whatsapp_bsuid'
                         AND i.valor = btrim(p_telefono)))
     AND c.deleted_at IS NULL
   FOR UPDATE OF c;

  IF v_contacto.id IS NULL THEN
    RETURN false;
  END IF;

  IF v_contacto.bot_activo THEN
    UPDATE crm.contactos
       SET bot_activo       = false,
           bot_motivo       = 'relevo',
           bot_cambiado_at  = v_momento,
           bot_cambiado_por = NULL   -- el eco no dice QUIÉN escribió
     WHERE id = v_contacto.id;

    INSERT INTO crm.actividades
      (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
    VALUES (v_contacto.inmobiliaria_id, 'sistema', 'sistema', v_contacto.id,
            'El bot deja de responderle: alguien del equipo le escribió.',
            v_momento);

  ELSIF v_contacto.bot_motivo = 'escalamiento' AND v_contacto.bot_caduca THEN
    -- Pidió una persona y una persona le escribió: desde aquí es un
    -- relevo como cualquiera. Si el asesor no vuelve a escribir en una
    -- ventana, el bot vuelve.
    UPDATE crm.contactos
       SET bot_motivo       = 'relevo',
           bot_cambiado_at  = v_momento,
           bot_cambiado_por = NULL
     WHERE id = v_contacto.id;

    INSERT INTO crm.actividades
      (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
    VALUES (v_contacto.inmobiliaria_id, 'sistema', 'sistema', v_contacto.id,
            'Alguien del equipo atendió a quien pidió una persona: el bot vuelve si nadie le escribe en '
              || v_duracion || '.',
            v_momento);

  ELSIF v_contacto.bot_motivo = 'relevo' THEN
    -- Ya estaba en relevo: la ventana corre con el último mensaje. Sin
    -- aviso nuevo; uno por mensaje enterraría el historial.
    UPDATE crm.contactos
       SET bot_cambiado_at = GREATEST(bot_cambiado_at, v_momento)
     WHERE id = v_contacto.id;

  ELSE
    -- Manual, o un escalamiento que alguien dejó sin caducidad: manda
    -- quien lo decidió.
    RETURN false;
  END IF;

  RETURN true;
END $function$;
