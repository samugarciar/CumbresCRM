-- =====================================================================
-- La analítica comercial (20261113100001).
--
-- Lo que se mide: que cada número signifique lo que dice la migración
-- (atendida, por una persona, mediana de respuesta, avanzó, dónde se
-- mueren, reclasificadas), que los periodos se armen en hora de Bogotá,
-- y que nada se cuele de otra inmobiliaria. Las fechas se arman contra
-- now() dentro de la última semana, así la prueba no depende de la hora
-- a la que corra.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(22);

SET LOCAL TimeZone = 'UTC';

DELETE FROM crm.contactos;
DELETE FROM public.citas;

-- --- Tres personas de Alfa y una de Beta -----------------------------------
INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164) VALUES
  ('a6100001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'La atiende el bot',     '+573006100001'),
  ('a6100002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'La atiende una persona', '+573006100002'),
  ('a6100003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Nadie le contesta',      '+573006100003'),
  ('b6100004-0000-0000-0000-000000000004', '22222222-2222-2222-2222-222222222222', 'De Beta',                '+573006100004');

INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, creado_por, metadata)
VALUES
  -- 1: escribe y el bot contesta a los 10 minutos.
  ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano', 'a6100001-0000-0000-0000-000000000001',
   'Hola', now() - interval '3 hours', NULL, '{"origen_tabla":"t61","origen_id":"1"}'),
  ('11111111-1111-1111-1111-111111111111', 'mensaje_saliente', 'agente_ia', 'a6100001-0000-0000-0000-000000000001',
   'Hola, soy el asistente', now() - interval '2 hours 50 minutes', NULL, '{"origen_tabla":"t61","origen_id":"2"}'),
  -- 2: escribe y una persona contesta a los 30 minutos.
  ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano', 'a6100002-0000-0000-0000-000000000002',
   'Buenas', now() - interval '2 hours', NULL, '{"origen_tabla":"t61","origen_id":"3"}'),
  ('11111111-1111-1111-1111-111111111111', 'mensaje_saliente', 'humano', 'a6100002-0000-0000-0000-000000000002',
   'Con gusto', now() - interval '1 hour 30 minutes', 'cccccccc-cccc-cccc-cccc-cccccccccccc', '{"origen_tabla":"t61","origen_id":"4"}'),
  -- 3: escribe y nadie contesta.
  ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano', 'a6100003-0000-0000-0000-000000000003',
   '¿Hay alguien?', now() - interval '1 hour', NULL, '{"origen_tabla":"t61","origen_id":"5"}'),
  -- Beta: no debe verse desde Alfa.
  ('22222222-2222-2222-2222-222222222222', 'mensaje_entrante', 'humano', 'b6100004-0000-0000-0000-000000000004',
   'Hola Beta', now() - interval '1 hour', NULL, '{"origen_tabla":"t61","origen_id":"6"}');

-- Dentro de la transacción now() no se mueve: lo creado «ahora» quedaría
-- en el borde del periodo, que es abierto por arriba. Se fecha atrás.
UPDATE crm.oportunidades SET created_at = now() - interval '4 hours'
 WHERE contacto_id IN ('a6100001-0000-0000-0000-000000000001',
                       'a6100002-0000-0000-0000-000000000002',
                       'a6100003-0000-0000-0000-000000000003');

-- La 1 avanza de Nuevo a Calificado de la mano del asesor.
INSERT INTO crm.transiciones
  (inmobiliaria_id, oportunidad_id, etapa_desde, etapa_hasta, origen, usuario_id, ocurrido_at)
SELECT o.inmobiliaria_id, o.id, 'nuevo', 'calificado', 'humano',
       'cccccccc-cccc-cccc-cccc-cccccccccccc', now() - interval '1 hour'
  FROM crm.oportunidades o
 WHERE o.contacto_id = 'a6100001-0000-0000-0000-000000000001' AND o.embudo = 'comercial';

-- La 3 se muere por no responder; la 2 se reclasifica (no es una muerte).
UPDATE crm.oportunidades
   SET estado = 'perdida', motivo_perdida = 'no_responde', cerrada_at = now() - interval '10 minutes'
 WHERE contacto_id = 'a6100003-0000-0000-0000-000000000003' AND embudo = 'comercial';
UPDATE crm.oportunidades
   SET estado = 'perdida', motivo_perdida = 'es_captacion', cerrada_at = now() - interval '10 minutes'
 WHERE contacto_id = 'a6100002-0000-0000-0000-000000000002' AND embudo = 'comercial';

-- Una visita agendada ahora, para hoy, de alguien que no está en el CRM.
INSERT INTO public.citas
  (id, inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono)
VALUES
  ('cc061001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'a3333333-3333-3333-3333-333333333333', 'a1111111-1111-1111-1111-111111111111',
   crm.hoy(), '23:00', '23:30', 'Visita de prueba', '+573006199999');
UPDATE public.citas SET created_at = now() - interval '2 hours'
 WHERE id = 'cc061001-0000-0000-0000-000000000001';

-- --- Desde la sesión de la admin de Alfa ------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT throws_ok($$SELECT crm.analitica('ayer', 'comercial')$$, '22023', NULL,
  'Un periodo desconocido se rechaza');
SELECT throws_ok($$SELECT crm.analitica('7d', 'inventado')$$, '22023', NULL,
  'Un embudo desconocido se rechaza');

CREATE TEMP TABLE r ON COMMIT DROP AS SELECT crm.analitica('7d', 'comercial') AS j;

SELECT is((SELECT (j->'kpis'->'actual'->>'conversaciones')::int FROM r), 3,
  'Tres conversaciones: la de Beta no se cuela');
SELECT is((SELECT (j->'kpis'->'actual'->>'atendidas')::int FROM r), 2,
  'Atendidas: la del bot y la de la persona');
SELECT is((SELECT (j->'kpis'->'actual'->>'atendidas_humano')::int FROM r), 1,
  'Por una persona: solo una');
SELECT is((SELECT (j->'kpis'->'actual'->>'mediana_respuesta_min')::numeric FROM r), 20.0,
  'La mediana de primera respuesta es 20 min (10 y 30)');
SELECT is((SELECT (j->'kpis'->'actual'->>'mediana_respuesta_humana_min')::numeric FROM r), 30.0,
  'La de una persona, 30 min');
SELECT is((SELECT (j->'kpis'->'actual'->>'leads_nuevos')::int FROM r), 3,
  'Tres leads nuevos en el embudo comercial de Alfa');
SELECT ok((SELECT (j->'kpis'->'actual'->>'avanzaron')::int FROM r) >= 1,
  'La que pasó de Nuevo a Calificado cuenta como avance');
SELECT is((SELECT (j->'kpis'->'actual'->>'perdidas')::int FROM r), 1,
  'Una muerte: la reclasificación no cuenta como perdida');
SELECT is((SELECT j->'perdidas_por_motivo'->0->>'motivo' FROM r), 'no_responde',
  'Se murió por no responder');
SELECT is((SELECT j->'reclasificadas'->0->>'motivo' FROM r), 'es_captacion',
  'La reclasificada va aparte');
SELECT is((SELECT (j->'kpis'->'actual'->>'citas_agendadas')::int FROM r), 1,
  'Una cita agendada en la semana');
SELECT is((SELECT (j->'visitas'->>'pendientes')::int FROM r), 1,
  'Y es para hoy: está pendiente');

SELECT is((SELECT (e->>'alcanzaron')::int
             FROM r, jsonb_array_elements(j->'embudo') e WHERE e->>'codigo' = 'nuevo'), 3,
  'El embudo arranca con los tres leads del periodo');
SELECT ok((SELECT (e->>'alcanzaron')::int
             FROM r, jsonb_array_elements(j->'embudo') e WHERE e->>'codigo' = 'contactado') >= 1,
  'Saltarse Contactado no le quita a nadie haber llegado más lejos');

SELECT is((SELECT (a->>'mensajes')::int
             FROM r, jsonb_array_elements(j->'asesores') a
            WHERE a->>'usuario_id' = 'cccccccc-cccc-cccc-cccc-cccccccccccc'), 1,
  'El asesor aparece con su mensaje');

SELECT is((SELECT jsonb_array_length(j->'serie') FROM r), 7,
  'La semana trae siete días');

SELECT is((SELECT jsonb_array_length(crm.analitica('hoy', 'comercial')->'serie')),
          extract(hour FROM now() AT TIME ZONE 'America/Bogota')::int + 1,
  'Hoy trae una barra por hora, desde la medianoche de Bogotá hasta la hora actual');

SELECT is((SELECT crm.analitica('mes', 'comercial')->'periodo'->>'desde'),
          to_char(date_trunc('month', crm.hoy()::timestamp) - interval '1 month', 'YYYY-MM-DD"T"HH24:MI'),
  'El último mes empieza el día 1 del mes anterior, a medianoche en Bogotá');

SELECT is((SELECT (crm.analitica('7d', 'captacion')->'kpis'->'actual'->>'citas_agendadas')::int), 0,
  'Las citas son del embudo comercial: en captación no cuentan');

-- --- Y desde Beta, nada de Alfa --------------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}';
SELECT is((SELECT (crm.analitica('7d', 'comercial')->'kpis'->'actual'->>'conversaciones')::int), 1,
  'Beta solo ve su conversación');

SELECT * FROM finish();
ROLLBACK;
