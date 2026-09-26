-- =====================================================================
-- La coexistencia: cada línea sabe cómo está conectada a Meta, guarda su
-- token donde nadie lo pueda leer, y el bot se calla cuando una persona
-- del equipo escribe.
--
-- LO QUE PIDIÓ SAMUEL (26 sep 2026)
-- Las tres líneas —comercial, administrativa y captación— hablando con la
-- Cloud API de Meta sin intermediarios, SIN que el equipo pierda la app
-- de WhatsApp Business del celular. Meta solo permite eso (la
-- "coexistencia") a través del registro integrado, y solo a un Tech
-- Provider: Cumbres se registra como Tech Provider de sí misma.
--
-- Consecuencia que da forma a todo lo de abajo: ya no hay UN token en
-- una variable de entorno. Cada cuenta que se incorpora entrega el suyo,
-- así que el token pasa a ser un dato POR LÍNEA.
--
-- VERIFICADO CONTRA LA DOCUMENTACIÓN DE META (26 sep 2026)
-- "Onboard WhatsApp Business app users":
--   · Contactos e historial se piden con POST /{phone_number_id}/smb_app_data
--     (sync_type 'smb_app_state_sync' y 'history'). UNA sola vez: repetir
--     exige desincorporar el número y pasar otra vez por el registro.
--   · Hay 24 horas desde el registro para pedirlos. Pasado eso, lo mismo.
--   · El historial llega en lotes con `progress`; 100 = terminado. Si el
--     negocio tiene el historial apagado en su app, llega el error 2593109.
--   · `smb_message_echoes` sale SOLO por lo que se manda desde la app o un
--     dispositivo acompañante, nunca por lo que se manda por la API. Un
--     eco es, sin ambigüedad, una persona del equipo escribiendo.
--
-- ⚠️ LA TRAMPA DE ESTE ESQUEMA, Y POR QUÉ HAY REVOKE MÁS ABAJO
-- `crm_esquema` hizo ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE ON
-- FUNCTIONS TO authenticated. O sea: TODA función nueva en `crm` nace
-- ejecutable por cualquier usuario logueado, desde el navegador, por
-- PostgREST. Sin el REVOKE, cualquier asesor podría pedirle a
-- crm.credencial_linea() el token de Meta de la inmobiliaria. Lo prueba
-- la 26: que un admin logueado reciba 42501.
--
-- LO QUE NO CAMBIA, A PROPÓSITO
--   · El silencio MANUAL no caduca nunca, y el del escalamiento vence a
--     los 3 días si nadie atendió. Son reglas aprobadas el 17 sep: el
--     relevo entra como un TERCER motivo con su propia regla, sin tocar
--     esas dos.
--   · crm.linea_por_numero() no se toca: corre en el camino de cada
--     mensaje entrante de la plataforma desplegada, y nada de lo que
--     necesita la coexistencia pasa por ahí.
-- =====================================================================


-- =====================================================================
-- 1 · Lo que la línea sabe de su conexión con Meta
-- =====================================================================
ALTER TABLE crm.lineas
  -- La cuenta de WhatsApp Business (WABA) a la que pertenece el número.
  -- Es a ella, no al número, a la que se suscribe la app.
  ADD COLUMN waba_id text,

  -- Coexistencia (app del celular + API) o solo API. Existe para no
  -- aplicarle a una línea las reglas de la otra: el historial, los ecos
  -- y el tope de 20 mensajes por segundo son solo de la coexistencia.
  ADD COLUMN modo text CHECK (modo IN ('coexistencia', 'cloud_api')),

  -- Dónde está el token en Vault. El token NO vive en esta tabla: aquí
  -- solo está la dirección, que sin permisos sobre Vault no sirve de nada.
  ADD COLUMN token_secreto_id uuid,

  -- Cuándo terminó el registro integrado. Arranca el reloj de 24 h.
  ADD COLUMN conectada_at timestamptz,

  -- Cuándo se comprobó, con el GET de subscribed_apps, que nuestra app
  -- está suscrita a la WABA. Es la puerta que falla en silencio: sin ella
  -- Meta recibe los mensajes y no manda ningún webhook, y todo parece
  -- bien configurado aunque no llegue nada. NULL en una línea conectada
  -- es una alarma, no un dato pendiente.
  ADD COLUMN suscripcion_verificada_at timestamptz,

  -- La sincronización de la coexistencia. Se pide una vez por ciclo.
  ADD COLUMN contactos_solicitados_at timestamptz,
  ADD COLUMN historial_solicitado_at  timestamptz,
  ADD COLUMN historial_progreso       smallint
    CHECK (historial_progreso BETWEEN 0 AND 100),
  ADD COLUMN historial_completado_at  timestamptz,
  ADD COLUMN historial_error_codigo   integer,
  ADD COLUMN historial_error          text,

  -- Una línea conectada tiene TODAS sus piezas. A medio conectar es peor
  -- que desconectada: parece que funciona.
  ADD CONSTRAINT lineas_conectada_completa CHECK (
    conectada_at IS NULL
    OR (waba_id IS NOT NULL
        AND modo IS NOT NULL
        AND token_secreto_id IS NOT NULL
        AND wa_phone_number_id IS NOT NULL));

COMMENT ON COLUMN crm.lineas.modo IS
  'coexistencia (app del celular + Cloud API) o cloud_api (solo API). Historial, ecos y el tope de 20 msg/s son solo de coexistencia.';
COMMENT ON COLUMN crm.lineas.token_secreto_id IS
  'Id del secreto en Vault con el token de Meta de esta línea. El token nunca está en esta tabla. Lo escribe crm.conectar_linea().';
COMMENT ON COLUMN crm.lineas.suscripcion_verificada_at IS
  'Cuándo se comprobó con GET /{waba_id}/subscribed_apps que la app está suscrita. Sin eso Meta no manda webhooks. NULL en una línea conectada = alarma.';
COMMENT ON COLUMN crm.lineas.historial_progreso IS
  'Último `progress` del webhook `history` (0-100). Solo sube: los lotes llegan desordenados.';


-- =====================================================================
-- 2 · Un token que sobrevive a su línea es una credencial viva que nadie
--     sabe que existe
--
-- Si se borra la línea —a mano, o en cascada al borrar la inmobiliaria—
-- su token se borra de Vault en la misma transacción. Si el borrado del
-- secreto fallara, falla todo: mejor una línea que no se deja borrar que
-- un token huérfano.
-- =====================================================================
CREATE OR REPLACE FUNCTION crm.borrar_secreto_linea()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $borrar$
BEGIN
  IF OLD.token_secreto_id IS NOT NULL THEN
    DELETE FROM vault.secrets WHERE id = OLD.token_secreto_id;
  END IF;
  RETURN OLD;
END $borrar$;

CREATE TRIGGER lineas_borrar_secreto
  AFTER DELETE ON crm.lineas
  FOR EACH ROW EXECUTE FUNCTION crm.borrar_secreto_linea();


-- =====================================================================
-- 3 · Conectar una línea: el contrato con el registro integrado
--
-- Lo llama el backend de la plataforma cuando termina el registro
-- integrado y ya cambió el código por el token. NUNCA el navegador: el
-- token no pasa por un cliente autenticado en ningún momento.
--
-- La plataforma responde de que quien lanzó el registro es admin de
-- `p_inmobiliaria_id`; esta función confía en service_role, que es lo
-- único que la puede llamar.
--
-- Actualiza la línea activa del embudo si ya existe —una por embudo, lo
-- garantiza un índice— y si no, la crea. Reconectar empieza un CICLO
-- NUEVO: Meta exige desincorporar y volver a registrar para repetir la
-- sincronización, así que lo sincronizado en el ciclo anterior deja de
-- valer.
--
-- El secreto se busca por NOMBRE (crm_linea_<id>) y no solo por la
-- columna: si alguien vaciara la columna a mano, crear otro chocaría con
-- el nombre único de Vault. Así hay siempre UN secreto por línea, y
-- reconectar reemplaza el valor en vez de dejar tokens viejos vivos.
-- =====================================================================
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
         historial_solicitado_at   = NULL,
         historial_progreso        = NULL,
         historial_completado_at   = NULL,
         historial_error_codigo    = NULL,
         historial_error           = NULL
   WHERE id = v_linea.id;

  RETURN v_linea.id;
END $conectar$;

COMMENT ON FUNCTION crm.conectar_linea(uuid, text, text, text, text, text, text, text) IS
  'Contrato con el registro integrado de Meta: guarda la conexión de la línea y su token (en Vault). Solo service_role. Reconectar empieza un ciclo nuevo.';


-- =====================================================================
-- 4 · El token, para quien manda
--
-- Por phone_number_id, la misma llave que crm.linea_por_numero(): es lo
-- que la plataforma tiene a mano tanto al contestar un mensaje entrante
-- como cuando el CRM le pide un envío.
--
-- Sin fila = la línea no pasó por el registro integrado. La plataforma
-- cae entonces a WHATSAPP_TOKEN, que queda solo para el número de prueba
-- de Meta y se retira cuando todas las líneas vivan aquí.
-- =====================================================================
CREATE OR REPLACE FUNCTION crm.credencial_linea(p_wa_phone_number_id text)
RETURNS TABLE (
  linea_id        uuid,
  inmobiliaria_id uuid,
  embudo          text,
  waba_id         text,
  modo            text,
  token           text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $credencial$
  SELECT l.id, l.inmobiliaria_id, l.embudo, l.waba_id, l.modo, s.decrypted_secret
    FROM crm.lineas l
    JOIN vault.decrypted_secrets s ON s.id = l.token_secreto_id
   WHERE l.wa_phone_number_id = p_wa_phone_number_id
     AND l.activa
   LIMIT 1;
$credencial$;

COMMENT ON FUNCTION crm.credencial_linea(text) IS
  'Contrato con el emisor de la plataforma: el token de Meta de una línea, descifrado. Solo service_role. Sin fila = la línea no pasó por el registro integrado.';


-- =====================================================================
-- 5 · Lo que Meta cuenta de una línea, anotado por la plataforma
--
-- Mismo patrón que crm.registrar_estado_envio(): la plataforma recibe de
-- Meta y anota aquí. Registra HECHOS y no los discute: si el plazo de
-- 24 h pasó, lo dirá crm.estado_sincronizacion(), no un rechazo que haría
-- perder la constancia de algo que sí ocurrió en Meta.
--
--   suscripcion_verificada  el GET de subscribed_apps lista nuestra app
--   suscripcion_perdida     y ya no la lista (para un chequeo periódico)
--   contactos_solicitados   se pidió smb_app_state_sync
--   historial_solicitado    se pidió history
--   historial_progreso      llegó un lote de `history` con su progress
--   historial_error         llegó un error, p. ej. 2593109
-- =====================================================================
CREATE OR REPLACE FUNCTION crm.registrar_estado_linea(
  p_wa_phone_number_id text,
  p_evento             text,
  p_progreso           int  DEFAULT NULL,
  p_error_codigo       int  DEFAULT NULL,
  p_error              text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $estado$
DECLARE
  v_id uuid;
BEGIN
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

    -- COALESCE: se pide una vez por ciclo. Un reintento de la plataforma
    -- no puede mover la fecha de la primera petición.
    WHEN 'contactos_solicitados' THEN
      UPDATE crm.lineas
         SET contactos_solicitados_at = COALESCE(contactos_solicitados_at, now())
       WHERE id = v_id;

    WHEN 'historial_solicitado' THEN
      UPDATE crm.lineas
         SET historial_solicitado_at = COALESCE(historial_solicitado_at, now())
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

COMMENT ON FUNCTION crm.registrar_estado_linea(text, text, int, int, text) IS
  'La plataforma anota lo que Meta le cuenta de una línea: suscripción verificada o perdida, sincronización pedida, progreso e errores del historial. Solo service_role.';


-- =====================================================================
-- 6 · Si la sincronización terminó, que lo diga la base
--
-- "Dejar registrado si la sincronización terminó, para no depender de
-- que alguien se acuerde de mirarlo." Es derivado y no una columna,
-- porque 'vencido' depende de la hora: una columna necesitaría un cron
-- que la fuera cambiando, y el día que el cron fallara diría 'pendiente'
-- de una línea que ya no tiene arreglo.
--
-- Se pide como columna virtual: select('*, estado_sincronizacion').
--
--   sin_conectar  la línea no pasó por el registro integrado
--   no_aplica     solo API: no hay app, así que no hay nada que traer
--   completo      contactos pedidos e historial al 100 %
--   rechazado     2593109: el negocio tiene el historial apagado en su
--                 app. No es un fallo nuestro, y reintentar no sirve
--   fallido       otro error de Meta
--   en_curso      pedidos los dos, llegando
--   vencido       pasaron 24 h sin pedir los dos: hay que desincorporar
--                 el número y repetir el registro entero
--   pendiente     conectada hace menos de 24 h, falta pedir
-- =====================================================================
CREATE OR REPLACE FUNCTION crm.estado_sincronizacion(l crm.lineas)
RETURNS text
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $sinc$
  SELECT CASE
    WHEN l.conectada_at IS NULL                      THEN 'sin_conectar'
    WHEN l.modo IS DISTINCT FROM 'coexistencia'      THEN 'no_aplica'
    WHEN l.historial_completado_at IS NOT NULL
     AND l.contactos_solicitados_at IS NOT NULL      THEN 'completo'
    WHEN l.historial_error_codigo = 2593109          THEN 'rechazado'
    WHEN l.historial_error_codigo IS NOT NULL
      OR l.historial_error IS NOT NULL               THEN 'fallido'
    WHEN l.historial_solicitado_at IS NOT NULL
     AND l.contactos_solicitados_at IS NOT NULL      THEN 'en_curso'
    -- 24 h es la regla de Meta, no una perilla nuestra.
    WHEN l.conectada_at < now() - interval '24 hours' THEN 'vencido'
    ELSE                                                  'pendiente'
  END;
$sinc$;

COMMENT ON FUNCTION crm.estado_sincronizacion(crm.lineas) IS
  'En qué punto está la sincronización de contactos e historial de la coexistencia. Derivado: ''vencido'' depende de la hora (24 h de Meta).';


-- =====================================================================
-- 7 · El relevo: cuando escribe una persona, el bot se calla
--
-- LA DECISIÓN DE SAMUEL (26 sep, opción C)
-- Cuando alguien del equipo escribe —desde el celular, desde WhatsApp Web
-- o desde el CRM— el bot se calla en esa conversación. Recupera el turno
-- por cualquiera de dos caminos:
--   · solo, cuando pasan 6 horas sin que nadie del equipo le escriba;
--   · a mano, cuando un asesor lo enciende (crm.cambiar_bot, que ya
--     existe y no cambia).
--
-- POR QUÉ UN MOTIVO NUEVO Y NO REUSAR 'manual'
-- 'manual' no caduca nunca: es alguien diciendo "yo me encargo". El
-- relevo sí caduca. Meterlo como manual dejaría al bot mudo para siempre
-- tras cualquier mensaje del equipo; meterlo como escalamiento lo haría
-- volver a los 3 días y no a las 6 horas.
--
-- LAS 6 HORAS SE CUENTAN DESDE EL ÚLTIMO MENSAJE HUMANO, no desde el
-- primero: mientras el asesor siga escribiendo, la ventana corre con él.
-- Por eso `bot_cambiado_at`, en el relevo, se mueve con cada mensaje.
-- =====================================================================
ALTER TABLE crm.contactos DROP CONSTRAINT contactos_bot_motivo_check;
-- Sin IF EXISTS, deliberadamente: si en alguna base este CHECK se llamara
-- distinto, la migración debe FALLAR aquí. Con IF EXISTS no borraría nada,
-- el CHECK viejo seguiría vivo, y todo relevo reventaría en silencio. En
-- la plataforma ya pasó exactamente eso con inmuebles_estado_check.
ALTER TABLE crm.contactos ADD CONSTRAINT contactos_bot_motivo_check
  CHECK (bot_motivo IN ('escalamiento', 'manual', 'relevo'));

-- La perilla. Mismo patrón que crm.ventana_escalamiento().
CREATE OR REPLACE FUNCTION crm.ventana_relevo()
RETURNS interval
LANGUAGE sql IMMUTABLE SET search_path = ''
AS $vr$ SELECT interval '6 hours'; $vr$;

COMMENT ON FUNCTION crm.ventana_relevo() IS
  'Cuánto tiempo sin mensajes del equipo hace falta para que el bot recupere el turno tras un relevo. 6 h, decidido el 26 sep. Es LA perilla: cambiarla aquí cambia la regla, el aviso del historial y la hora que enseña la ficha.';

GRANT EXECUTE ON FUNCTION crm.ventana_relevo() TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- Una persona del equipo escribió: el contrato con la plataforma
--
-- La plataforma lo llama por cada mensaje humano saliente: cada
-- smb_message_echoes, y cada envío que el CRM le pide. Siempre DESPUÉS de
-- guardar el mensaje, que es lo que crea el contacto si no existía.
--
-- Va por LÍNEA y no solo por teléfono. El estado del bot cuelga del
-- contacto, pero que alguien de administrativa le conteste a un inquilino
-- por su contrato no significa que alguien esté atendiendo su búsqueda
-- comercial. Solo cuenta lo que se escribe en una línea donde el bot
-- habla.
--
-- NO HACE NADA, y devuelve false, cuando:
--   · la línea no existe o el bot no atiende en ella;
--   · el mensaje tiene más de 6 horas. Al conectar un número, Meta
--     REPRODUCE el historial, con mensajes humanos de hace meses: sin esta
--     guarda, conectar la línea comercial callaría al bot en todas esas
--     conversaciones de golpe. Mismo cuidado que el "solo hacia adelante"
--     del escalamiento;
--   · el teléfono no es de ningún contacto. Falla hacia "el bot responde",
--     como bot_puede_responder;
--   · el bot ya está callado por otro motivo. El manual no caduca y el
--     escalamiento tiene su propia regla: el relevo no les pasa por
--     encima.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.registrar_relevo(
  p_wa_phone_number_id text,
  p_telefono           text,
  p_ocurrido_at        timestamptz DEFAULT now())
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $relevo$
DECLARE
  v_inmobiliaria uuid;
  v_bot_atiende  boolean;
  -- Un reloj adelantado no puede estirar el relevo hacia el futuro.
  v_momento      timestamptz := LEAST(COALESCE(p_ocurrido_at, now()), now());
  v_contacto     crm.contactos%ROWTYPE;
BEGIN
  SELECT l.inmobiliaria_id, e.bot_atiende INTO v_inmobiliaria, v_bot_atiende
    FROM crm.lineas l
    JOIN crm.embudos e ON e.codigo = l.embudo
   WHERE l.wa_phone_number_id = p_wa_phone_number_id
     AND l.activa;

  IF v_inmobiliaria IS NULL OR NOT v_bot_atiende THEN
    RETURN false;
  END IF;

  IF v_momento < now() - crm.ventana_relevo() THEN
    RETURN false;
  END IF;

  SELECT * INTO v_contacto
    FROM crm.contactos c
   WHERE c.inmobiliaria_id = v_inmobiliaria
     AND c.telefono_e164 = crm.normalizar_telefono(p_telefono)
     AND c.deleted_at IS NULL
   FOR UPDATE;

  IF v_contacto.id IS NULL THEN
    RETURN false;
  END IF;

  IF NOT v_contacto.bot_activo AND v_contacto.bot_motivo IS DISTINCT FROM 'relevo' THEN
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
  ELSE
    -- Ya estaba en relevo: la ventana corre con el último mensaje. Sin
    -- aviso nuevo; uno por mensaje enterraría el historial.
    UPDATE crm.contactos
       SET bot_cambiado_at = GREATEST(bot_cambiado_at, v_momento)
     WHERE id = v_contacto.id;
  END IF;

  RETURN true;
END $relevo$;

COMMENT ON FUNCTION crm.registrar_relevo(text, text, timestamptz) IS
  'Contrato con la plataforma: una persona del equipo escribió a este teléfono por esta línea. Calla al bot (motivo relevo) o corre la ventana. Solo líneas donde el bot habla, solo mensajes de menos de 6 h, nunca sobre un silencio manual o de escalamiento. Solo service_role.';

-- ---------------------------------------------------------------------
-- Devolverle la voz al bot cuando el equipo dejó de escribir
--
-- Deja rastro, como toda vuelta del bot: uno que habla otra vez sin que
-- conste por qué es lo que nadie consigue explicar tres semanas después.
-- La cifra del aviso sale de la perilla, no de un 6 escrito a mano.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.reactivar_relevos()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $reactivar$
DECLARE
  v_n     integer;
  v_horas integer := round(extract(epoch FROM crm.ventana_relevo()) / 3600);
BEGIN
  WITH vencidos AS (
    UPDATE crm.contactos c
       SET bot_activo       = true,
           bot_motivo       = NULL,
           bot_cambiado_at  = now(),
           bot_cambiado_por = NULL
     WHERE c.deleted_at IS NULL
       AND NOT c.bot_activo
       AND c.bot_motivo = 'relevo'
       AND c.bot_cambiado_at < now() - crm.ventana_relevo()
    RETURNING c.id AS contacto_id, c.inmobiliaria_id
  ), rastro AS (
    INSERT INTO crm.actividades
      (inmobiliaria_id, tipo, origen, contacto_id, cuerpo)
    SELECT v.inmobiliaria_id, 'sistema', 'sistema', v.contacto_id,
           'El bot vuelve a responderle: pasaron ' || v_horas ||
           ' horas sin que nadie del equipo le escribiera.'
      FROM vencidos v
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_n FROM vencidos;
  RETURN v_n;
END $reactivar$;

COMMENT ON FUNCTION crm.reactivar_relevos() IS
  'Devuelve la voz al bot donde el relevo venció (crm.ventana_relevo() sin mensajes del equipo). No toca silencios manuales ni de escalamiento.';

-- ---------------------------------------------------------------------
-- Para la ficha: cuándo vuelve el bot si nadie más escribe
--
-- La regla vive aquí y la pantalla solo pinta una hora, igual que
-- crm.ventana_whatsapp(). Si la ficha sumara 6 horas por su cuenta, el
-- día que cambie la perilla la ficha mentiría.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.bot_vuelve_at(p_contacto_id uuid)
RETURNS timestamptz
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $vuelve$
  SELECT c.bot_cambiado_at + crm.ventana_relevo()
    FROM crm.contactos c
   WHERE c.id = p_contacto_id
     AND c.deleted_at IS NULL
     AND NOT c.bot_activo
     AND c.bot_motivo = 'relevo';
$vuelve$;

COMMENT ON FUNCTION crm.bot_vuelve_at(uuid) IS
  'Cuándo recupera el bot la voz si nadie más del equipo escribe. Solo para el relevo; NULL en cualquier otro caso.';

-- ---------------------------------------------------------------------
-- Cada 5 minutos: la ventana se mide en horas, y 5 minutos de retraso en
-- que el bot vuelva no los nota nadie. Sin argumentos a propósito: la
-- firma no puede desencontrarse con lo agendado, que es lo que dejó
-- cuatro días muerta a crm.reactivar_bots.
-- ---------------------------------------------------------------------
DO $agenda$
BEGIN
  PERFORM cron.schedule(
    'crm_reactivar_relevos', '*/5 * * * *',
    $trabajo$SELECT crm.reactivar_relevos();$trabajo$);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron no disponible; habrá que agendar crm.reactivar_relevos() a mano: %', SQLERRM;
END $agenda$;


-- =====================================================================
-- 8 · Quién puede llamar qué
--
-- El REVOKE que justifica la advertencia del principio. Todo lo que toca
-- tokens o decide sobre el bot es del servidor de la plataforma
-- (service_role). crm.estado_sincronizacion() y crm.bot_vuelve_at() son
-- de pantalla y se quedan con el permiso por defecto: la RLS decide qué
-- filas ve cada quien.
-- =====================================================================
REVOKE ALL ON FUNCTION crm.conectar_linea(uuid, text, text, text, text, text, text, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.credencial_linea(text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.registrar_estado_linea(text, text, int, int, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.registrar_relevo(text, text, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.reactivar_relevos()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.borrar_secreto_linea()
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION crm.conectar_linea(uuid, text, text, text, text, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION crm.credencial_linea(text) TO service_role;
GRANT EXECUTE ON FUNCTION crm.registrar_estado_linea(text, text, int, int, text) TO service_role;
GRANT EXECUTE ON FUNCTION crm.registrar_relevo(text, text, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION crm.reactivar_relevos() TO service_role;
