-- =====================================================================
-- "Mi día".
--
-- Lo que se mide: que el ORDEN sea la función —lo que se pierde por no
-- mirarlo va primero— que las siete fuentes lleguen a una sola lista, que
-- completar una tarea la saque, y que nada se filtre entre inmobiliarias.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(13);

DELETE FROM crm.contactos;
DELETE FROM crm.tareas;
DELETE FROM public.citas;
DELETE FROM public.tareas;

INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, ultima_actividad_at)
VALUES
  ('dd000001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Espera una persona', '+573001110001', now()),
  ('dd000002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'Tiene tarea', '+573001110002', now());

-- Hace falta la actividad para que nazca la oportunidad: el requerimiento
-- describe lo que alguien quiere, la actividad registra lo que pasó.
INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, ocurrido_at, metadata)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
   'dd000001-0000-0000-0000-000000000001', now() - interval '40 minutes',
   '{"origen_tabla":"t","origen_id":"d1"}'),
  ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
   'dd000002-0000-0000-0000-000000000002', now() - interval '1 hour',
   '{"origen_tabla":"t","origen_id":"d2"}');

-- El bot pidió una persona hace 40 minutos y nadie ha abierto la ficha.
UPDATE crm.oportunidades SET escalado_at = now() - interval '40 minutes'
 WHERE contacto_id = 'dd000001-0000-0000-0000-000000000001';

-- Una visita HOY.
INSERT INTO public.citas
  (id, inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono)
VALUES ('cc00dd01-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'a3333333-3333-3333-3333-333333333333',
        'a1111111-1111-1111-1111-111111111111',
        current_date, '15:00', '15:30', 'Visita de hoy', '+573001110003');

-- Una tarea vencida y una de hoy.
INSERT INTO crm.tareas (id, inmobiliaria_id, contacto_id, titulo, vence_at)
VALUES
  ('77770001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'dd000002-0000-0000-0000-000000000002', 'Llamarlo, se prometió ayer',
   now() - interval '2 days'),
  ('77770002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'dd000002-0000-0000-0000-000000000002', 'Mandarle el apartamento',
   date_trunc('day', now()) + interval '9 hours');

-- Una tarea pendiente de la plataforma de inventario.
INSERT INTO public.tareas
  (inmobiliaria_id, entidad_tipo, evento_titulo, titulo, estado)
VALUES ('11111111-1111-1111-1111-111111111111', 'inmueble',
        'Inventario', 'Subir fotos del apto 301', 'pendiente');

SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

-- --- LA AFIRMACIÓN QUE MÁS IMPORTA -----------------------------------
-- El orden ES la función. Sin prioridad esto sería otra bandeja más, y de
-- bandejas el asesor ya tiene cuatro.
SELECT is(
  (SELECT tipo FROM crm.mi_dia() LIMIT 1),
  'escalado',
  'Lo primero del día es quien está esperando a una persona'
);

SELECT is(
  (SELECT contacto_id FROM crm.mi_dia() LIMIT 1),
  'dd000001-0000-0000-0000-000000000001'::uuid,
  'Y viene con a quién hay que escribirle, no solo con el aviso'
);

SELECT ok(
  (SELECT prioridad FROM crm.mi_dia() WHERE tipo = 'visita_hoy')
  < (SELECT prioridad FROM crm.mi_dia() WHERE tipo = 'tarea_hoy'),
  'Una visita de hoy va antes que una tarea de hoy: tiene hora'
);

SELECT ok(
  (SELECT prioridad FROM crm.mi_dia() WHERE tipo = 'tarea_vencida')
  < (SELECT prioridad FROM crm.mi_dia() WHERE tipo = 'tarea_hoy'),
  'Y lo que se prometió y no se hizo, antes que lo de hoy'
);

-- --- Las siete fuentes, una sola lista --------------------------------
SELECT is(
  (SELECT count(*)::int FROM crm.mi_dia() WHERE tipo = 'visita_hoy'),
  1,
  'La visita de hoy llega desde public.citas'
);

SELECT is(
  (SELECT count(*)::int FROM crm.mi_dia() WHERE tipo = 'tarea_plataforma'),
  1,
  'Y la tarea de la plataforma de inventario también: un solo sitio donde mirar'
);

SELECT is(
  (SELECT count(*)::int FROM crm.mi_dia() WHERE tipo = 'tarea_vencida'),
  1,
  'La vencida está'
);

SELECT is(
  (SELECT count(*)::int FROM crm.mi_dia() WHERE tipo = 'tarea_hoy'),
  1,
  'Y la de hoy'
);

-- --- Completar --------------------------------------------------------
SELECT lives_ok(
  $$SELECT crm.completar_tarea('77770001-0000-0000-0000-000000000001')$$,
  'Se puede marcar como hecha'
);

SELECT is(
  (SELECT count(*)::int FROM crm.mi_dia() WHERE tipo = 'tarea_vencida'),
  0,
  'Y desaparece del día'
);

-- No se borra: "qué se hizo ayer" es una pregunta que alguien va a hacer.
SELECT ok(
  (SELECT completada_at IS NOT NULL FROM crm.tareas
    WHERE id = '77770001-0000-0000-0000-000000000001'),
  'Pero la tarea NO se borra: queda con fecha de cuándo se hizo'
);

-- --- Una tarea sin fecha no es una tarea ------------------------------
RESET ROLE;
SELECT throws_ok(
  $$INSERT INTO crm.tareas (inmobiliaria_id, titulo)
    VALUES ('11111111-1111-1111-1111-111111111111', 'Sin fecha')$$,
  '23502',
  NULL,
  'Una tarea sin fecha no se guarda: sin fecha no se puede ordenar un día'
);

-- --- Aislamiento ------------------------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM crm.mi_dia() WHERE tipo IN ('escalado','tarea_hoy','tarea_vencida')),
  0,
  'Beta no ve ni una cosa del día de Alfa'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
