-- =====================================================================
-- Un token que Meta deja de aceptar se ve en la pantalla de líneas.
--
-- AJUSTE A LA DECISIÓN 23 (1 oct 2026)
-- "Un token que Meta invalida tiene que dejar la línea en un estado
-- visible, no fallar en silencio en cada envío." Y "el token no puede
-- aparecer nunca en logs, trazas ni errores".
--
-- Un token muere sin avisar: alguien cambia la contraseña de la cuenta
-- de Meta, se revoca el acceso de la app, caduca. Desde ese momento cada
-- envío falla con el código 190 y cada falla, vista sola, parece un
-- mensaje que no salió. Sin un estado en la línea, nadie ve que lo que
-- se cayó es la LÍNEA entera.
--
-- EL ESTADO
-- Tres columnas: desde cuándo (la PRIMERA vez que Meta lo rechazó, para
-- que la pantalla diga cuánto lleva caída) y el último código y mensaje
-- de Meta. Se limpian de dos maneras:
--   · reconectando la línea, que guarda un token nuevo;
--   · con el evento contrario, `token_valido`, que la plataforma anota
--     cuando una llamada con esa misma credencial vuelve a funcionar.
--     Sin él, una línea que usa la credencial general de la plataforma
--     —que no se cambia reconectando— quedaría marcada para siempre.
--
-- EL TOKEN NO SE CUELA EN NINGÚN ERROR
-- Un mensaje de error de Meta no debería traer el token, pero uno
-- armado por la plataforma podría. crm.retirar_token() es el ÚNICO sitio
-- donde se reconoce la forma de un token: lo usan estos eventos, el
-- error del historial y el registro de intentos de incorporación, que
-- hasta hoy tenía su propia copia de la expresión.
-- =====================================================================

-- ---------------------------------------------------------------------
-- La forma de un token de Meta, en un solo sitio
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.retirar_token(p_texto text)
RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = ''
AS $retirar$
  -- Los tokens de Meta empiezan por EAA y son muy largos. Treinta
  -- caracteres de margen para no confundirlos con un id corto.
  SELECT regexp_replace(p_texto, 'EAA[A-Za-z0-9]{30,}', '[token retirado]', 'g');
$retirar$;

COMMENT ON FUNCTION crm.retirar_token(text) IS
  'Sustituye todo lo que tenga forma de token de Meta (EAA…) por [token retirado]. El único sitio donde se reconoce esa forma.';

-- Solo la usan funciones que corren como su dueño.
REVOKE ALL ON FUNCTION crm.retirar_token(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION crm.retirar_token(text) TO service_role;


-- ---------------------------------------------------------------------
-- El estado de la línea
-- ---------------------------------------------------------------------
ALTER TABLE crm.lineas
  ADD COLUMN token_invalido_at  timestamptz,
  ADD COLUMN token_error_codigo integer,
  ADD COLUMN token_error        text;

COMMENT ON COLUMN crm.lineas.token_invalido_at IS
  'Desde cuándo Meta rechaza el token de esta línea (la primera vez). NULL = no se sabe de ningún rechazo. Lo anota la plataforma con registrar_estado_linea(''token_invalido''); se limpia al reconectar o con ''token_valido''.';
COMMENT ON COLUMN crm.lineas.token_error IS
  'Último mensaje de Meta al rechazar el token, con cualquier cosa con forma de token ya retirada.';


-- ---------------------------------------------------------------------
-- Reconectar guarda un token nuevo: la alarma del viejo deja de valer.
-- Misma firma; lo nuevo son las tres líneas del token.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.conectar_linea(
  p_inmobiliaria_id    uuid,
  p_embudo             text,
  p_waba_id            text,
  p_wa_phone_number_id text,
  p_modo               text,
  p_token              text,
  p_telefono_e164      text DEFAULT NULL,
  p_nombre             text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $conectar$
DECLARE
  v_linea   crm.lineas%ROWTYPE;
  v_secreto uuid;
BEGIN
  IF p_modo IS NULL OR p_modo NOT IN ('coexistencia', 'cloud_api') THEN
    RAISE EXCEPTION 'Modo desconocido: %. Es coexistencia o cloud_api.', p_modo
      USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM crm.embudos e WHERE e.codigo = p_embudo) THEN
    RAISE EXCEPTION 'Embudo desconocido: %', p_embudo USING ERRCODE = '22023';
  END IF;
  IF COALESCE(btrim(p_waba_id), '') = ''
     OR COALESCE(btrim(p_wa_phone_number_id), '') = '' THEN
    RAISE EXCEPTION 'Faltan el waba_id o el phone_number_id que devolvió Meta'
      USING ERRCODE = '22023';
  END IF;
  IF COALESCE(btrim(p_token), '') = '' THEN
    RAISE EXCEPTION 'Sin token no hay línea: el intercambio del código no devolvió nada'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_linea
    FROM crm.lineas l
   WHERE l.inmobiliaria_id = p_inmobiliaria_id
     AND l.embudo = p_embudo
     AND l.activa
   FOR UPDATE;

  IF v_linea.id IS NULL THEN
    INSERT INTO crm.lineas (inmobiliaria_id, embudo, nombre)
    VALUES (p_inmobiliaria_id, p_embudo,
            COALESCE(NULLIF(btrim(p_nombre), ''),
                     (SELECT e.etiqueta FROM crm.embudos e WHERE e.codigo = p_embudo)))
    RETURNING * INTO v_linea;
  END IF;

  SELECT s.id INTO v_secreto
    FROM vault.secrets s
   WHERE s.name = 'crm_linea_' || v_linea.id::text;

  IF v_secreto IS NULL THEN
    v_secreto := vault.create_secret(
      p_token,
      'crm_linea_' || v_linea.id::text,
      'Token de la Cloud API de Meta de la línea ' || p_embudo ||
      '. Lo escribe crm.conectar_linea(); no se edita a mano.');
  ELSE
    PERFORM vault.update_secret(v_secreto, p_token);
  END IF;

  UPDATE crm.lineas
     SET waba_id                   = btrim(p_waba_id),
         wa_phone_number_id        = btrim(p_wa_phone_number_id),
         telefono_e164             = COALESCE(NULLIF(btrim(p_telefono_e164), ''), telefono_e164),
         modo                      = p_modo,
         token_secreto_id          = v_secreto,
         conectada_at              = now(),
         -- Token nuevo: el rechazo del anterior ya no dice nada.
         token_invalido_at         = NULL,
         token_error_codigo        = NULL,
         token_error               = NULL,
         -- Ciclo nuevo: nada de lo anterior vale.
         suscripcion_verificada_at = NULL,
         contactos_solicitados_at  = NULL,
         contactos_request_id      = NULL,
         historial_solicitado_at   = NULL,
         historial_request_id      = NULL,
         historial_progreso        = NULL,
         historial_completado_at   = NULL,
         historial_error_codigo    = NULL,
         historial_error           = NULL
   WHERE id = v_linea.id;

  RETURN v_linea.id;
END $conectar$;


-- ---------------------------------------------------------------------
-- registrar_estado_linea: dos eventos más. Misma firma que dejó el
-- request_id, así que CREATE OR REPLACE la sustituye sin crear otra.
--
--   token_invalido   Meta rechazó el token (código 190 y sus subcódigos)
--   token_valido     una llamada con esa credencial volvió a funcionar
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.registrar_estado_linea(
  p_wa_phone_number_id text,
  p_evento             text,
  p_progreso           int  DEFAULT NULL,
  p_error_codigo       int  DEFAULT NULL,
  p_error              text DEFAULT NULL,
  p_request_id         text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $estado$
DECLARE
  v_id         uuid;
  v_request_id text := NULLIF(btrim(p_request_id), '');
  -- El mensaje se limpia una vez, antes de que llegue a ninguna columna.
  v_error      text := crm.retirar_token(p_error);
BEGIN
  -- Antes de buscar la línea: un contrato mal entendido se avisa aunque
  -- el número no tenga línea.
  IF v_request_id IS NOT NULL
     AND p_evento NOT IN ('contactos_solicitados', 'historial_solicitado') THEN
    RAISE EXCEPTION 'El request_id solo acompaña a contactos_solicitados e historial_solicitado; los lotes de Meta no lo traen'
      USING ERRCODE = '22023';
  END IF;

  SELECT l.id INTO v_id
    FROM crm.lineas l
   WHERE l.wa_phone_number_id = p_wa_phone_number_id
     AND l.activa;

  IF v_id IS NULL THEN
    RETURN false;   -- número sin línea: no hay dónde anotarlo
  END IF;

  CASE p_evento
    WHEN 'suscripcion_verificada' THEN
      UPDATE crm.lineas SET suscripcion_verificada_at = now() WHERE id = v_id;

    WHEN 'suscripcion_perdida' THEN
      UPDATE crm.lineas SET suscripcion_verificada_at = NULL WHERE id = v_id;

    -- COALESCE: se pide una vez por ciclo —Meta no deja repetirlo sin
    -- desincorporar el número—. Un reintento de la plataforma no puede
    -- mover la fecha ni el recibo de la primera petición. Si la primera
    -- llegó sin recibo, el reintento lo completa.
    WHEN 'contactos_solicitados' THEN
      UPDATE crm.lineas
         SET contactos_solicitados_at = COALESCE(contactos_solicitados_at, now()),
             contactos_request_id     = COALESCE(contactos_request_id, v_request_id)
       WHERE id = v_id;

    WHEN 'historial_solicitado' THEN
      UPDATE crm.lineas
         SET historial_solicitado_at = COALESCE(historial_solicitado_at, now()),
             historial_request_id    = COALESCE(historial_request_id, v_request_id)
       WHERE id = v_id;

    WHEN 'historial_progreso' THEN
      IF p_progreso IS NULL THEN
        RAISE EXCEPTION 'historial_progreso necesita el progress del lote'
          USING ERRCODE = '22023';
      END IF;
      -- SOLO SUBE. Los lotes llegan desordenados, y un 30 que llega
      -- después de un 60 no significa que se haya deshecho nada.
      UPDATE crm.lineas
         SET historial_progreso = GREATEST(COALESCE(historial_progreso, 0),
                                           LEAST(GREATEST(p_progreso, 0), 100)),
             historial_completado_at = CASE
               WHEN p_progreso >= 100 THEN COALESCE(historial_completado_at, now())
               ELSE historial_completado_at
             END
       WHERE id = v_id;

    WHEN 'historial_error' THEN
      UPDATE crm.lineas
         SET historial_error_codigo = p_error_codigo,
             historial_error        = v_error
       WHERE id = v_id;

    -- La fecha es la del PRIMER rechazo: la pantalla dice cuánto lleva
    -- caída la línea, y cada envío fallido no puede reiniciar ese reloj.
    -- El código y el mensaje sí son los del último, que es el vigente.
    WHEN 'token_invalido' THEN
      UPDATE crm.lineas
         SET token_invalido_at  = COALESCE(token_invalido_at, now()),
             token_error_codigo = p_error_codigo,
             token_error        = v_error
       WHERE id = v_id;

    WHEN 'token_valido' THEN
      UPDATE crm.lineas
         SET token_invalido_at  = NULL,
             token_error_codigo = NULL,
             token_error        = NULL
       WHERE id = v_id;

    ELSE
      -- Ni un nombre de evento equivocado puede sacar un token en el error.
      RAISE EXCEPTION 'Evento de línea desconocido: %', crm.retirar_token(p_evento)
        USING ERRCODE = '22023';
  END CASE;

  RETURN true;
END $estado$;

COMMENT ON FUNCTION crm.registrar_estado_linea(text, text, int, int, text, text) IS
  'La plataforma anota lo que Meta le cuenta de una línea: suscripción verificada o perdida, sincronización pedida (con el request_id que devolvió Meta), progreso y errores del historial, token rechazado o de nuevo válido. Solo service_role.';

REVOKE ALL ON FUNCTION crm.registrar_estado_linea(text, text, int, int, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION crm.registrar_estado_linea(text, text, int, int, text, text)
  TO service_role;


-- ---------------------------------------------------------------------
-- El registro de intentos usa ahora la misma forma de token. Misma firma
-- y mismo comportamiento: solo cambia de dónde sale la expresión.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.registrar_intento_incorporacion(
  p_inmobiliaria_id    uuid,
  p_embudo             text,
  p_resultado          text,
  p_error_codigo       text        DEFAULT NULL,
  p_error              jsonb       DEFAULT NULL,
  p_wa_phone_number_id text        DEFAULT NULL,
  p_waba_id            text        DEFAULT NULL,
  p_ocurrido_at        timestamptz DEFAULT now())
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $intento$
DECLARE
  v_error  jsonb := crm.retirar_token(p_error::text)::jsonb;
  v_codigo text  := crm.retirar_token(p_error_codigo);
  v_id     uuid;
BEGIN
  INSERT INTO crm.intentos_incorporacion
    (inmobiliaria_id, embudo, resultado, error_codigo, error,
     wa_phone_number_id, waba_id, ocurrido_at, token_retirado)
  VALUES
    (p_inmobiliaria_id, p_embudo, p_resultado, v_codigo, v_error,
     p_wa_phone_number_id, p_waba_id,
     -- Un reloj adelantado no puede fechar un intento en el futuro.
     LEAST(COALESCE(p_ocurrido_at, now()), now()),
     -- Algo se retiró si lo guardado ya no es lo recibido.
     v_error IS DISTINCT FROM p_error OR v_codigo IS DISTINCT FROM p_error_codigo)
  RETURNING id INTO v_id;

  RETURN v_id;
END $intento$;
