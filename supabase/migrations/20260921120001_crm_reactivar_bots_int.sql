-- =====================================================================
-- crm.reactivar_bots pasa de smallint a int, porque su cron nunca pudo
-- llamarla.
--
-- EL FALLO
-- Se declaró `p_dias smallint` y el cron quedó registrado como
-- `SELECT crm.reactivar_bots(3)`. El literal `3` es INTEGER, y Postgres
-- no convierte integer → smallint al resolver a qué función llamar. Las
-- cuatro corridas desde el 18 sep fallaron con:
--
--     ERROR: function crm.reactivar_bots(integer) does not exist
--
-- Cuatro días con la caducidad del silencio muerta y 4 contactos ya
-- vencidos sin que el bot volviera. Nadie se enteró porque un cron que
-- falla no avisa a nadie: queda en cron.job_run_details y ahí se queda.
--
-- POR QUÉ LA PRUEBA NO LO VIO, QUE ES LO QUE DE VERDAD HAY QUE APRENDER
-- La prueba llamaba `crm.reactivar_bots(3::smallint)`. O sea, estaba
-- escrita contra la IMPLEMENTACIÓN y no contra la LLAMADA REAL. Probaba
-- que la función funciona; nunca probó que alguien pudiera invocarla.
--
-- El arreglo de la prueba importa más que el de la función: ahora se
-- ejecuta el comando EXACTO que el cron tiene registrado, leído de
-- cron.job. Si mañana alguien cambia una firma, la prueba se cae.
--
-- Se elige `int` y no arreglar el cron con un cast porque int es la
-- convención de la casa: crm.cerrar_fantasmas(p_dias int DEFAULT 30) ya
-- lo era, y es lo que cualquiera escribe al llamarla a mano.
-- =====================================================================

DROP FUNCTION IF EXISTS crm.reactivar_bots(smallint);

CREATE OR REPLACE FUNCTION crm.reactivar_bots(p_dias int DEFAULT 3)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $re$
DECLARE
  v_n integer;
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
       AND c.bot_cambiado_at < now() - make_interval(days => p_dias)
       AND NOT crm.bot_atendido_desde(c.id, c.bot_cambiado_at)
    RETURNING c.id AS contacto_id, c.inmobiliaria_id
  ), rastro AS (
    INSERT INTO crm.actividades
      (inmobiliaria_id, tipo, origen, contacto_id, cuerpo)
    SELECT v.inmobiliaria_id, 'sistema', 'sistema', v.contacto_id,
           'El bot vuelve a responderle: pasaron ' || p_dias ||
           ' días desde que pidió hablar con una persona y nadie del equipo llegó.'
      FROM vencidos v
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_n FROM vencidos;
  RETURN v_n;
END $re$;

COMMENT ON FUNCTION crm.reactivar_bots(int) IS
  'Devuelve la voz al bot en los leads que escalaron hace más de N días sin que nadie los atendiera. El silencio manual NUNCA caduca.';

-- El comando del cron no cambia —siempre fue `crm.reactivar_bots(3)`—
-- pero se reagenda para dejar constancia de que a partir de aquí resuelve.
DO $agenda$
BEGIN
  PERFORM cron.schedule(
    'crm_reactivar_bots', '0 8 * * *',
    $trabajo$SELECT crm.reactivar_bots(3);$trabajo$);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron no disponible: %', SQLERRM;
END $agenda$;
