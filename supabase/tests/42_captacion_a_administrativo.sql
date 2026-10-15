-- =====================================================================
-- PRUEBA 42: Reclasificación de Propietario a Línea Administrativa
-- y eliminación de etapa 'por_aprobar' en captación.
-- =====================================================================
BEGIN;
SELECT plan(12);

-- 1 · Verificar que 'por_aprobar' ya no existe en crm.etapas
SELECT is(
  (SELECT count(*)::int FROM crm.etapas WHERE embudo = 'captacion' AND codigo = 'por_aprobar'),
  0,
  'La etapa por_aprobar no existe en el embudo de captación'
);

SELECT is(
  (SELECT count(*)::int FROM crm.etapas WHERE embudo = 'captacion'),
  5,
  'El embudo de captación tiene exactamente 5 etapas'
);

SELECT is(
  (SELECT array_agg(codigo ORDER BY orden) FROM crm.etapas WHERE embudo = 'captacion'),
  ARRAY['prospecto', 'propietario_contactado', 'visita_captacion', 'inmueble_verificado', 'negociando']::text[],
  'Las etapas de captación están ordenadas correlativamente 1 a 5'
);

-- 2 · Fixture: Propietario con captación abierta en negociación
CREATE TEMP TABLE c_prop AS
  SELECT id FROM crm.contactos
   WHERE inmobiliaria_id = '11111111-1111-1111-1111-111111111111'
   LIMIT 1;

-- Asegurar tipo propietario y abrir captación
UPDATE crm.contactos SET tipo = 'propietario' WHERE id = (SELECT id FROM c_prop);

-- Cerrar cualquier oportunidad previa abierta
UPDATE crm.oportunidades SET estado = 'perdida', motivo_perdida = 'otro', cerrada_at = now()
 WHERE contacto_id = (SELECT id FROM c_prop) AND estado = 'abierta';

INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado)
VALUES ('11111111-1111-1111-1111-111111111111', (SELECT id FROM c_prop), 'captacion', 'negociando', 'abierta');

-- Conectar como asesor autenticado
GRANT SELECT ON c_prop TO authenticated;

SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'role', 'authenticated'
)::text, true);

SET LOCAL ROLE authenticated;

-- 3 · Iniciar relación comercial: crm.convertir_a_administrativo(id, true)
SELECT ok(
  crm.convertir_a_administrativo((SELECT id FROM c_prop), true) IS NOT NULL,
  'crm.convertir_a_administrativo ejecuta con éxito para captación abierta'
);

SELECT is(
  (SELECT estado FROM crm.oportunidades WHERE contacto_id = (SELECT id FROM c_prop) AND embudo = 'captacion'),
  'ganada',
  'La oportunidad de captación queda cerrada como ganada al iniciar relación comercial'
);

SELECT is(
  (SELECT etapa FROM crm.oportunidades WHERE contacto_id = (SELECT id FROM c_prop) AND embudo = 'administrativa' AND estado = 'abierta'),
  'al_dia',
  'Se abre el caso administrativo para el propietario en la primera etapa (al_dia)'
);

SELECT is(
  (SELECT tipo FROM crm.contactos WHERE id = (SELECT id FROM c_prop)),
  'propietario',
  'El tipo de contacto se conserva como propietario'
);

SELECT is(
  (SELECT count(*)::int FROM crm.actividades WHERE contacto_id = (SELECT id FROM c_prop)
    AND metadata ? 'captacion_cerrada_id' AND (metadata->>'es_ganada')::boolean = true),
  1,
  'Se registra actividad de sistema documentando la vinculación comercial'
);

-- 4 · Idempotencia: llamar nuevamente no duplica casos administrativos
SELECT ok(
  crm.convertir_a_administrativo((SELECT id FROM c_prop), true) IS NOT NULL,
  'Segunda llamada es idempotente y no lanza error de unicidad'
);

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades WHERE contacto_id = (SELECT id FROM c_prop) AND embudo = 'administrativa' AND estado = 'abierta'),
  1,
  'Solo existe un caso administrativo abierto tras llamada repetida'
);

-- 5 · Reclasificación no ganada (p_es_ganada = false)
RESET ROLE;
CREATE TEMP TABLE c_reclasif AS
  SELECT gen_random_uuid() AS id;

INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo)
VALUES ((SELECT id FROM c_reclasif), '11111111-1111-1111-1111-111111111111', 'Contacto Reclasif', '+573199887766', 'propietario');

INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado)
VALUES ('11111111-1111-1111-1111-111111111111', (SELECT id FROM c_reclasif), 'captacion', 'prospecto', 'abierta');

GRANT SELECT ON c_reclasif TO authenticated;

SET LOCAL ROLE authenticated;

SELECT is(
  (
    SELECT estado FROM crm.oportunidades
     WHERE id = (
       SELECT id FROM crm.oportunidades WHERE contacto_id = (SELECT id FROM c_reclasif) AND embudo = 'captacion'
     )
  ),
  'abierta',
  'Caso inicial abierto en captacion'
);

-- Ejecutar reclasificación con es_ganada = false
SELECT crm.convertir_a_administrativo((SELECT id FROM c_reclasif), false);

SELECT is(
  (SELECT motivo_perdida FROM crm.oportunidades WHERE contacto_id = (SELECT id FROM c_reclasif) AND embudo = 'captacion'),
  'es_administrativa',
  'Reclasificación con es_ganada=false registra motivo es_administrativa'
);

SELECT finish();
ROLLBACK;
