-- =====================================================================
-- crm.normalizar_telefono — la función de la que depende toda la
-- identidad del contacto. Si alguien la "mejora" y rompe un caso, esta
-- prueba se pone roja antes de que el backfill fusione a dos personas.
--
-- Los casos no son inventados: salen de la forma real que tienen los
-- 608 teléfonos de citas + solicitudes_apertura en producción.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(18);

-- --- Nada que normalizar ---------------------------------------------
SELECT is(crm.normalizar_telefono(NULL), NULL, 'NULL entra, NULL sale');
SELECT is(crm.normalizar_telefono(''), NULL, 'Cadena vacía → NULL');
SELECT is(crm.normalizar_telefono('llamar al fijo'), NULL, 'Texto sin dígitos → NULL');

-- --- Móvil colombiano, las formas que aparecen de verdad --------------
SELECT is(crm.normalizar_telefono('3001234567'), '+573001234567',
  'Móvil pelado de 10 dígitos (492 de los 608 vienen así)');
SELECT is(crm.normalizar_telefono('+57 300 123 4567'), '+573001234567',
  'Con indicativo, espacios y signo más (103 vienen con símbolos)');
SELECT is(crm.normalizar_telefono('573001234567'), '+573001234567',
  'Con 57 delante, sin el más');
SELECT is(crm.normalizar_telefono('00573001234567'), '+573001234567',
  'Prefijo internacional 00 a la vieja usanza');
SELECT is(crm.normalizar_telefono('300 123 45 67'), '+573001234567',
  'Separado en grupos');
SELECT is(crm.normalizar_telefono('(300) 123-4567'), '+573001234567',
  'Con paréntesis y guion');

-- --- Fijos colombianos (numeración de 10 dígitos) ---------------------
SELECT is(crm.normalizar_telefono('6044445566'), '+576044445566',
  'Fijo de Medellín en el formato nuevo de 10 dígitos');
SELECT is(crm.normalizar_telefono('576044445566'), '+576044445566',
  'Fijo con el 57 delante');
SELECT is(crm.normalizar_telefono('4445566'), NULL,
  'Fijo de 7 dígitos sin indicativo → NULL: no se puede saber la ciudad');

-- --- El caso que parece internacional y no lo es ----------------------
SELECT is(crm.normalizar_telefono('+3001234567'), '+573001234567',
  'Un "+3001234567" es un móvil colombiano sin el 57, NO un número de Grecia');

-- --- Extranjeros legítimos (9 de los 13 que no encajaban) -------------
SELECT is(crm.normalizar_telefono('+51987654321'), '+51987654321',
  'Perú con el más: se respeta tal cual');
SELECT is(crm.normalizar_telefono('13055551234'), '+13055551234',
  'EE.UU. sin el más: 11 dígitos ya no caben en la numeración local');

-- --- Ambigüedad: se prefiere NULL antes que adivinar ------------------
SELECT is(crm.normalizar_telefono('32001234567'), NULL,
  'Once dígitos que empiezan en 3: casi seguro un dedazo, no Bélgica → NULL');
SELECT is(crm.normalizar_telefono('8012345678'), NULL,
  'Diez dígitos que no son ni móvil ni fijo colombiano, sin marca → NULL');

-- --- Idempotencia -----------------------------------------------------
-- Importante para el backfill: normalizar algo ya normalizado no lo
-- cambia. Si no, re-procesar una fuente produciría llaves distintas.
SELECT is(
  crm.normalizar_telefono(crm.normalizar_telefono('3001234567')),
  crm.normalizar_telefono('3001234567'),
  'Normalizar dos veces da lo mismo que normalizar una'
);

SELECT * FROM finish();
ROLLBACK;
