-- =====================================================================
-- El silencio por escalamiento baja de 3 días a 6 horas.
--
-- LO QUE SE MIDIÓ EN PRODUCCIÓN EL 1/OCT
-- 35 contactos con el bot callado, 34 de ellos por escalamiento. De las 60
-- conversaciones más activas del agente, 23 tenían el bot mudo; de las 12
-- con actividad ese día, 7. Desde el 18 sep el apagado automático calla
-- entre 4 y 13 contactos al día, y con 3 días de vigencia el stock de
-- callados (~35) quedó del mismo orden que las conversaciones activas al
-- día. Visto desde Kommo parecía que el bot no contestaba a nadie.
--
-- POR QUÉ 6 HORAS Y NO OTRO NÚMERO
-- Es la ventana que ya se decidió el 26 sep para el relevo
-- (crm.ventana_relevo): cuánto se espera sin mensajes del equipo antes de
-- que el bot recupere el turno. Las dos reglas del bot pasan a medirse con
-- el mismo plazo, y queda una sola idea que recordar en vez de dos.
--
-- Y hay una razón de fondo: la caducidad de 3 días se diseñó confiando en
-- poder distinguir "nadie atendió", pero crm.bot_atendido_desde() solo ve
-- actos DENTRO del CRM, y las asesoras contestan en Kommo, que el CRM no
-- ve. Mientras esa señal siga siendo ciega —hasta la fase 5-B— tres días
-- de silencio son tres días apostando a una señal que no existe. Seis
-- horas acotan la apuesta sin renunciar a la regla de Samuel: quien
-- escala pidió una persona, y el bot se calla.
--
-- QUÉ NO CAMBIA
-- crm.sincronizar_escalamientos() se queda igual: seguir callando al bot
-- al escalar es la regla de negocio. Lo único que cambia es cuánto dura.
-- El silencio MANUAL sigue sin caducar nunca.
-- =====================================================================

-- ---------------------------------------------------------------------
-- La perilla, mismo patrón que crm.ventana_relevo() y
-- crm.ventana_escalamiento(): el plazo se cambia aquí y en ningún otro
-- sitio.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.ventana_silencio_escalamiento()
RETURNS interval
LANGUAGE sql IMMUTABLE SET search_path = ''
AS $vse$ SELECT interval '6 hours'; $vse$;

COMMENT ON FUNCTION crm.ventana_silencio_escalamiento() IS
  'Cuánto dura el silencio del bot tras un escalamiento si nadie del equipo atiende. 6 h, decidido el 1 oct 2026 para igualarlo a crm.ventana_relevo(). Es LA perilla: cambiarla aquí cambia la regla y el texto del historial.';

GRANT EXECUTE ON FUNCTION crm.ventana_silencio_escalamiento() TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- La ventana nueva NO es retroactiva, y esto es una decisión, no un detalle
--
-- Al aplicar esto hay 36 contactos con el bot callado, 27 de ellos con más
-- de 6 h. Si la ventana los alcanzara, el bot volvería a hablarles a los
-- cinco minutos, de golpe, en conversaciones donde puede haber una asesora
-- respondiendo por Kommo ahora mismo —que es justo lo que el CRM todavía no
-- ve—. Decisión de Samuel el 1/oct: **esos se quedan callados, los atiende
-- una persona.** La ventana solo alcanza a los que se callen desde aquí.
--
-- Se marca con una columna y no con una fecha de corte dentro de la función
-- porque el UPDATE corre EN EL MOMENTO de aplicar: captura exactamente a
-- quien esté callado entonces, sin que importe cuánto tarde en aplicarse ni
-- que entren más apagones por el camino. Una fecha literal habría dejado
-- fuera —o dentro— a los de ese hueco, en silencio.
--
-- Y sobre todo: siguen saliendo en «Mi día» como 'bot_callado', porque
-- conservan motivo 'escalamiento' y nadie los ha atendido. Era la condición
-- para que esto no sea abandonarlos: que estén callados Y a la vista.
-- ---------------------------------------------------------------------
ALTER TABLE crm.contactos
  ADD COLUMN bot_caduca boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN crm.contactos.bot_caduca IS
  'Si este silencio caduca solo al vencer crm.ventana_silencio_escalamiento(). false = lo atiende una persona y el bot no vuelve por su cuenta; se usó el 1/oct/2026 para los 36 silencios que ya existían cuando la ventana bajó de 3 días a 6 h.';

UPDATE crm.contactos
   SET bot_caduca = false
 WHERE NOT bot_activo
   AND deleted_at IS NULL;

-- ---------------------------------------------------------------------
-- crm.reactivar_bots pierde el argumento
--
-- No es cosmético. Con `p_dias` el plazo vivía en el COMANDO DEL CRON, no
-- en el código, y esa separación ya costó cuatro días de caducidad muerta
-- (20260921120001: la firma era smallint y el cron pasaba un integer).
-- Sin argumentos la firma no se puede desencontrar con lo agendado, que es
-- exactamente lo que se decidió para crm.reactivar_relevos().
--
-- El DROP y el reagendado van en la misma migración a propósito: dejar el
-- cron apuntando a una firma que ya no existe es el fallo que esta función
-- ya tuvo una vez.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS crm.reactivar_bots(int);

CREATE OR REPLACE FUNCTION crm.reactivar_bots()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $re$
DECLARE
  v_n       integer;
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
  RETURN v_n;
END $re$;

COMMENT ON FUNCTION crm.reactivar_bots() IS
  'Devuelve la voz al bot en los leads que escalaron hace más de crm.ventana_silencio_escalamiento() sin que nadie los atendiera. El silencio manual NUNCA caduca.';

-- Decide sobre el bot, así que es del servidor de la plataforma y de nadie
-- más: el esquema crm regala EXECUTE a authenticated en toda función nueva.
-- Misma línea que 20260926170001_crm_cerrar_funciones_de_sistema.sql.
REVOKE ALL ON FUNCTION crm.reactivar_bots() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION crm.reactivar_bots() TO service_role;

-- ---------------------------------------------------------------------
-- Encender el bot a mano devuelve la caducidad
--
-- Sin esto, el marcado de arriba sería una trampa para dentro de un mes:
-- una asesora atiende a uno de esos 27, enciende el bot desde la ficha, y
-- el contacto se queda con bot_caduca = false para siempre. El día que ese
-- mismo lead vuelva a escalar, su silencio no caducaría nunca y nadie
-- sabría por qué.
--
-- La regla queda: bot_caduca = false vale para EL silencio que hay ahora,
-- no para la persona. Quien enciende el bot cierra ese capítulo.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.cambiar_bot(
  p_contacto_id uuid,
  p_activo      boolean)
RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $cambiar$
DECLARE
  v_inmobiliaria uuid;
  v_antes boolean;
BEGIN
  SELECT c.inmobiliaria_id, c.bot_activo INTO v_inmobiliaria, v_antes
    FROM crm.contactos c
   WHERE c.id = p_contacto_id AND c.deleted_at IS NULL;

  -- Sin fila visible: o no existe, o la RLS no la deja ver. Las dos
  -- respuestas son la misma a propósito.
  IF v_inmobiliaria IS NULL THEN RETURN false; END IF;

  -- Pulsar dos veces no escribe dos veces ni ensucia el historial.
  IF v_antes = p_activo THEN RETURN true; END IF;

  UPDATE crm.contactos
     SET bot_activo       = p_activo,
         bot_motivo       = CASE WHEN p_activo THEN NULL ELSE 'manual' END,
         -- Al encender, el próximo silencio vuelve a caducar como cualquiera.
         bot_caduca       = CASE WHEN p_activo THEN true ELSE bot_caduca END,
         bot_cambiado_at  = now(),
         bot_cambiado_por = auth.uid()
   WHERE id = p_contacto_id;

  INSERT INTO crm.actividades
    (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, creado_por)
  VALUES (
    v_inmobiliaria, 'sistema', 'humano', p_contacto_id,
    CASE WHEN p_activo
      THEN 'El bot vuelve a responderle a esta persona.'
      ELSE 'El bot deja de responderle: un asesor atiende esta conversación.'
    END,
    auth.uid());

  RETURN true;
END $cambiar$;

-- ---------------------------------------------------------------------
-- Cada 5 minutos, no una vez al día
--
-- Con 3 días de plazo, una pasada diaria a las 8 bastaba. Con 6 horas, un
-- cron diario haría que el bot volviera hasta 24 h tarde: el plazo lo
-- fijaría el cron y no la regla. Cada 5 min es lo que ya hace
-- crm_reactivar_relevos, que mide la misma ventana.
--
-- En el minuto 2 y no en el 0: crm_reactivar_relevos corre en `*/5` y los
-- crones de este proyecto no comparten minuto desde el bucle de las nueve
-- (20260918100001).
-- ---------------------------------------------------------------------
DO $agenda$
BEGIN
  PERFORM cron.schedule(
    'crm_reactivar_bots', '2-59/5 * * * *',
    $trabajo$SELECT crm.reactivar_bots();$trabajo$);
EXCEPTION WHEN OTHERS THEN
  -- Si esto se tragara un error de verdad, el cron quedaría apuntando a
  -- `crm.reactivar_bots(3)`, que ya no existe. Lo caza la prueba 19, que
  -- ejecuta el comando EXACTO de cada agendado del CRM.
  RAISE NOTICE 'pg_cron no disponible: %', SQLERRM;
END $agenda$;
