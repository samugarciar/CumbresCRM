-- =====================================================================
-- Cerrar solas las oportunidades que se apagaron.
--
-- EL PROBLEMA, MEDIDO
-- De 982 contactos con conversación, 981 terminan con un mensaje NUESTRO
-- y 670 llevan más de catorce días en silencio. Sin nada que las cierre,
-- "Contactado" acumula para siempre tarjetas que no van a ninguna parte
-- y el tablero acaba pesando más de lo que informa.
--
-- ⚠️ EL RIESGO, DICHO CLARO
-- En crm.actividades hay CERO mensajes salientes escritos por una
-- persona: todos los puso el bot. Cuando un asesor contesta, lo hace
-- desde su teléfono por Kommo, y eso nunca toca esta base. Así que
-- "lleva 30 días sin responder" puede significar dos cosas muy
-- distintas:
--
--     a) el cliente se calló de verdad
--     b) la conversación se mudó a un canal que no vemos
--
-- Esta función NO puede distinguirlas, y por eso está construida para
-- deshacerse: cada cierre deja `cerrada_por` en NULL y una transición
-- con origen 'sistema', así que los automáticos se pueden encontrar y
-- revertir en bloque. Ver crm.reabrir_oportunidad().
--
-- Se podrán separar de verdad en la fase 5, cuando el canal de WhatsApp
-- sea nuestro y las respuestas humanas entren a esta base.
-- =====================================================================

CREATE OR REPLACE FUNCTION crm.cerrar_fantasmas(p_dias int DEFAULT 30)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $fantasmas$
DECLARE
  v_n integer := 0;
  v_op record;
BEGIN
  FOR v_op IN
    SELECT o.id, o.inmobiliaria_id, o.etapa, o.contacto_id
      FROM crm.oportunidades o
      JOIN crm.contactos c ON c.id = o.contacto_id
     WHERE o.estado = 'abierta'
       AND c.deleted_at IS NULL
       -- Silencio de verdad: ningún hecho de ningún tipo. Una nota, una
       -- visita o un movimiento de etapa cuentan como vida.
       AND COALESCE(c.ultima_actividad_at, o.created_at)
             < now() - make_interval(days => p_dias)
       -- NO se pregunta por `etapa_at`, y es deliberado: el backfill del
       -- 14 sep puso ese reloj en `now()` para las 1.275 oportunidades a
       -- la vez, así que durante un mes habría protegido justo a los 670
       -- fantasmas que esta función viene a cerrar. Un reloj que una
       -- migración puede reiniciar en masa no sirve para decidir nada.
       --
       -- La pregunta de verdad es si una PERSONA ha tocado esto, y eso lo
       -- sabe el historial. Las transiciones del backfill y del avance
       -- automático llevan origen 'sistema'/'backfill' y no cuentan.
       AND NOT EXISTS (
         SELECT 1 FROM crm.transiciones t
          WHERE t.oportunidad_id = o.id
            AND t.origen = 'humano'
            AND t.ocurrido_at > now() - make_interval(days => p_dias)
       )
       -- Si el último que habló fue el cliente, NO se cierra: eso no es
       -- un fantasma, es alguien esperando respuesta nuestra. Cerrarlo
       -- como "no responde" sería echarle a él la culpa de nuestro
       -- silencio.
       AND NOT EXISTS (
         SELECT 1 FROM crm.actividades a
          WHERE a.contacto_id = o.contacto_id
            AND a.tipo = 'mensaje_entrante'
            AND a.ocurrido_at > COALESCE((
              SELECT max(a2.ocurrido_at) FROM crm.actividades a2
               WHERE a2.contacto_id = o.contacto_id
                 AND a2.tipo = 'mensaje_saliente'
            ), '-infinity'::timestamptz)
       )
       -- Y nadie con una visita por delante es un fantasma.
       AND NOT EXISTS (
         SELECT 1 FROM crm.actividades a
           JOIN public.citas ci ON ci.id = a.cita_id
          WHERE a.contacto_id = o.contacto_id
            AND ci.estado = 'agendada'
            AND ci.fecha >= current_date
       )
  LOOP
    BEGIN
      UPDATE crm.oportunidades
         SET estado         = 'perdida',
             motivo_perdida = 'no_responde',
             cerrada_at     = now(),
             -- NULL a propósito: es la huella de que esto lo cerró una
             -- regla y no una persona. Misma convención que
             -- citas.completada_por en el cierre masivo del 14 sep.
             cerrada_por    = NULL,
             updated_at     = now()
       WHERE id = v_op.id;

      INSERT INTO crm.transiciones
        (inmobiliaria_id, oportunidad_id, etapa_desde, etapa_hasta,
         estado_hasta, origen, motivo)
      VALUES (v_op.inmobiliaria_id, v_op.id, v_op.etapa, NULL,
              'perdida', 'sistema',
              format('sin respuesta en %s días', p_dias));

      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      NULL;   -- una oportunidad rota no puede detener a las otras 669
    END;
  END LOOP;

  RETURN v_n;
END $fantasmas$;

COMMENT ON FUNCTION crm.cerrar_fantasmas(int) IS
  'Cierra como no_responde lo que lleva N días en silencio. Deja cerrada_por en NULL para poder distinguir —y deshacer— lo que cerró la máquina.';

-- ---------------------------------------------------------------------
-- Deshacer
--
-- Existe porque el cierre automático se construyó sabiendo que puede
-- equivocarse. Una función que cierra en masa sin una que reabra es una
-- función en la que no se puede confiar.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.reabrir_oportunidad(p_oportunidad_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $reabrir$
DECLARE
  v_op crm.oportunidades%ROWTYPE;
BEGIN
  SELECT * INTO v_op FROM crm.oportunidades o WHERE o.id = p_oportunidad_id;
  IF v_op.id IS NULL THEN
    RAISE EXCEPTION 'No existe esa oportunidad, o no es tuya';
  END IF;
  IF v_op.estado = 'abierta' THEN
    RETURN;   -- ya estaba abierta; reabrir de más no hace daño
  END IF;

  -- La regla de "una abierta por persona" sigue mandando: si mientras
  -- tanto nació otra, esta se queda cerrada y se dice por qué.
  IF EXISTS (
    SELECT 1 FROM crm.oportunidades o
     WHERE o.contacto_id = v_op.contacto_id AND o.estado = 'abierta'
  ) THEN
    RAISE EXCEPTION 'Esa persona ya tiene una oportunidad abierta. Usa esa.';
  END IF;

  UPDATE crm.oportunidades
     SET estado         = 'abierta',
         motivo_perdida = NULL,
         cerrada_at     = NULL,
         cerrada_por    = NULL,
         etapa_at       = now(),
         updated_at     = now()
   WHERE id = p_oportunidad_id;

  INSERT INTO crm.transiciones
    (inmobiliaria_id, oportunidad_id, etapa_desde, etapa_hasta,
     estado_hasta, origen, motivo, usuario_id)
  VALUES (v_op.inmobiliaria_id, p_oportunidad_id, NULL, v_op.etapa,
          'abierta', 'humano', 'reabierta', (SELECT auth.uid()));
END $reabrir$;

GRANT EXECUTE ON FUNCTION crm.reabrir_oportunidad(uuid) TO authenticated;
REVOKE ALL ON FUNCTION crm.cerrar_fantasmas(int) FROM public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Una vez al día, de madrugada.
--
-- No cada cinco minutos como el recálculo: esto CIERRA negocios, y algo
-- que cierra negocios no debe correr sesenta veces por hora. A las 4:00
-- hora de Colombia (09:00 UTC) no hay nadie mirando el tablero.
-- ---------------------------------------------------------------------
DO $cron$
BEGIN
  PERFORM cron.schedule(
    'crm_cerrar_fantasmas', '0 9 * * *',
    $trabajo$SELECT crm.cerrar_fantasmas(30);$trabajo$);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron no disponible; habrá que agendar crm.cerrar_fantasmas() a mano: %', SQLERRM;
END $cron$;
