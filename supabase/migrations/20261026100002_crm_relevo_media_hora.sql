-- =====================================================================
-- Relevo de 30 minutos, separado del escalamiento (26 oct 2026)
--
-- LO QUE DECIDIÓ SAMUEL
-- Cuando alguien del equipo le escribe al cliente, el bot se calla para
-- no hablarle encima al asesor, pero VUELVE SOLO si el asesor no escribe
-- en 30 minutos (antes, 6 horas; Samuel lo bajó de 1 hora a 30 minutos
-- la mañana del 26 oct). La ventana del escalamiento —cuánto espera el bot
-- callado a que llegue una persona cuando el cliente la pidió— sigue en
-- 6 horas, y el filtro de frescura de registrar_relevo también: son
-- perillas distintas (20261001150001).
--
-- LO QUE CAMBIA
--  1. crm.ventana_relevo() pasa a 30 minutos. Es la perilla: cambiarla mueve
--     la regla, el aviso del historial y la hora que enseña la ficha.
--  2. crm.reactivar_relevos escribe el aviso con la cifra de la perilla
--     y en buen español: «pasó 1 hora», «pasaron 2 horas», «pasaron 30
--     minutos» (crm.duracion_legible).
--  3. crm.registrar_relevo:
--     · no abre un relevo que nace vencido: un eco que llega con más de
--       una ventana de retraso no calla al bot para devolverle la voz en
--       la siguiente pasada del cron;
--     · si el bot estaba callado por un ESCALAMIENTO que caduca, lo pasa a
--       relevo desde el mensaje del asesor. Quien pidió una persona ya la
--       tuvo: si el asesor no vuelve a escribir en 30 minutos, el bot vuelve.
--       Antes se quedaba callado para siempre (reactivar_bots no despierta
--       a un escalado atendido);
--     · un silencio MANUAL no se toca: «yo me encargo» no caduca.
--  4. crm.bot_vuelve_at también responde para un escalamiento sin atender
--     que caduca: bot_cambiado_at + ventana_silencio_escalamiento().
--  5. crm_reactivar_relevos corre cada minuto: con una ventana de 30 minutos,
--     5 minutos de retraso ya se notan frente a la hora que dice la ficha.
--
-- Mismas firmas y mismos permisos (CREATE OR REPLACE los conserva).
-- Idempotente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. La perilla
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.ventana_relevo()
RETURNS interval
LANGUAGE sql IMMUTABLE SET search_path = ''
-- Perilla del relevo: cámbiala aquí.
AS $vr$ SELECT interval '30 minutes'; $vr$;

COMMENT ON FUNCTION crm.ventana_relevo() IS
  'Perilla del relevo: cámbiala aquí. Cuánto tiempo sin mensajes del equipo hace falta para que el bot '
  'recupere el turno tras un relevo. 30 min desde el 26 oct 2026 (antes 6 h). Mueve la regla '
  '(reactivar_relevos), el aviso del historial y la hora de la ficha (bot_vuelve_at). NO mueve la '
  'ventana del escalamiento (crm.ventana_silencio_escalamiento) ni el filtro de frescura (crm.frescura_relevo).';

-- ---------------------------------------------------------------------
-- 2. Una duración en palabras, para los avisos del historial
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.duracion_legible(p_duracion interval)
RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = ''
AS $dl$
  SELECT CASE
           WHEN m >= 60 AND m % 60 = 0 THEN
             (m / 60)::text || CASE WHEN m = 60 THEN ' hora' ELSE ' horas' END
           ELSE
             m::text || CASE WHEN m = 1 THEN ' minuto' ELSE ' minutos' END
         END
    FROM (SELECT round(extract(epoch FROM p_duracion) / 60)::bigint AS m) x;
$dl$;

COMMENT ON FUNCTION crm.duracion_legible(interval) IS
  '«1 hora», «6 horas», «30 minutos»: la cifra de una perilla para los avisos del historial.';

REVOKE ALL ON FUNCTION crm.duracion_legible(interval) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION crm.duracion_legible(interval) TO service_role;

-- ---------------------------------------------------------------------
-- 3. La vuelta, con el aviso sacado de la perilla
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.reactivar_relevos()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $rr$
DECLARE
  v_n        integer;
  v_duracion text := crm.duracion_legible(crm.ventana_relevo());
  v_aviso    text;
BEGIN
  v_aviso := 'El bot vuelve a responderle: '
          || CASE WHEN v_duracion LIKE '1 %' THEN 'pasó ' ELSE 'pasaron ' END
          || v_duracion
          || ' sin que nadie del equipo le escribiera.';

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
    SELECT v.inmobiliaria_id, 'sistema', 'sistema', v.contacto_id, v_aviso
      FROM vencidos v
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_n FROM vencidos;
  RETURN v_n;
END $rr$;

COMMENT ON FUNCTION crm.reactivar_relevos() IS
  'Devuelve la voz al bot donde el relevo venció (crm.ventana_relevo() sin mensajes del equipo). '
  'No toca silencios manuales ni escalamientos sin atender.';

-- ---------------------------------------------------------------------
-- 4. El relevo: no nace vencido, y atiende al escalado
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
     AND c.telefono_e164 = crm.normalizar_telefono(p_telefono)
     AND c.deleted_at IS NULL
   FOR UPDATE;

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
END $relevo$;

COMMENT ON FUNCTION crm.registrar_relevo(text, text, timestamptz) IS
  'Calla al bot cuando alguien del equipo le escribe al cliente (eco o envío del CRM). La ventana es '
  'crm.ventana_relevo(); un eco más viejo que la ventana no abre relevo. Un escalamiento que caduca pasa '
  'a relevo; un silencio manual no se toca.';

-- ---------------------------------------------------------------------
-- 5. Cuándo vuelve el bot: relevo y escalamiento sin atender
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.bot_vuelve_at(p_contacto_id uuid)
RETURNS timestamptz
LANGUAGE sql STABLE SET search_path = ''
AS $vuelve$
  SELECT CASE
           WHEN c.bot_motivo = 'relevo'
             THEN c.bot_cambiado_at + crm.ventana_relevo()
           -- Lo despierta crm.reactivar_bots si nadie del equipo llegó.
           WHEN c.bot_motivo = 'escalamiento'
            AND c.bot_caduca
            AND NOT crm.bot_atendido_desde(c.id, c.bot_cambiado_at)
             THEN c.bot_cambiado_at + crm.ventana_silencio_escalamiento()
         END
    FROM crm.contactos c
   WHERE c.id = p_contacto_id
     AND c.deleted_at IS NULL
     AND NOT c.bot_activo;
$vuelve$;

COMMENT ON FUNCTION crm.bot_vuelve_at(uuid) IS
  'Cuándo recupera el bot la voz si nadie hace nada: relevo (bot_cambiado_at + ventana_relevo) o '
  'escalamiento sin atender que caduca (bot_cambiado_at + ventana_silencio_escalamiento). NULL si es '
  'manual, si el escalamiento ya se atendió o si el bot está activo.';

-- ---------------------------------------------------------------------
-- 6. La vuelta corre cada minuto
-- ---------------------------------------------------------------------
DO $agenda$
BEGIN
  PERFORM cron.schedule(
    'crm_reactivar_relevos', '* * * * *',
    $trabajo$SELECT crm.reactivar_relevos();$trabajo$);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron no disponible; habrá que agendar crm.reactivar_relevos() a mano: %', SQLERRM;
END $agenda$;
