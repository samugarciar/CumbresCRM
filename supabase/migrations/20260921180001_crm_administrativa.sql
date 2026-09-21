-- =====================================================================
-- El embudo administrativo, que no es un embudo.
--
-- LO QUE DIJO SAMUEL (21 sep 2026)
-- "Podríamos trabajarlo por persona y, más que un embudo lineal, podría
-- ser uno de ida y vuelta para atender diferentes estados que se
-- presentan."
--
-- Y tiene razón, porque describe algo distinto de lo que el modelo sabía
-- hacer. Comercial y captación son RECORRIDOS: se avanza y no se vuelve —
-- quien ya visitó no des-visita. Lo administrativo es un ESTADO que
-- oscila: al día → en mora → acuerdo de pago → al día, y vuelta a
-- empezar mientras dure el contrato.
--
-- Por eso la unidad es la PERSONA y no el asunto. Un inquilino tiene una
-- sola relación administrativa viva —su contrato— y lo que cambia es en
-- qué situación está. Modelarlo por asunto habría chocado con "una
-- abierta por embudo": dos reparaciones simultáneas no cabrían.
--
-- QUÉ HACÍA FALTA DE VERDAD, QUE ERA MENOS DE LO QUE PARECÍA
-- `crm.mover_etapa()` NUNCA impuso avanzar: acepta cualquier peldaño. El
-- "solo hacia adelante" vive en `recalcular_oportunidad()`, el avance
-- AUTOMÁTICO, y esa función ya quedó acotada a comercial en la migración
-- anterior. O sea que la ida y vuelta ya funcionaba; lo que faltaba era
-- decirlo en el modelo, para que la interfaz sepa que este tablero no se
-- dibuja como los otros dos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Un embudo declara de qué tipo es
--
-- No es decoración: cambia cómo se dibuja y cómo se mide. Un recorrido
-- tiene conversión —cuántos pasan del peldaño 3 al 4— y una máquina de
-- estados no; lo que se mide ahí es cuánto tiempo pasa la gente en cada
-- estado, que es otra pregunta.
-- ---------------------------------------------------------------------
ALTER TABLE crm.embudos
  ADD COLUMN lineal boolean NOT NULL DEFAULT true;

UPDATE crm.embudos SET lineal = false WHERE codigo = 'administrativa';

COMMENT ON COLUMN crm.embudos.lineal IS
  'true = recorrido que solo avanza (comercial, captación). false = estados entre los que se va y se vuelve (administrativa).';

-- ---------------------------------------------------------------------
-- 2. Los estados de la relación administrativa
--
-- Son situaciones, no escalones, y por eso el `orden` aquí solo dice en
-- qué posición se dibujan; no implica progreso.
--
-- `dias_pudricion` cambia de sentido con ellos y hay que leerlo así:
--   · `al_dia` NO se pudre (NULL). Estar bien no es una tarea pendiente,
--     y marcarlo en ámbar a los pocos días llenaría el tablero de alertas
--     falsas — el error que este proyecto ya cometió dos veces.
--   · `en_mora` se pudre en 3: cada día que pasa vale dinero.
--   · los demás son gestiones con plazo razonable.
-- ---------------------------------------------------------------------
INSERT INTO crm.etapas (codigo, orden, etiqueta, dias_pudricion, automatica, embudo) VALUES
  ('al_dia',          1, 'Al día',           NULL, false, 'administrativa'),
  ('en_mora',         2, 'En mora',          3,    false, 'administrativa'),
  ('acuerdo_de_pago', 3, 'Acuerdo de pago',  7,    false, 'administrativa'),
  ('mantenimiento',   4, 'Mantenimiento',    5,    false, 'administrativa'),
  ('en_renovacion',   5, 'En renovación',    10,   false, 'administrativa'),
  ('en_terminacion',  6, 'En terminación',   7,    false, 'administrativa');

-- ---------------------------------------------------------------------
-- 3. Mover de etapa, dentro del embudo que toca
--
-- El fallo que se arregla: la comprobación era `EXISTS (... WHERE
-- e.codigo = p_etapa)` — CUALQUIER etapa de CUALQUIER embudo. Mover una
-- oportunidad comercial a 'en_mora' pasaba el control y reventaba después
-- contra la foránea compuesta, con un error de base de datos en vez de
-- una frase que alguien pueda entender.
--
-- No se impone avanzar, y es deliberado: en administrativa volver atrás
-- es el caso normal, y en comercial el retroceso manual ya era legítimo
-- —lo que no retrocede es el avance automático—. Quien mueve una tarjeta
-- a mano sabe lo que hace; la máquina no.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.mover_etapa(
  p_oportunidad_id uuid,
  p_etapa          text,
  p_motivo         text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $mover$
DECLARE
  v_op crm.oportunidades%ROWTYPE;
BEGIN
  SELECT * INTO v_op FROM crm.oportunidades o WHERE o.id = p_oportunidad_id;
  IF v_op.id IS NULL THEN
    RAISE EXCEPTION 'No existe esa oportunidad, o no es tuya';
  END IF;
  IF v_op.estado <> 'abierta' THEN
    RAISE EXCEPTION 'La oportunidad ya está cerrada como %', v_op.estado;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM crm.etapas e
     WHERE e.codigo = p_etapa AND e.embudo = v_op.embudo
  ) THEN
    RAISE EXCEPTION 'La etapa % no pertenece al embudo %', p_etapa, v_op.embudo;
  END IF;

  IF p_etapa = v_op.etapa THEN
    RETURN;   -- soltar la tarjeta en su propia columna no es un movimiento
  END IF;

  UPDATE crm.oportunidades
     SET etapa = p_etapa, etapa_at = now(), updated_at = now()
   WHERE id = p_oportunidad_id;

  INSERT INTO crm.transiciones
    (inmobiliaria_id, oportunidad_id, etapa_desde, etapa_hasta,
     estado_hasta, origen, motivo, usuario_id)
  VALUES (v_op.inmobiliaria_id, p_oportunidad_id, v_op.etapa, p_etapa,
          'abierta', 'humano', p_motivo, (SELECT auth.uid()));
END $mover$;

GRANT EXECUTE ON FUNCTION crm.mover_etapa(uuid, text, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 4. Cuánto lleva cada quien en el estado en el que está
--
-- La pregunta que sustituye a "conversión" cuando el embudo no avanza.
-- En comercial importa cuántos pasan de un peldaño al siguiente; en
-- administrativa importa cuánto tiempo lleva alguien en mora, porque eso
-- es lo que cuesta dinero.
--
-- Sale de `crm.transiciones`, que ya guarda cada movimiento con su fecha:
-- no hace falta ninguna tabla nueva.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.tiempo_en_estado(p_embudo text DEFAULT 'administrativa')
RETURNS TABLE (
  etapa        text,
  etiqueta     text,
  cuantos      int,
  dias_mediana numeric,
  dias_maximo  int
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $tee$
  SELECT o.etapa,
         e.etiqueta,
         count(*)::int,
         round(percentile_cont(0.5) WITHIN GROUP (
           ORDER BY EXTRACT(epoch FROM now() - o.etapa_at) / 86400)::numeric, 1),
         max(EXTRACT(day FROM now() - o.etapa_at))::int
    FROM crm.oportunidades o
    JOIN crm.etapas e ON e.codigo = o.etapa AND e.embudo = o.embudo
   WHERE o.estado = 'abierta' AND o.embudo = p_embudo
   GROUP BY o.etapa, e.etiqueta, e.orden
   ORDER BY e.orden;
$tee$;

COMMENT ON FUNCTION crm.tiempo_en_estado(text) IS
  'Cuánta gente hay en cada estado y cuánto lleva ahí. Es la pregunta que sustituye a la conversión cuando el embudo no avanza.';

GRANT EXECUTE ON FUNCTION crm.tiempo_en_estado(text) TO authenticated;
