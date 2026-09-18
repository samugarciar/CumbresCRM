-- =====================================================================
-- Consentimiento para escribir primero.
--
-- LA DECISIÓN, Y VA FIRMADA (Samuel, 17 sep 2026)
-- Que alguien nos escriba por WhatsApp se toma como consentimiento para
-- volver a escribirle. Es una INTERPRETACIÓN, no un hecho, y por eso
-- queda escrita aquí con fecha y con nombre en vez de colarse dentro de
-- un UPDATE que nadie vuelve a leer.
--
-- POR QUÉ HACÍA FALTA DECIDIRLO
-- crm.contactos tiene `consentimiento` con DEFAULT false desde el primer
-- día. Medido en producción: 0 de 1.350 lo tienen. O sea que, en los
-- papeles, HOY NO SE LE PUEDE ESCRIBIR A NADIE — ni a las 670 personas
-- dormidas que son la bandeja de reactivación, que es el caso de negocio
-- más valioso que queda por construir.
--
-- Y el riesgo que de verdad importa no es la multa de Habeas Data: es la
-- calidad de una WABA recién migrada. Meta baja la calificación con los
-- bloqueos y los reportes de los destinatarios, y una WABA castigada
-- deja sin canal a toda la inmobiliaria.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Lo que faltaba: poder decir que NO
--
-- `public.captacion_prospectos` —del otro repo— ya tiene `opt_out`.
-- `crm.contactos` no lo tenía, y esa asimetría solo se nota el día de la
-- primera queja. Añadirlo ahora cuesta una columna; añadirlo después
-- cuesta la queja.
--
-- No es lo contrario de `consentimiento`: es más fuerte. Consentimiento
-- se deduce; el opt-out lo dice la persona, y gana siempre.
-- ---------------------------------------------------------------------
ALTER TABLE crm.contactos
  ADD COLUMN opt_out boolean NOT NULL DEFAULT false,
  ADD COLUMN opt_out_at timestamptz,
  ADD COLUMN opt_out_motivo text;

COMMENT ON COLUMN crm.contactos.opt_out IS
  'La persona pidió que no le escribamos. Gana sobre cualquier consentimiento y filtra TODO envío de marketing.';

-- El público de marketing es pequeño comparado con la tabla, y se
-- consulta entero cada vez que se arma un lote.
CREATE INDEX contactos_marketing
  ON crm.contactos (inmobiliaria_id)
  WHERE deleted_at IS NULL AND consentimiento AND NOT opt_out;

-- ---------------------------------------------------------------------
-- El backfill, con la fecha REAL de cada quien
--
-- No se pone `now()` a todos: la fecha del consentimiento es la del
-- primer mensaje que esa persona nos mandó, que es el hecho en que se
-- apoya la interpretación. Poner la fecha de hoy haría que el registro
-- dijera que 1.043 personas consintieron el mismo segundo, que es
-- justamente lo que no se podría defender si alguien lo preguntara.
--
-- Idempotente: solo toca a quien no lo tenga ya.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.backfill_consentimiento()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $bf$
DECLARE
  v_n integer;
BEGIN
  WITH primero AS (
    SELECT a.contacto_id, MIN(a.ocurrido_at) AS cuando
      FROM crm.actividades a
     WHERE a.tipo = 'mensaje_entrante' AND a.contacto_id IS NOT NULL
     GROUP BY a.contacto_id
  ), tocados AS (
    UPDATE crm.contactos c
       SET consentimiento       = true,
           consentimiento_at    = p.cuando,
           consentimiento_canal = 'whatsapp',
           updated_at           = now()
      FROM primero p
     WHERE c.id = p.contacto_id
       AND NOT c.consentimiento
       AND c.deleted_at IS NULL
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_n FROM tocados;
  RETURN v_n;
END $bf$;

COMMENT ON FUNCTION crm.backfill_consentimiento() IS
  'Marca como consentido a quien nos escribió, con la fecha de SU primer mensaje. Interpretación decidida por Samuel el 17 sep 2026.';

SELECT crm.backfill_consentimiento();

-- ---------------------------------------------------------------------
-- Y de aquí en adelante, solo
--
-- El backfill de arriba corre UNA vez, al aplicar la migración. Sin lo
-- que sigue, ningún lead nuevo quedaría jamás como consentido y la
-- bandeja de reactivación se habría congelado en los 1.043 de hoy,
-- envejeciendo sola. Es el mismo error que ya costó una corrección con
-- el sembrado de plantillas: un INSERT suelto en una migración solo
-- cubre lo que existe en ese segundo.
--
-- Va en un trigger porque el consentimiento nace del mismo hecho que la
-- actividad —la persona nos escribió— y separarlos es abrir la puerta a
-- que un día uno ocurra sin el otro.
--
-- Barato a propósito: el WHEN descarta todo lo que no sea un mensaje
-- entrante antes de llamar a nada, y lo que queda es un UPDATE por clave
-- primaria sobre una fila. Esto corre en el camino de CADA mensaje.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.consentir_al_escribirnos()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $cae$
BEGIN
  BEGIN
    UPDATE crm.contactos
       SET consentimiento       = true,
           consentimiento_at    = NEW.ocurrido_at,
           consentimiento_canal = 'whatsapp'
     WHERE id = NEW.contacto_id
       AND NOT consentimiento;
  EXCEPTION WHEN OTHERS THEN
    NULL;   -- jamás puede tumbar la llegada de un mensaje de un cliente
  END;
  RETURN NULL;
END $cae$;

CREATE TRIGGER crm_consentir_al_escribirnos
  AFTER INSERT ON crm.actividades
  FOR EACH ROW
  WHEN (NEW.tipo = 'mensaje_entrante' AND NEW.contacto_id IS NOT NULL)
  EXECUTE FUNCTION crm.consentir_al_escribirnos();

-- ---------------------------------------------------------------------
-- La única puerta por la que sale un lote de marketing
--
-- Existe para que ningún sitio de la aplicación pueda armar una lista a
-- mano y olvidarse del opt_out. Si un día hay que añadir otra condición
-- —una lista negra, un país, un límite de frecuencia— se añade aquí y
-- vale para todos los caminos a la vez.
--
-- Ordena por silencio descendente: al que lleva más tiempo callado se le
-- escribe primero, que es lo contrario de lo que sale por defecto y lo
-- que de verdad mueve inventario parado. Mismo criterio que la rotación
-- de inmuebles.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.publico_marketing(
  p_dias_silencio int DEFAULT 14,
  p_limite        int DEFAULT 100)
RETURNS TABLE (
  contacto_id     uuid,
  nombre          text,
  telefono_e164   text,
  ultima_actividad_at timestamptz,
  dias_callado    int
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $pm$
  SELECT c.id, c.nombre, c.telefono_e164, c.ultima_actividad_at,
         EXTRACT(day FROM now() - c.ultima_actividad_at)::int
    FROM crm.contactos c
   WHERE c.deleted_at IS NULL
     AND c.consentimiento
     AND NOT c.opt_out
     AND c.telefono_e164 IS NOT NULL
     AND c.ultima_actividad_at < now() - make_interval(days => p_dias_silencio)
   ORDER BY c.ultima_actividad_at ASC
   LIMIT p_limite;
$pm$;

COMMENT ON FUNCTION crm.publico_marketing(int, int) IS
  'La ÚNICA forma de armar un lote de marketing. Filtra opt_out y exige consentimiento, para que ningún camino de la app pueda saltárselo.';

GRANT EXECUTE ON FUNCTION crm.publico_marketing(int, int) TO authenticated;

-- ---------------------------------------------------------------------
-- Pedir que no le escribamos más
--
-- Deja rastro, como todo lo que cambia el trato con una persona. Y no
-- borra el consentimiento: quedan los dos, porque "consintió y luego
-- pidió salir" y "nunca consintió" no son lo mismo si alguien pregunta.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.marcar_opt_out(
  p_contacto_id uuid,
  p_motivo      text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $oo$
DECLARE
  v_inmobiliaria uuid;
BEGIN
  SELECT c.inmobiliaria_id INTO v_inmobiliaria
    FROM crm.contactos c WHERE c.id = p_contacto_id AND c.deleted_at IS NULL;
  IF v_inmobiliaria IS NULL THEN RETURN false; END IF;

  UPDATE crm.contactos
     SET opt_out = true, opt_out_at = now(), opt_out_motivo = p_motivo
   WHERE id = p_contacto_id AND NOT opt_out;

  INSERT INTO crm.actividades
    (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, creado_por)
  VALUES (v_inmobiliaria, 'sistema', 'humano', p_contacto_id,
          'Pidió que no le escribamos más.' ||
            COALESCE(' Motivo: ' || p_motivo, ''),
          auth.uid());
  RETURN true;
END $oo$;

GRANT EXECUTE ON FUNCTION crm.marcar_opt_out(uuid, text) TO authenticated;
