-- =====================================================================
-- Solo líneas oficiales y el freno del bot fuera del CRM (16 oct 2026).
--
-- Lo que importa:
--  · con la preferencia apagada, nada cambia (las pruebas de siempre lo
--    cubren; aquí basta un testigo);
--  · encendida, lo de Kommo (sin línea) no entra, lo de una línea de
--    crm.lineas sí, y una cita solo entra si la persona ya está;
--  · el bot comercial sigue frenándose sin contacto: el escalamiento lo
--    calla, el cron lo devuelve si nadie atendió, y alguien del equipo lo
--    puede encender desde «Bots callados»;
--  · la limpieza archiva, vacía y no le devuelve la voz a nadie;
--  · el archivo y la limpieza no están al alcance de la app.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(51);

DELETE FROM crm.lineas;
DELETE FROM crm.contactos;
DELETE FROM crm.eventos;
DELETE FROM crm.frenos_bot;
DELETE FROM crm.preferencias;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'agente_comercial_mensajes' AND column_name = 'wa_phone_number_id'
  ) THEN
    ALTER TABLE public.agente_comercial_mensajes ADD COLUMN wa_phone_number_id text;
  END IF;
END $$;

INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre) VALUES
  ('11111111-1111-1111-1111-111111111111', 'administrativa', '320000000000045', 'Administrativa 320'),
  ('11111111-1111-1111-1111-111111111111', 'comercial',      '324000000000045', 'Comercial 324');

-- Las conversaciones de la plataforma (una por teléfono).
INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono, cliente_nombre) VALUES
  ('f4500001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '+573004500001', 'Testigo apagada'),
  ('f4500002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', '+573004500002', 'Lead por Kommo'),
  ('f4500003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', '+573004500003', 'Inquilina por el 320'),
  ('f4500004-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', '+573004500004', 'Número de prueba de Meta'),
  ('f4500005-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', '+573004500005', 'Escalado viejo'),
  ('f4500006-0000-0000-0000-000000000006', '11111111-1111-1111-1111-111111111111', '+573004500006', 'Lead oficial por el 324'),
  ('f4500007-0000-0000-0000-000000000007', '22222222-2222-2222-2222-222222222222', '+573004500007', 'Beta callado'),
  ('f4500008-0000-0000-0000-000000000008', '22222222-2222-2222-2222-222222222222', '+573004500008', 'Beta hablando');


-- ---------------------------------------------------------------------
-- 1 · Apagada: como siempre
-- ---------------------------------------------------------------------
SELECT is(crm.solo_lineas_oficiales('11111111-1111-1111-1111-111111111111'), false,
  'Sin preferencia, la inmobiliaria no está en solo líneas oficiales');

INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido, created_at)
VALUES ('f4500001-0000-0000-0000-000000000001', 'usuario', 'Hola, por Kommo', now() - interval '3 hours');

SELECT is(
  (SELECT count(*)::int FROM crm.contactos WHERE telefono_e164 = '+573004500001'), 1,
  'Apagada, un mensaje sin línea (Kommo) crea el contacto como siempre');


-- ---------------------------------------------------------------------
-- 2 · Encendida: solo lo que llega por una línea de crm.lineas
-- ---------------------------------------------------------------------
INSERT INTO crm.preferencias (inmobiliaria_id, solo_lineas_oficiales, solo_lineas_desde)
VALUES ('11111111-1111-1111-1111-111111111111', true, now() - interval '4 days');

SELECT is(crm.solo_lineas_oficiales('11111111-1111-1111-1111-111111111111'), true,
  'Encendida para Alfa');

INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido, created_at)
VALUES ('f4500002-0000-0000-0000-000000000002', 'usuario', 'Quiero ver el apartamento', now() - interval '2 hours');

SELECT is(
  (SELECT count(*)::int FROM crm.contactos WHERE telefono_e164 = '+573004500002'), 0,
  'Encendida, un mensaje sin línea (Kommo) no crea contacto');
SELECT is(
  (SELECT count(*)::int FROM crm.actividades a
     JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE c.telefono_e164 = '+573004500002'), 0,
  'Ni actividad');

INSERT INTO public.agente_comercial_mensajes
  (conversacion_id, rol, contenido, created_at, wa_phone_number_id, wa_message_id)
VALUES ('f4500003-0000-0000-0000-000000000003', 'usuario', 'Necesito el paz y salvo',
        now() - interval '90 minutes', '320000000000045', 'wamid.45.1');

SELECT is(
  (SELECT count(*)::int FROM crm.contactos WHERE telefono_e164 = '+573004500003'), 1,
  'Un mensaje por una línea de crm.lineas sí entra');
SELECT is(
  (SELECT a.wa_phone_number_id FROM crm.actividades a
     JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE c.telefono_e164 = '+573004500003' AND a.tipo = 'mensaje_entrante'),
  '320000000000045',
  'Y queda con su línea');

INSERT INTO public.agente_comercial_mensajes
  (conversacion_id, rol, contenido, created_at, wa_phone_number_id, wa_message_id)
VALUES ('f4500004-0000-0000-0000-000000000004', 'usuario', 'Mensaje al número de prueba',
        now() - interval '80 minutes', '999999999999999', 'wamid.45.2');

SELECT is(
  (SELECT count(*)::int FROM crm.contactos WHERE telefono_e164 = '+573004500004'), 0,
  'Un número que no es una línea de crm.lineas tampoco entra, aunque venga de Meta');

-- Beta sigue apagada: la preferencia es por inmobiliaria.
INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido, created_at) VALUES
  ('f4500007-0000-0000-0000-000000000007', 'usuario', 'Hola Beta', now() - interval '5 hours'),
  ('f4500007-0000-0000-0000-000000000007', 'agente',  'Hola, ¿en qué te ayudo?', now() - interval '299 minutes'),
  ('f4500008-0000-0000-0000-000000000008', 'usuario', 'Otro de Beta', now() - interval '5 hours');

SELECT is(
  (SELECT count(*)::int FROM crm.contactos WHERE inmobiliaria_id = '22222222-2222-2222-2222-222222222222'), 2,
  'Beta, apagada, sigue copiando lo de Kommo');


-- ---------------------------------------------------------------------
-- 3 · Citas: solo de quien ya está
-- ---------------------------------------------------------------------
INSERT INTO public.citas
  (id, inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono)
VALUES
  ('cc450001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'a3333333-3333-3333-3333-333333333333', 'a1111111-1111-1111-1111-111111111111',
   current_date + 3, '09:00', '09:30', 'Lead por Kommo', '+573004500002'),
  ('cc450002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'a3333333-3333-3333-3333-333333333333', 'a1111111-1111-1111-1111-111111111111',
   current_date + 3, '10:00', '10:30', 'Inquilina por el 320', '+573004500003');

SELECT is(
  (SELECT count(*)::int FROM crm.contactos WHERE telefono_e164 = '+573004500002'), 0,
  'La cita de alguien que no está en el CRM no lo crea');
SELECT is(
  (SELECT count(*)::int FROM crm.actividades a
     JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE c.telefono_e164 = '+573004500003' AND a.tipo = 'visita_agendada'), 1,
  'La cita de alguien que ya está sí entra a su ficha');

INSERT INTO public.solicitudes_apertura
  (inmobiliaria_id, inmueble_id, fecha, hora_inicio, hora_fin, cliente_nombre, cliente_telefono)
VALUES ('11111111-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111',
        current_date + 2, '18:00', '19:00', 'Lead por Kommo', '300 450 00 02');

SELECT is(
  (SELECT count(*)::int FROM crm.contactos WHERE telefono_e164 = '+573004500002'), 0,
  'Una solicitud de apertura tampoco crea a nadie');


-- ---------------------------------------------------------------------
-- 4 · El freno de quien no está en el CRM
-- ---------------------------------------------------------------------
-- Un lead oficial por el 324: tiene contacto y oportunidad comercial.
INSERT INTO public.agente_comercial_mensajes
  (conversacion_id, rol, contenido, created_at, wa_phone_number_id, wa_message_id)
VALUES ('f4500006-0000-0000-0000-000000000006', 'usuario', 'Hola, vi el anuncio',
        now() - interval '70 minutes', '324000000000045', 'wamid.45.3');

-- Nació con ese mensaje, hace 70 minutos (en la transacción todo es now()):
-- desde el 26 oct un escalamiento anterior al contacto no cuenta.
UPDATE crm.contactos SET created_at = now() - interval '70 minutes'
 WHERE telefono_e164 = '+573004500006';
UPDATE crm.oportunidades o SET created_at = now() - interval '70 minutes'
  FROM crm.contactos c
 WHERE c.id = o.contacto_id AND c.telefono_e164 = '+573004500006';

INSERT INTO public.agente_comercial_uso
  (inmobiliaria_id, conversacion_id, modelo, etapa, escalado, created_at)
VALUES
  -- El lead por Kommo escala ahora: el freno lo calla.
  ('11111111-1111-1111-1111-111111111111', 'f4500002-0000-0000-0000-000000000002',
   'claude-opus-5', 'CONSULTA', true, now() - interval '30 minutes'),
  -- Escalado hace 3 días: después de encender, pero fuera de las 48 horas.
  ('11111111-1111-1111-1111-111111111111', 'f4500005-0000-0000-0000-000000000005',
   'claude-opus-5', 'CONSULTA', true, now() - interval '3 days'),
  -- Escalado hace 5 días: antes de encender.
  ('11111111-1111-1111-1111-111111111111', 'f4500005-0000-0000-0000-000000000005',
   'claude-opus-5', 'CONSULTA', true, now() - interval '5 days'),
  -- El lead oficial escala: lo cubre su contacto, no el freno.
  ('11111111-1111-1111-1111-111111111111', 'f4500006-0000-0000-0000-000000000006',
   'claude-opus-5', 'CONSULTA', true, now() - interval '20 minutes');

SELECT ok(crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573004500002'),
  'Antes del cron el bot del lead por Kommo puede hablar');

SELECT ok(crm.sincronizar_escalamientos() >= 1, 'El cron de escalamientos encuentra trabajo');

SELECT results_eq(
  $$SELECT bot_activo, bot_motivo, bot_caduca, conversacion_id::text, nombre
      FROM crm.frenos_bot WHERE telefono_e164 = '+573004500002'$$,
  $$VALUES (false, 'escalamiento', true, 'f4500002-0000-0000-0000-000000000002', 'Lead por Kommo')$$,
  'El escalamiento por Kommo calla al bot en el freno, con su conversación y su nombre');
SELECT is(crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '300 450 00 02'), false,
  'Y crm.bot_puede_responder lo ve, con el teléfono como venga');
SELECT is(
  (SELECT count(*)::int FROM crm.frenos_bot WHERE telefono_e164 = '+573004500005'), 0,
  'Los escalamientos de antes de encender o de hace más de 48 horas no frenan a nadie');
SELECT is(
  (SELECT count(*)::int FROM crm.frenos_bot WHERE telefono_e164 = '+573004500006'), 0,
  'Quien tiene oportunidad comercial abierta no va al freno');
SELECT results_eq(
  $$SELECT bot_activo, bot_motivo FROM crm.contactos WHERE telefono_e164 = '+573004500006'$$,
  $$VALUES (false, 'escalamiento')$$,
  'Lo calla su contacto, como siempre');
SELECT is(crm.sincronizar_escalamientos(), 0,
  'Una segunda pasada no vuelve a tocar nada');

-- Dentro de la prueba todo pasa en el mismo now(): se hace como si el
-- cron hubiera pasado hace 25 minutos, para que lo que llegue después sea
-- de verdad posterior al silencio.
UPDATE crm.frenos_bot SET bot_cambiado_at = now() - interval '25 minutes'
 WHERE telefono_e164 = '+573004500002';

-- Lo que sigue llegando por Kommo alimenta el freno sin entrar al CRM.
INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido, created_at) VALUES
  ('f4500002-0000-0000-0000-000000000002', 'usuario', '¿Hay alguien?', now() - interval '10 minutes');
SELECT is(
  (SELECT ultimo_entrante_at FROM crm.frenos_bot WHERE telefono_e164 = '+573004500002'),
  now() - interval '10 minutes',
  'El freno anota cuándo escribió la persona por última vez');
SELECT is(
  (SELECT count(*)::int FROM crm.contactos WHERE telefono_e164 = '+573004500002'), 0,
  'Sin crear el contacto');
SELECT is(
  (SELECT atendido_at FROM crm.frenos_bot WHERE telefono_e164 = '+573004500002'), NULL,
  'Nadie del equipo le ha escrito todavía');

INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido, created_at) VALUES
  ('f4500002-0000-0000-0000-000000000002', 'asesor', 'Hola, soy Laura', now() - interval '5 minutes');
SELECT is(
  (SELECT atendido_at FROM crm.frenos_bot WHERE telefono_e164 = '+573004500002'),
  now() - interval '5 minutes',
  'Un mensaje de alguien del equipo por Kommo cuenta como atendido');


-- ---------------------------------------------------------------------
-- 5 · El cron que devuelve la voz
-- ---------------------------------------------------------------------
INSERT INTO crm.frenos_bot
  (inmobiliaria_id, telefono_e164, nombre, bot_activo, bot_motivo, bot_caduca,
   bot_cambiado_at, atendido_at)
VALUES
  ('11111111-1111-1111-1111-111111111111', '+573004509001', 'Vence sin atender',
   false, 'escalamiento', true, now() - interval '7 hours', NULL),
  ('11111111-1111-1111-1111-111111111111', '+573004509002', 'Vence pero atendido',
   false, 'escalamiento', true, now() - interval '7 hours', now() - interval '6 hours'),
  ('11111111-1111-1111-1111-111111111111', '+573004509003', 'No caduca',
   false, 'escalamiento', false, now() - interval '7 hours', NULL),
  ('11111111-1111-1111-1111-111111111111', '+573004509004', 'Apagado a mano',
   false, 'manual', true, now() - interval '7 days', NULL),
  ('11111111-1111-1111-1111-111111111111', '+573004509005', 'Todavía no vence',
   false, 'escalamiento', true, now() - interval '2 hours', NULL);

SELECT ok(crm.reactivar_bots() >= 1, 'El cron devuelve la voz a alguien');
SELECT results_eq(
  $$SELECT telefono_e164 FROM crm.frenos_bot
     WHERE telefono_e164 LIKE '+57300450900%' AND bot_activo ORDER BY 1$$,
  $$VALUES ('+573004509001'::text)$$,
  'Solo vuelve el escalado que caduca, ya venció y nadie atendió');


-- ---------------------------------------------------------------------
-- 6 · «Bots callados» y el botón de encender
-- ---------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;

SELECT results_eq(
  $$SELECT contacto_id IS NULL, motivo, atendido, vuelve_at IS NULL
      FROM crm.v_bot_callado WHERE telefono_e164 = '+573004500002'$$,
  $$VALUES (true, 'escalamiento', true, true)$$,
  'La lista enseña el freno sin contacto: atendido, así que no vuelve solo');
SELECT is(
  (SELECT vuelve_at FROM crm.v_bot_callado WHERE telefono_e164 = '+573004509005'),
  now() - interval '2 hours' + crm.ventana_silencio_escalamiento(),
  'Y la hora a la que vuelve solo es la del cron');

SELECT ok(crm.encender_bot_freno('+57 300 450 0002'), 'Un asesor enciende el bot desde la lista');

RESET ROLE;
SELECT results_eq(
  $$SELECT bot_activo, bot_motivo, bot_cambiado_por::text FROM crm.frenos_bot WHERE telefono_e164 = '+573004500002'$$,
  $$VALUES (true, NULL::text, 'cccccccc-cccc-cccc-cccc-cccccccccccc')$$,
  'El freno queda encendido y con quién lo encendió');
SELECT is(crm.sincronizar_escalamientos(), 0,
  'El mismo escalamiento no lo vuelve a callar');

-- Lo encendieron hace diez minutos (en la transacción todo es now()), y
-- la persona vuelve a pedir ayuda hace uno: desde el 26 oct solo calla un
-- pedido POSTERIOR al último cambio del freno.
UPDATE crm.frenos_bot SET bot_cambiado_at = now() - interval '10 minutes'
 WHERE telefono_e164 = '+573004500002';

INSERT INTO public.agente_comercial_uso
  (inmobiliaria_id, conversacion_id, modelo, etapa, escalado, created_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'f4500002-0000-0000-0000-000000000002',
        'claude-opus-5', 'CONSULTA', true, now() - interval '1 minute');
SELECT is(crm.sincronizar_escalamientos(), 1, 'Un escalamiento nuevo sí');
SELECT is(crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573004500002'), false,
  'Y el bot vuelve a callarse');

-- Un apagado a mano no se convierte en escalamiento: si no, volvería solo.
INSERT INTO crm.frenos_bot
  (inmobiliaria_id, telefono_e164, conversacion_id, bot_activo, bot_motivo, bot_caduca, bot_cambiado_at)
VALUES ('11111111-1111-1111-1111-111111111111', '+573004500004',
        'f4500004-0000-0000-0000-000000000004', false, 'manual', true, now() - interval '1 day');
INSERT INTO public.agente_comercial_uso
  (inmobiliaria_id, conversacion_id, modelo, etapa, escalado, created_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'f4500004-0000-0000-0000-000000000004',
        'claude-opus-5', 'CONSULTA', true, now() - interval '2 minutes');
SELECT is(crm.sincronizar_escalamientos(), 1, 'El escalamiento de alguien apagado a mano se anota');
SELECT results_eq(
  $$SELECT bot_activo, bot_motivo, bot_cambiado_at, escalado_at
      FROM crm.frenos_bot WHERE telefono_e164 = '+573004500004'$$,
  $$VALUES (false, 'manual', now() - interval '1 day', now() - interval '2 minutes')$$,
  'Pero sigue siendo un apagado a mano, con su hora: no vuelve solo');

-- Lo de Alfa no se ve ni se toca desde Beta.
SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM crm.frenos_bot WHERE inmobiliaria_id = '11111111-1111-1111-1111-111111111111'), 0,
  'Beta no ve el freno de Alfa');
SELECT is(crm.encender_bot_freno('+573004500002'), false, 'Ni lo puede encender');

-- Las funciones y las columnas de sistema no están al alcance de la app.
SELECT throws_ok(
  $$INSERT INTO crm.frenos_bot (inmobiliaria_id, telefono_e164, bot_activo, bot_motivo)
    VALUES ('22222222-2222-2222-2222-222222222222', '+573009999999', false, 'manual')$$,
  '42501', NULL, 'Nadie de la app crea frenos a mano');
SELECT throws_ok(
  $$UPDATE crm.frenos_bot SET escalado_at = now()$$,
  '42501', NULL, 'Ni toca las columnas que escribe el sistema');
SELECT throws_ok(
  $$UPDATE crm.preferencias SET solo_lineas_oficiales = false$$,
  '42501', NULL, 'Ni apaga la preferencia');
SELECT throws_ok(
  $$SELECT count(*) FROM crm_archivo.contactos$$,
  '42501', NULL, 'El archivo está cerrado para la app');
SELECT throws_ok(
  $$SELECT crm.archivar_era_kommo('22222222-2222-2222-2222-222222222222')$$,
  '42501', NULL, 'Y la limpieza también');

RESET ROLE;


-- ---------------------------------------------------------------------
-- 7 · La limpieza
-- ---------------------------------------------------------------------
-- Beta: un contacto con el bot callado por escalamiento y otro hablando.
UPDATE crm.contactos
   SET bot_activo = false, bot_motivo = 'escalamiento', bot_caduca = true,
       bot_cambiado_at = now() - interval '1 hour'
 WHERE telefono_e164 = '+573004500007';

CREATE TEMP TABLE antes_beta AS
  SELECT (SELECT count(*) FROM crm.actividades WHERE inmobiliaria_id = '22222222-2222-2222-2222-222222222222') AS actividades;

CREATE TEMP TABLE limpieza AS
  SELECT crm.archivar_era_kommo('22222222-2222-2222-2222-222222222222') AS r;

SELECT is((SELECT (r ->> 'contactos')::int FROM limpieza), 2, 'La limpieza reporta los contactos que archivó');
SELECT is((SELECT (r ->> 'frenos')::int FROM limpieza), 1, 'Y el bot callado que pasó al freno');
SELECT is(
  (SELECT count(*)::int FROM crm.contactos WHERE inmobiliaria_id = '22222222-2222-2222-2222-222222222222'), 0,
  'El CRM de Beta queda vacío');
SELECT is(
  (SELECT count(*)::int FROM crm_archivo.actividades WHERE inmobiliaria_id = '22222222-2222-2222-2222-222222222222'),
  (SELECT actividades::int FROM antes_beta),
  'Todas sus actividades están en el archivo');
SELECT results_eq(
  $$SELECT bot_activo, bot_motivo, conversacion_id::text FROM crm.frenos_bot
     WHERE inmobiliaria_id = '22222222-2222-2222-2222-222222222222'$$,
  $$VALUES (false, 'escalamiento', 'f4500007-0000-0000-0000-000000000007')$$,
  'El callado sigue callado, ahora en el freno y atado a su conversación');
SELECT ok(
  NOT crm.bot_puede_responder('22222222-2222-2222-2222-222222222222', '+573004500007')
  AND crm.bot_puede_responder('22222222-2222-2222-2222-222222222222', '+573004500008'),
  'Al bot no le cambia nada: el callado sigue callado y el otro sigue hablando');
SELECT is(crm.solo_lineas_oficiales('22222222-2222-2222-2222-222222222222'), true,
  'Y Beta queda en solo líneas oficiales');

-- Un escalamiento de antes de la limpieza (hace una hora) ya no frena a
-- nadie: lo habría visto el CRM con sus contactos, y si no lo calló fue
-- porque no tocaba.
INSERT INTO public.agente_comercial_uso
  (inmobiliaria_id, conversacion_id, modelo, etapa, escalado, created_at)
VALUES ('22222222-2222-2222-2222-222222222222', 'f4500008-0000-0000-0000-000000000008',
        'claude-opus-5', 'CONSULTA', true, now() - interval '1 hour');
SELECT is(crm.sincronizar_escalamientos(), 0,
  'Un escalamiento de antes de encender no frena a nadie, aunque sea de las últimas 48 horas');

-- No archiva a quien ya tiene envíos: su historial se perdería.
INSERT INTO crm.envios (inmobiliaria_id, contacto_id, cuerpo)
SELECT inmobiliaria_id, id, 'Hola' FROM crm.contactos WHERE telefono_e164 = '+573004500003';
SELECT throws_ok(
  $$SELECT crm.archivar_era_kommo('11111111-1111-1111-1111-111111111111')$$,
  '55000', NULL, 'La limpieza se niega si la inmobiliaria ya tiene envíos');

SELECT * FROM finish();
ROLLBACK;
