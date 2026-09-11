-- =====================================================================
-- La elección de nombre entre fuentes.
--
-- Una persona llega por WhatsApp con el apodo que ella misma se puso
-- ("MG❤️") y más tarde, al agendar una visita, el agente le pregunta el
-- nombre y escribe "María González". El CRM debe quedarse con el segundo.
--
-- La regla es tosca a propósito —cuenta palabras con letras— porque
-- cualquier cosa más lista es imposible de explicar cuando alguien
-- pregunta por qué el CRM eligió un nombre y no el otro.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(11);

-- --- La medida de calidad ---------------------------------------------
SELECT is(crm.calidad_nombre('María González'), 2, 'Dos palabras con letras → 2');
SELECT is(crm.calidad_nombre('MG❤️'), 1, 'Un apodo con letras y un emoji → 1');
SELECT is(crm.calidad_nombre('☺️'), 0, 'Solo emoji → 0: no hay nada que leer ahí');
SELECT is(crm.calidad_nombre('.'), 0, 'Un punto tampoco es un nombre');
SELECT is(crm.calidad_nombre(NULL), 0, 'NULL → 0');

-- --- La elección ------------------------------------------------------
SELECT is(crm.mejor_nombre('MG❤️', 'María González'), 'María González',
  'El nombre que la persona dio al agendar gana al apodo de WhatsApp');

SELECT is(crm.mejor_nombre('María González', 'MG❤️'), 'María González',
  'Y no se pierde cuando después llega el apodo: la calidad manda, no el orden');

SELECT is(crm.mejor_nombre('Juan', 'Juan Restrepo'), 'Juan Restrepo',
  'Un nombre completo gana a uno de una sola palabra');

SELECT is(crm.mejor_nombre('☺️', 'Juli'), 'Juli',
  'Cualquier cosa con letras gana al emoji suelto');

SELECT is(crm.mejor_nombre('Ana Gómez', 'Sara Pérez'), 'Ana Gómez',
  'En empate gana el que ya estaba: la ficha no debe cambiar de nombre sola');

SELECT is(crm.mejor_nombre('Ana Gómez', NULL), 'Ana Gómez',
  'Un candidato vacío nunca borra lo que ya había');

SELECT * FROM finish();
ROLLBACK;
