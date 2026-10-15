-- =====================================================================
-- Plantillas por línea (tarea 3 del prompt del 9 oct, nota 10 del vault)
--
-- POR QUÉ UNA PLANTILLA ES DE UNA LÍNEA
-- Meta guarda las plantillas en la cuenta de WhatsApp (WABA) de cada
-- número. Una plantilla aprobada en la WABA del 320 no existe para el 324:
-- mandarla por ahí es un error 132001 delante del cliente. Así que cada
-- plantilla de WhatsApp sabe de qué línea es, y por ninguna otra sale.
--
-- Sin línea (NULL) significa lo mismo que en crm.envios: «el número por
-- defecto de la plataforma». Es lo que había antes de las líneas, y así
-- las plantillas viejas y sus envíos siguen funcionando igual.
--
-- LO QUE TRAE ADEMÁS
--  · Los valores de una plantilla para una persona salen de UNA función
--    (crm.valores_plantilla). La pantalla los usa para enseñar el texto y
--    el envío los usa para mandarle a Meta los parámetros con nombre.
--    Antes las plantillas salían sin sus variables: Meta habría rechazado
--    cualquier plantilla con {{nombre}}.
--  · La sincronización con Meta se hace aquí, con la sesión del admin, a
--    partir de lo que la plataforma trae de la WABA (contrato C2). El CRM
--    ya no habla con Meta ni guarda su token.
--  · crm.encolar_envio deja pasar fuera de la ventana solo una plantilla
--    de WhatsApp aprobada de ESA línea. Una respuesta rápida de chat sale
--    como texto libre, y fuera de la ventana Meta la rechaza.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1 · La línea de cada plantilla
-- ---------------------------------------------------------------------
ALTER TABLE crm.plantillas
  ADD COLUMN wa_phone_number_id text;

COMMENT ON COLUMN crm.plantillas.wa_phone_number_id IS
  'phone_number_id de la línea en cuya WABA vive la plantilla. Solo sale por esa línea. NULL = número por defecto de la plataforma; siempre NULL en las de chat.';

-- Una respuesta rápida de chat no pasa por Meta: no es de ninguna línea.
ALTER TABLE crm.plantillas
  ADD CONSTRAINT plantillas_chat_sin_linea
  CHECK (tipo <> 'chat' OR wa_phone_number_id IS NULL);

-- El nombre visible puede repetirse entre líneas («Recordatorio de pago»
-- en el 320 y en el 324). Dentro de una misma línea, no.
DROP INDEX crm.plantillas_nombre_unico;
CREATE UNIQUE INDEX plantillas_nombre_unico
  ON crm.plantillas (inmobiliaria_id, COALESCE(wa_phone_number_id, ''), lower(btrim(nombre)))
  WHERE activa;

-- Y Meta no admite dos plantillas con el mismo nombre e idioma en una
-- WABA: es también la llave con la que se sincroniza.
CREATE UNIQUE INDEX plantillas_meta_por_linea
  ON crm.plantillas (inmobiliaria_id, wa_phone_number_id, nombre_meta, idioma)
  WHERE activa AND tipo = 'whatsapp'
    AND wa_phone_number_id IS NOT NULL AND nombre_meta IS NOT NULL;

-- ---------------------------------------------------------------------
-- 2 · Los valores de una plantilla, y el relleno
--
-- Dos funciones puras y una que lee:
--   hueco_variable   qué se enseña cuando falta un dato («[sin precio]»)
--   rellenar_cuerpo  pone los valores en el cuerpo, en UNA pasada
--   valores_plantilla los valores de verdad, solo de las variables que el
--                    cuerpo usa; NULL donde falta el dato
--
-- render_plantilla queda como valores + relleno: el texto que ve el
-- asesor y los parámetros que recibe Meta salen de la misma fuente.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.hueco_variable(p_variable text)
RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = ''
AS $hv$
  SELECT CASE p_variable
    WHEN 'nombre'       THEN '[sin nombre]'
    WHEN 'telefono'     THEN '[sin teléfono]'
    WHEN 'asesor'       THEN '[asesor]'
    WHEN 'inmueble'     THEN '[sin inmueble]'
    WHEN 'barrio'       THEN '[sin barrio]'
    WHEN 'ciudad'       THEN '[sin ciudad]'
    WHEN 'precio'       THEN '[sin precio]'
    WHEN 'habitaciones' THEN '[sin dato]'
    ELSE '[sin ' || replace(p_variable, '_', ' ') || ']'
  END;
$hv$;

COMMENT ON FUNCTION crm.hueco_variable(text) IS
  'Lo que se ve en lugar de una variable sin dato. Visible a propósito: un corchete lo para el asesor; un hueco vacío llega al cliente.';

-- Una sola pasada, de izquierda a derecha: lo que se pone nunca se vuelve
-- a leer. Así un valor que traiga «{{precio}}» o una barra invertida no
-- se interpreta, cosa que con regexp_replace sí pasaría.
CREATE OR REPLACE FUNCTION crm.rellenar_cuerpo(p_cuerpo text, p_valores jsonb)
RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path = ''
AS $rc$
DECLARE
  v_patron constant text := '\{\{\s*[a-z_]+\s*\}\}';
  v_resto  text := COALESCE(p_cuerpo, '');
  v_salida text := '';
  v_ini    int;
  v_fin    int;
  v_var    text;
BEGIN
  LOOP
    v_ini := regexp_instr(v_resto, v_patron);
    EXIT WHEN v_ini = 0;
    v_fin := regexp_instr(v_resto, v_patron, 1, 1, 1);
    v_var := (regexp_match(substr(v_resto, v_ini, v_fin - v_ini), '([a-z_]+)'))[1];

    v_salida := v_salida
             || substr(v_resto, 1, v_ini - 1)
             || COALESCE(NULLIF(btrim(p_valores ->> v_var), ''), crm.hueco_variable(v_var));
    v_resto := substr(v_resto, v_fin);
  END LOOP;

  RETURN v_salida || v_resto;
END $rc$;

COMMENT ON FUNCTION crm.rellenar_cuerpo(text, jsonb) IS
  'Pone los valores en el cuerpo de una plantilla. Lo que falta queda como hueco visible (crm.hueco_variable).';

CREATE OR REPLACE FUNCTION crm.valores_plantilla(
  p_plantilla_id uuid,
  p_contacto_id  uuid DEFAULT NULL,
  p_inmueble_id  uuid DEFAULT NULL,
  p_asesor       text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path = ''
AS $vp$
DECLARE
  v_cuerpo text;
  v_todos  jsonb;
  c record;
  i record;
BEGIN
  SELECT p.cuerpo INTO v_cuerpo
    FROM crm.plantillas p WHERE p.id = p_plantilla_id AND p.activa;
  IF v_cuerpo IS NULL THEN RETURN NULL; END IF;

  SELECT ct.nombre, ct.telefono_e164 INTO c
    FROM crm.contactos ct WHERE ct.id = p_contacto_id;

  SELECT v.titulo, v.barrio, v.ciudad, v.precio, v.habitaciones INTO i
    FROM crm.v_inmuebles v WHERE v.id = p_inmueble_id;

  v_todos := jsonb_build_object(
    'nombre',       NULLIF(btrim(c.nombre), ''),
    'telefono',     c.telefono_e164,
    'asesor',       NULLIF(btrim(p_asesor), ''),
    'inmueble',     i.titulo,
    'barrio',       i.barrio,
    'ciudad',       i.ciudad,
    -- Separador de miles forzado a punto: 'G' usa el del locale del
    -- servidor, que en esta base es la coma. "$1,500,000" se lee mal aquí.
    'precio',       '$' || replace(to_char(i.precio, 'FM999G999G999'), ',', '.'),
    'habitaciones', i.habitaciones::text
  );

  -- Solo las que el cuerpo usa. Una que el CRM no sabe llenar queda en
  -- NULL: quien envía decide qué hacer con ella, nunca se inventa.
  RETURN (
    SELECT COALESCE(jsonb_object_agg(u.v, v_todos -> u.v), '{}'::jsonb)
      FROM (SELECT DISTINCT (regexp_matches(v_cuerpo, '\{\{\s*([a-z_]+)\s*\}\}', 'g'))[1] AS v) u
  );
END $vp$;

COMMENT ON FUNCTION crm.valores_plantilla(uuid, uuid, uuid, text) IS
  'Los valores de las variables que usa la plantilla, para esta persona. NULL donde falta el dato. Es lo que viaja a Meta como parámetros con nombre.';

CREATE OR REPLACE FUNCTION crm.render_plantilla(
  p_plantilla_id uuid,
  p_contacto_id  uuid DEFAULT NULL,
  p_inmueble_id  uuid DEFAULT NULL,
  p_asesor       text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path = ''
AS $render$
DECLARE
  v_cuerpo text;
BEGIN
  SELECT p.cuerpo INTO v_cuerpo
    FROM crm.plantillas p WHERE p.id = p_plantilla_id AND p.activa;
  IF v_cuerpo IS NULL THEN RETURN NULL; END IF;

  RETURN crm.rellenar_cuerpo(
    v_cuerpo,
    crm.valores_plantilla(p_plantilla_id, p_contacto_id, p_inmueble_id, p_asesor));
END $render$;

GRANT EXECUTE ON FUNCTION crm.hueco_variable(text) TO authenticated;
GRANT EXECUTE ON FUNCTION crm.rellenar_cuerpo(text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION crm.valores_plantilla(uuid, uuid, uuid, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 3 · Sincronizar con lo que hay en Meta
--
-- La plataforma trae las plantillas de la WABA de una línea (contrato
-- C2) y el CRM las cruza aquí, con la sesión del admin y su RLS.
--
-- La llave es (línea, nombre en Meta, idioma). Si no está, se adopta un
-- borrador sin línea con ese mismo nombre en Meta, y si tampoco, se crea.
--
-- NO SE TRAE lo que no se podría mandar bien: variables numeradas
-- ({{1}}), variables que el CRM no conoce, categoría de autenticación o
-- un idioma que el CRM no maneja. Se devuelven en «omitidas», con el
-- motivo, para que el admin sepa que existen.
--
-- Una plantilla que estaba enviada o aprobada en esta línea y ya no está
-- en Meta pasa a rechazada: mandarla daría error delante del cliente.
-- Solo si la lista llegó completa (p_completa), porque una lista cortada
-- haría creer que se borraron las que no cupieron.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.sincronizar_plantillas(
  p_wa_phone_number_id text,
  p_remotas            jsonb,
  p_completa           boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = ''
AS $sp$
DECLARE
  v_linea      constant text := NULLIF(btrim(p_wa_phone_number_id), '');
  v_org        uuid;
  r            jsonb;
  v_nombre_meta text;
  v_idioma     text;
  v_cuerpo     text;
  v_categoria  text;
  v_estado     text;
  v_motivo     text;
  v_nombre     text;
  v_id         uuid;
  v_vistas     text[] := ARRAY[]::text[];
  v_omitidas   jsonb  := '[]'::jsonb;
  v_agregadas  int := 0;
  v_actualizadas int := 0;
  v_retiradas  int := 0;
BEGIN
  IF public.get_my_role() IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'Solo un administrador sincroniza las plantillas con Meta'
      USING ERRCODE = '42501';
  END IF;

  -- La RLS de crm.lineas ya esconde las ajenas.
  SELECT l.inmobiliaria_id INTO v_org
    FROM crm.lineas l
   WHERE l.wa_phone_number_id = v_linea AND l.activa;
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Esa línea no es de esta inmobiliaria o no está activa'
      USING ERRCODE = '22023';
  END IF;

  IF jsonb_typeof(p_remotas) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Se esperaba la lista de plantillas de Meta'
      USING ERRCODE = '22023';
  END IF;

  FOR r IN SELECT x FROM jsonb_array_elements(p_remotas) x LOOP
    v_nombre_meta := NULLIF(btrim(r ->> 'name'), '');
    v_idioma      := NULLIF(btrim(r ->> 'language'), '');
    IF v_nombre_meta IS NULL THEN CONTINUE; END IF;

    v_vistas := v_vistas || (v_nombre_meta || '|' || COALESCE(v_idioma, ''));

    v_cuerpo := (
      SELECT c ->> 'text'
        FROM jsonb_array_elements(COALESCE(r -> 'components', '[]'::jsonb)) c
       WHERE upper(c ->> 'type') = 'BODY'
       LIMIT 1);

    v_categoria := CASE upper(r ->> 'category')
                     WHEN 'MARKETING' THEN 'marketing'
                     WHEN 'UTILITY'   THEN 'utilidad'
                   END;

    v_motivo := CASE
      WHEN v_idioma IS NULL OR NOT v_idioma = ANY (ARRAY['es', 'es_CO', 'en', 'en_US'])
        THEN 'Idioma que el CRM no maneja: ' || COALESCE(v_idioma, 'ninguno')
      WHEN btrim(COALESCE(v_cuerpo, '')) = ''
        THEN 'No tiene cuerpo de texto'
      WHEN v_cuerpo ~ '\{\{\s*[0-9]+\s*\}\}'
        THEN 'Usa variables numeradas ({{1}}): el CRM solo llena variables con nombre'
      WHEN cardinality(crm.variables_desconocidas(v_cuerpo)) > 0
        THEN 'Usa variables que el CRM no conoce: '
             || array_to_string(crm.variables_desconocidas(v_cuerpo), ', ')
      WHEN v_categoria IS NULL
        THEN 'Categoría que el CRM no usa: ' || COALESCE(r ->> 'category', 'ninguna')
    END;

    IF v_motivo IS NOT NULL THEN
      v_omitidas := v_omitidas || jsonb_build_object('nombre_meta', v_nombre_meta, 'motivo', v_motivo);
      CONTINUE;
    END IF;

    v_estado := CASE upper(r ->> 'status')
                  WHEN 'APPROVED'  THEN 'aprobada'
                  WHEN 'PENDING'   THEN 'enviada'
                  WHEN 'IN_APPEAL' THEN 'enviada'
                  ELSE 'rechazada'
                END;

    -- Meta manda rejected_reason = 'NONE' en las que no rechazó.
    v_motivo := CASE WHEN v_estado = 'rechazada' THEN
                  COALESCE(NULLIF(NULLIF(btrim(r ->> 'rejected_reason'), ''), 'NONE'),
                           CASE upper(r ->> 'status')
                             WHEN 'PAUSED'   THEN 'Pausada por Meta por baja calidad'
                             WHEN 'DISABLED' THEN 'Deshabilitada por Meta'
                             ELSE 'Estado en Meta: ' || COALESCE(r ->> 'status', 'desconocido')
                           END)
                END;

    SELECT p.id INTO v_id
      FROM crm.plantillas p
     WHERE p.inmobiliaria_id = v_org
       AND p.wa_phone_number_id = v_linea
       AND p.nombre_meta = v_nombre_meta
       AND p.idioma = v_idioma
       AND p.tipo = 'whatsapp'
       AND p.activa
     LIMIT 1;

    -- Un borrador de antes de las líneas, con ese nombre en Meta, se adopta.
    IF v_id IS NULL THEN
      SELECT p.id INTO v_id
        FROM crm.plantillas p
       WHERE p.inmobiliaria_id = v_org
         AND p.wa_phone_number_id IS NULL
         AND p.nombre_meta = v_nombre_meta
         AND p.idioma = v_idioma
         AND p.tipo = 'whatsapp'
         AND p.activa
       LIMIT 1;
    END IF;

    IF v_id IS NOT NULL THEN
      UPDATE crm.plantillas
         SET wa_phone_number_id  = v_linea,
             cuerpo              = v_cuerpo,
             categoria           = v_categoria,
             estado_meta         = v_estado,
             motivo_rechazo_meta = v_motivo,
             updated_at          = now()
       WHERE id = v_id;
      v_actualizadas := v_actualizadas + 1;
    ELSE
      v_nombre := replace(v_nombre_meta, '_', ' ');
      v_nombre := upper(left(v_nombre, 1)) || substr(v_nombre, 2);
      IF EXISTS (SELECT 1 FROM crm.plantillas p
                  WHERE p.inmobiliaria_id = v_org
                    AND COALESCE(p.wa_phone_number_id, '') = v_linea
                    AND lower(btrim(p.nombre)) = lower(btrim(v_nombre))
                    AND p.activa) THEN
        v_nombre := v_nombre || ' (' || v_idioma || ')';
      END IF;

      INSERT INTO crm.plantillas
        (inmobiliaria_id, nombre, cuerpo, categoria, tipo, estado_meta,
         nombre_meta, idioma, motivo_rechazo_meta, wa_phone_number_id, creada_por)
      VALUES
        (v_org, v_nombre, v_cuerpo, v_categoria, 'whatsapp', v_estado,
         v_nombre_meta, v_idioma, v_motivo, v_linea, (SELECT auth.uid()));
      v_agregadas := v_agregadas + 1;
    END IF;
  END LOOP;

  IF p_completa THEN
    UPDATE crm.plantillas p
       SET estado_meta = 'rechazada',
           motivo_rechazo_meta = 'Ya no está en Meta: se borró de la cuenta de WhatsApp de esta línea',
           updated_at = now()
     WHERE p.inmobiliaria_id = v_org
       AND p.wa_phone_number_id = v_linea
       AND p.tipo = 'whatsapp'
       AND p.activa
       AND p.estado_meta IN ('enviada', 'aprobada')
       AND NOT ((COALESCE(p.nombre_meta, '') || '|' || p.idioma) = ANY (v_vistas));
    GET DIAGNOSTICS v_retiradas = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'total',        jsonb_array_length(p_remotas),
    'agregadas',    v_agregadas,
    'actualizadas', v_actualizadas,
    'retiradas',    v_retiradas,
    'omitidas',     v_omitidas);
END $sp$;

COMMENT ON FUNCTION crm.sincronizar_plantillas(text, jsonb, boolean) IS
  'Cruza las plantillas de la WABA de una línea (traídas por la plataforma, contrato C2) con crm.plantillas. Solo admin. Devuelve cuántas agregó, actualizó, retiró y cuáles omitió y por qué.';

GRANT EXECUTE ON FUNCTION crm.sincronizar_plantillas(text, jsonb, boolean) TO authenticated;

-- ---------------------------------------------------------------------
-- 4 · encolar_envio: la plantilla, de esta línea y de WhatsApp
--
-- Dos cambios sobre la versión del 9 oct, nada más:
--  · Solo una plantilla de WHATSAPP aprobada abre la puerta fuera de la
--    ventana. Las respuestas rápidas de chat nacen «aprobadas» en local,
--    pero salen como texto libre: fuera de la ventana Meta las rechaza.
--  · La plantilla de WhatsApp tiene que ser de la línea del envío.
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
  v_tipo text;
  v_linea_plantilla text;
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

  IF p_plantilla_id IS NOT NULL THEN
    SELECT p.tipo, p.wa_phone_number_id, (p.tipo = 'whatsapp' AND p.estado_meta = 'aprobada')
      INTO v_tipo, v_linea_plantilla, v_aprobada
      FROM crm.plantillas p WHERE p.id = p_plantilla_id AND p.activa;
    v_aprobada := COALESCE(v_aprobada, false);

    -- Vive en la WABA de una línea: por otra no existe.
    IF v_tipo = 'whatsapp' AND v_linea_plantilla IS DISTINCT FROM v_pnid THEN
      RAISE EXCEPTION 'Esa plantilla es de otra línea: por esta no se puede enviar'
        USING ERRCODE = '22023';
    END IF;
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
