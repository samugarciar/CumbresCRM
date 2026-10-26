-- =====================================================================
-- «Hoy» es el de Colombia (20261026100003).
--
-- La base corre en UTC: entre las 7 p. m. y la medianoche de Bogotá,
-- current_date ya es mañana. Mi día enseñaba como «de hoy» las visitas de
-- mañana. Esta prueba no depende de la hora a la que corra: arma las
-- fechas con crm.hoy() y comprueba que crm.hoy() es el día de Bogotá.
--
-- De paso: las tareas que ve un asesor y qué cuenta como atender un
-- escalado.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(11);

-- La sesión en UTC, como la base de producción.
SET LOCAL TimeZone = 'UTC';

-- --- Las dos funciones -----------------------------------------------------
SELECT is(crm.hoy(), ((now() AT TIME ZONE 'UTC') - interval '5 hours')::date,
  'crm.hoy() es el día de Bogotá (UTC-5, sin horario de verano) aunque la sesión esté en UTC');

SELECT is(crm.inicio_de_hoy(), (crm.hoy()::timestamp + interval '5 hours') AT TIME ZONE 'UTC',
  'crm.inicio_de_hoy() es la medianoche de Bogotá, las 5 a. m. en UTC');

SELECT ok(crm.inicio_de_hoy() <= now() AND now() < crm.inicio_de_hoy() + interval '1 day',
  'Y ahora cae dentro de ese día');

DELETE FROM crm.contactos;
DELETE FROM crm.tareas;
DELETE FROM public.citas;
DELETE FROM public.tareas;

-- --- Visitas de hoy y de mañana ---------------------------------------------
INSERT INTO public.citas
  (id, inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono)
VALUES
  ('cc005001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'a3333333-3333-3333-3333-333333333333', 'a1111111-1111-1111-1111-111111111111',
   crm.hoy(), '23:00', '23:30', 'Visita de hoy', '+573005000001'),
  ('cc005002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'a3333333-3333-3333-3333-333333333333', 'a1111111-1111-1111-1111-111111111111',
   crm.hoy() + 1, '10:00', '10:30', 'Visita de mañana', '+573005000002');

-- --- Tareas de tres dueños ---------------------------------------------------
INSERT INTO crm.tareas (id, inmobiliaria_id, titulo, vence_at, asignado_a)
VALUES
  ('77775001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'De la admin', crm.inicio_de_hoy() + interval '20 hours', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('77775002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'Del asesor', crm.inicio_de_hoy() + interval '20 hours', 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
  ('77775003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
   'De nadie', crm.inicio_de_hoy() + interval '20 hours', NULL),
  ('77775004-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111',
   'Vence mañana', crm.inicio_de_hoy() + interval '1 day' + interval '1 hour', NULL);

-- --- Un escalado sin nombre --------------------------------------------------
INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, ultima_actividad_at)
VALUES ('dd005001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        NULL, '+573005000003', now());

INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, ocurrido_at, metadata)
VALUES ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
        'dd005001-0000-0000-0000-000000000001', now() - interval '40 minutes',
        '{"origen_tabla":"t","origen_id":"p50"}');

UPDATE crm.oportunidades SET escalado_at = now() - interval '30 minutes'
 WHERE contacto_id = 'dd005001-0000-0000-0000-000000000001';

-- =====================================================================
-- Lo que ve el asesor
-- =====================================================================
SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT array_agg(titulo ORDER BY titulo)
     FROM crm.mi_dia(60, 'cccccccc-cccc-cccc-cccc-cccccccccccc') WHERE tipo = 'tarea_hoy'),
  ARRAY['De nadie', 'Del asesor'],
  'El asesor ve sus tareas y las que no tienen dueño; la de la admin no, y la de mañana tampoco'
);

SELECT is(
  (SELECT detalle FROM crm.mi_dia(60, 'cccccccc-cccc-cccc-cccc-cccccccccccc') WHERE tipo = 'escalado'),
  '+573005000003 escribió y sigue esperando',
  'Un escalado sin nombre dice el teléfono en vez de quedar vacío'
);

SELECT lives_ok(
  $$SELECT crm.marcar_leido('dd005001-0000-0000-0000-000000000001')$$,
  'El asesor abre la ficha'
);

SELECT is(
  (SELECT count(*)::int FROM crm.mi_dia(60, 'cccccccc-cccc-cccc-cccc-cccccccccccc') WHERE tipo = 'escalado'),
  1,
  'Abrir la ficha no es atender: sigue pendiente'
);

SELECT lives_ok(
  $$SELECT crm.marcar_atendido('dd005001-0000-0000-0000-000000000001', 'Lo llamé')$$,
  'El asesor lo llama y deja la nota'
);

SELECT is(
  (SELECT count(*)::int FROM crm.mi_dia(60, 'cccccccc-cccc-cccc-cccc-cccccccccccc') WHERE tipo = 'escalado'),
  0,
  'Ahora sí: alguien hizo algo después de que pidió una persona'
);

RESET ROLE;

-- =====================================================================
-- Lo que ve la admin
-- =====================================================================
SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT array_agg(titulo ORDER BY titulo)
     FROM crm.mi_dia(60, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') WHERE tipo = 'tarea_hoy'),
  ARRAY['De la admin', 'De nadie', 'Del asesor'],
  'La admin ve todas las tareas de hoy'
);

-- Las citas las ve quien tiene la franja (aquí, la admin de Alfa).
SELECT is(
  (SELECT array_agg(detalle ORDER BY detalle)
     FROM crm.mi_dia(60, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') WHERE tipo = 'visita_hoy'),
  ARRAY['Visita de hoy · Apartamento Alfa 101'],
  'En «Para hoy» sale la visita de hoy (en Bogotá) y no la de mañana'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
