-- =====================================================================
-- El request_id de cada solicitud de sincronización.
--
-- DECISIÓN 28, segunda mitad (1 oct 2026)
-- `POST /{phone_number_id}/smb_app_data` se llama dos veces por ciclo
-- —contactos (`smb_app_state_sync`) e historial (`history`)— y cada una
-- devuelve `{ "messaging_product": "whatsapp", "request_id": "…" }`.
-- Hasta hoy el CRM solo guardaba CUÁNDO se pidió. Ahora guarda también
-- el recibo de Meta.
--
-- LO QUE EL request_id SÍ DA, Y LO QUE NO
-- Verificado contra la documentación de Meta el 1 oct: los lotes de
-- `history` y de `smb_app_state_sync` NO traen el request_id. Llevan
-- `phase`, `chunk_order` y `progress`, y nada que los ate a la solicitud.
-- Así que el request_id NO sirve para reconocer un lote repetido: eso lo
-- sigue haciendo el progreso que solo sube. Lo que sí da:
--   · la constancia de que Meta ACEPTÓ la solicitud, que no es lo mismo
--     que la plataforma diga que la mandó;
--   · lo que pide el soporte de Meta cuando una sincronización no llega;
--   · que un reintento de la plataforma sea inocuo: el primero gana, como
--     ya pasaba con la fecha.
-- Por eso la función RECHAZA un request_id en cualquier otro evento: si
-- la plataforma cree que los lotes lo traen, mejor que lo sepa en el
-- primer lote que en producción.
--
-- LA FIRMA
-- El parámetro nuevo va AL FINAL y con DEFAULT, así que toda llamada que
-- hoy funciona sigue funcionando igual. Pero añadir un parámetro con
-- CREATE OR REPLACE no reemplaza: crea una SEGUNDA función con el mismo
-- nombre, y la llamada de cinco argumentos quedaría ambigua. Por eso se
-- borra la vieja en la misma transacción. Una función nueva nace,
-- además, ejecutable por todos: el REVOKE se repite abajo.
-- =====================================================================

ALTER TABLE crm.lineas
  ADD COLUMN contactos_request_id text,
  ADD COLUMN historial_request_id text;

COMMENT ON COLUMN crm.lineas.contactos_request_id IS
  'request_id que devolvió Meta al pedir smb_app_state_sync en este ciclo. El primero gana. Los lotes NO lo traen: es el recibo de la solicitud, no la llave de los lotes.';
COMMENT ON COLUMN crm.lineas.historial_request_id IS
  'request_id que devolvió Meta al pedir history en este ciclo. El primero gana. Los lotes NO lo traen: es el recibo de la solicitud, no la llave de los lotes.';


-- ---------------------------------------------------------------------
-- Reconectar empieza un ciclo nuevo, y el recibo del ciclo anterior deja
-- de valer como todo lo demás. Misma firma; lo único nuevo son las dos
-- líneas que vacían los request_id.
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
-- registrar_estado_linea, con el recibo
-- ---------------------------------------------------------------------
DROP FUNCTION crm.registrar_estado_linea(text, text, int, int, text);

CREATE FUNCTION crm.registrar_estado_linea(
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
             historial_error        = p_error
       WHERE id = v_id;

    ELSE
      RAISE EXCEPTION 'Evento de línea desconocido: %', p_evento
        USING ERRCODE = '22023';
  END CASE;

  RETURN true;
END $estado$;

COMMENT ON FUNCTION crm.registrar_estado_linea(text, text, int, int, text, text) IS
  'La plataforma anota lo que Meta le cuenta de una línea: suscripción verificada o perdida, sincronización pedida (con el request_id que devolvió Meta), progreso y errores del historial. Solo service_role.';

REVOKE ALL ON FUNCTION crm.registrar_estado_linea(text, text, int, int, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION crm.registrar_estado_linea(text, text, int, int, text, text)
  TO service_role;
