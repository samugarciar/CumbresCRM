-- =====================================================================
-- PRUEBA 61: El reciclador de leads (migración 20261113120001)
--
-- Lo que tiene que garantizar:
--   · LA regla: solo a quien le escribimos de último, callado más de
--     horas_silencio y dentro de dias_atras; nunca a quien nos dejó
--     esperando, ni con opt-out, bot callado, visita agendada o sin
--     nombre cuando la plantilla lo pide.
--   · Dos intentos por silencio, separados por el mismo silencio; si la
--     persona contesta, el conteo vuelve a cero.
--   · Solo un admin configura; enviar de verdad exige plantilla aprobada.
--   · En simulación no sale nada; de verdad sale con `origen: reciclador`.
--   · Si falla el canal, el intento no cuenta y el reciclador se apaga.
--
-- La red no se toca: crm.pedir_envio_a_plataforma se cambia por uno que
-- anota la petición. Las fechas son fijas: el martes 17 nov 2026 a las
-- 10:00 de Bogotá (15:00 UTC) es T.
-- =====================================================================
BEGIN;
SELECT plan(33);

-- ---------------------------------------------------------------------
-- Fixtures (como postgres)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t AS SELECT '2026-11-17 15:00:00+00'::timestamptz AS v;

INSERT INTO crm.lineas (id, inmobiliaria_id, embudo, wa_phone_number_id, nombre) VALUES
  ('11610000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'comercial', '312000000000061', 'Comercial 312'),
  ('11610000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'administrativa', '320000000000061', 'Administrativa 320');

INSERT INTO crm.plantillas
  (id, inmobiliaria_id, nombre, cuerpo, categoria, estado_meta, nombre_meta, wa_phone_number_id)
VALUES
  ('fa610001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Retomar', 'Hola {{nombre}}, ¿sigues buscando inmueble? Aquí seguimos para ayudarte.',
   'marketing', 'aprobada', 'retomar_conversacion', '312000000000061'),
  ('fa610002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'Retomar v2', 'Hola {{nombre}}, ¿seguimos?', 'marketing', 'enviada', 'retomar_v2',
   '312000000000061'),
  ('fa610003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
   'Con barrio', 'Hola {{nombre}}, hay algo en {{barrio}}.', 'marketing', 'aprobada',
   'con_barrio', '312000000000061');

-- Nueve personas, una por caso.
INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, opt_out, opt_out_at,
                           bot_activo, bot_motivo) VALUES
  ('c0610000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Ana María', '+573006100001', false, NULL, true, NULL),
  ('c0610000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Beto',  '+573006100002', false, NULL, true, NULL),
  ('c0610000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Carla', '+573006100003', false, NULL, true, NULL),
  ('c0610000-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'Darío', '+573006100004', false, NULL, true, NULL),
  ('c0610000-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'Elena', '+573006100005', true,  now(), true, NULL),
  ('c0610000-0000-0000-0000-000000000006', '11111111-1111-1111-1111-111111111111', 'Fabio', '+573006100006', false, NULL, false, 'manual'),
  ('c0610000-0000-0000-0000-000000000007', '11111111-1111-1111-1111-111111111111', 'Gina',  '+573006100007', false, NULL, true, NULL),
  ('c0610000-0000-0000-0000-000000000008', '11111111-1111-1111-1111-111111111111', 'Hugo',  '+573006100008', false, NULL, true, NULL),
  ('c0610000-0000-0000-0000-000000000009', '11111111-1111-1111-1111-111111111111', NULL,    '+573006100009', false, NULL, true, NULL);

-- Las conversaciones por la 312. (horas antes de T: entrante, saliente)
--   Ana 30/29 → muerta · Beto 5/4 → muy reciente · Carla 20/19 al revés →
--   nos dejó esperando (entra desde el 17 nov, perilla incluir_esperando) · Darío 10 días → fuera de la ventana · Elena,
--   Fabio, Gina e Iván como Ana pero excluidos · Hugo nunca escribió.
INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, ocurrido_at, wa_phone_number_id)
SELECT '11111111-1111-1111-1111-111111111111', x.tipo, x.origen, x.contacto::uuid,
       (SELECT v FROM t) - make_interval(hours => x.horas), '312000000000061'
  FROM (VALUES
    ('c0610000-0000-0000-0000-000000000001', 'mensaje_entrante', 'humano', 30),
    ('c0610000-0000-0000-0000-000000000001', 'mensaje_saliente', 'agente_ia', 29),
    ('c0610000-0000-0000-0000-000000000002', 'mensaje_entrante', 'humano', 5),
    ('c0610000-0000-0000-0000-000000000002', 'mensaje_saliente', 'agente_ia', 4),
    ('c0610000-0000-0000-0000-000000000003', 'mensaje_saliente', 'agente_ia', 20),
    ('c0610000-0000-0000-0000-000000000003', 'mensaje_entrante', 'humano', 19),
    ('c0610000-0000-0000-0000-000000000004', 'mensaje_entrante', 'humano', 240),
    ('c0610000-0000-0000-0000-000000000004', 'mensaje_saliente', 'agente_ia', 239),
    ('c0610000-0000-0000-0000-000000000005', 'mensaje_entrante', 'humano', 30),
    ('c0610000-0000-0000-0000-000000000005', 'mensaje_saliente', 'agente_ia', 29),
    ('c0610000-0000-0000-0000-000000000006', 'mensaje_entrante', 'humano', 30),
    ('c0610000-0000-0000-0000-000000000006', 'mensaje_saliente', 'humano', 29),
    ('c0610000-0000-0000-0000-000000000007', 'mensaje_entrante', 'humano', 30),
    ('c0610000-0000-0000-0000-000000000007', 'mensaje_saliente', 'agente_ia', 29),
    ('c0610000-0000-0000-0000-000000000008', 'mensaje_saliente', 'humano', 29),
    ('c0610000-0000-0000-0000-000000000009', 'mensaje_entrante', 'humano', 30),
    ('c0610000-0000-0000-0000-000000000009', 'mensaje_saliente', 'agente_ia', 29)
  ) AS x(contacto, tipo, origen, horas);

-- Gina tiene visita mañana (la proyección la enlaza; si no, se enlaza aquí).
INSERT INTO public.citas
  (id, inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono)
VALUES ('cc610001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'a3333333-3333-3333-3333-333333333333', 'a1111111-1111-1111-1111-111111111111',
        crm.hoy() + 1, '09:00', '09:30', 'Gina', '+573006100007');
INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cita_id, ocurrido_at)
SELECT '11111111-1111-1111-1111-111111111111', 'sistema', 'sistema',
       'c0610000-0000-0000-0000-000000000007', 'cc610001-0000-0000-0000-000000000001', now()
 WHERE NOT EXISTS (SELECT 1 FROM crm.actividades
                    WHERE cita_id = 'cc610001-0000-0000-0000-000000000001'
                      AND contacto_id = 'c0610000-0000-0000-0000-000000000007');

-- La red, de mentira.
CREATE TEMP TABLE peticiones (n serial, cuerpo jsonb);
GRANT ALL ON peticiones TO PUBLIC;
CREATE OR REPLACE FUNCTION crm.pedir_envio_a_plataforma(p_url text, p_token text, p_cuerpo jsonb)
RETURNS bigint
LANGUAGE sql VOLATILE SET search_path = ''
AS $f$
  INSERT INTO pg_temp.peticiones (cuerpo) VALUES (p_cuerpo) RETURNING 961000 + n;
$f$;

-- ---------------------------------------------------------------------
-- Configurar: quién puede y qué exige
-- ---------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$SELECT crm.configurar_reciclador('11610000-0000-0000-0000-000000000001', true, true,
      12, 2, 7, 50, 'fa610001-0000-0000-0000-000000000001')$$,
  '42501', NULL, 'Un asesor no puede configurar el reciclador');

SELECT throws_ok(
  $$SELECT crm.despachar_reciclaje()$$,
  '42501', NULL, 'Nadie de la pantalla puede correr el despachador');

RESET ROLE;
SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$SELECT crm.configurar_reciclador('11610000-0000-0000-0000-000000000002', true, true,
      12, 2, 7, 50, NULL)$$,
  '22023', 'El reciclador es solo para la línea comercial', 'Solo en la línea comercial');

SELECT throws_ok(
  $$SELECT crm.configurar_reciclador('11610000-0000-0000-0000-000000000001', true, false,
      12, 2, 7, 50, 'fa610002-0000-0000-0000-000000000002')$$,
  '22023', 'Para enviar de verdad hace falta una plantilla aprobada por Meta',
  'Enviar de verdad exige plantilla aprobada');

SELECT throws_ok(
  $$SELECT crm.configurar_reciclador('11610000-0000-0000-0000-000000000001', true, true,
      12, 2, 7, 50, 'fa610003-0000-0000-0000-000000000003')$$,
  '22023', 'La plantilla solo puede usar la variable {{nombre}}',
  'Una plantilla con variables que el reciclador no sabe rellenar se rechaza');

SELECT throws_ok(
  $$SELECT crm.configurar_reciclador('11610000-0000-0000-0000-000000000001', true, true,
      12, 5, 7, 50, 'fa610001-0000-0000-0000-000000000001')$$,
  '23514', NULL, 'Más de 3 intentos no se admite');

SELECT lives_ok(
  $$SELECT crm.configurar_reciclador('11610000-0000-0000-0000-000000000001', true, true,
      12, 2, 7, 50, 'fa610001-0000-0000-0000-000000000001')$$,
  'El admin lo enciende en simulación: 12 horas, 2 intentos, 7 días');

-- La marca de la función dura lo que la transacción; en la app cada
-- petición es la suya. Se limpia para probar la escritura a mano.
SELECT set_config('crm.reciclador', '', true);
SELECT throws_ok(
  $$UPDATE crm.reciclador_config SET simulacion = false
     WHERE linea_id = '11610000-0000-0000-0000-000000000001'$$,
  '42501', NULL, 'Ni el admin puede escribir la fila a mano: solo por la función');

-- ---------------------------------------------------------------------
-- LA regla
-- ---------------------------------------------------------------------
SELECT results_eq(
  $$SELECT nombre FROM crm.candidatos_reciclaje('11610000-0000-0000-0000-000000000001',
      '2026-11-17 15:00:00+00')$$,
  ARRAY['Ana María', 'Carla'],
  'Ana (hablamos de último, 29 h) y Carla (nos dejó esperando, 19 h); los demás quedan fuera');

SELECT is(
  (SELECT nos_esperaba FROM crm.candidatos_reciclaje('11610000-0000-0000-0000-000000000001',
      '2026-11-17 15:00:00+00') WHERE nombre = 'Carla'),
  true, 'Carla viene marcada como «nos esperaba»');

-- Con la perilla apagada vuelve la regla del 13 nov: solo a quien le hablamos de último.
SELECT crm.configurar_reciclador('11610000-0000-0000-0000-000000000001', true, true,
  12, 2, 7, 50, 'fa610001-0000-0000-0000-000000000001', p_incluir_esperando => false);
SELECT results_eq(
  $$SELECT nombre FROM crm.candidatos_reciclaje('11610000-0000-0000-0000-000000000001',
      '2026-11-17 15:00:00+00')$$,
  ARRAY['Ana María'],
  'Con incluir_esperando apagado, Carla no entra');
SELECT crm.configurar_reciclador('11610000-0000-0000-0000-000000000001', true, true,
  12, 2, 7, 50, 'fa610001-0000-0000-0000-000000000001');

SELECT is(
  (SELECT intento FROM crm.candidatos_reciclaje('11610000-0000-0000-0000-000000000001',
      '2026-11-17 15:00:00+00') WHERE nombre = 'Ana María'),
  1, 'Es su primer intento');

SELECT results_eq(
  $$SELECT nombre FROM crm.candidatos_reciclaje('11610000-0000-0000-0000-000000000001',
      '2026-11-17 23:00:00+00') ORDER BY nombre$$,
  ARRAY['Ana María', 'Beto', 'Carla'],
  'Ocho horas después Beto también cumple las 12 horas de silencio');

RESET ROLE;
SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM crm.reciclador_config), 0,
  'Otra inmobiliaria no ve la configuración');
SELECT is(
  (SELECT count(*)::int FROM crm.candidatos_reciclaje('11610000-0000-0000-0000-000000000001',
      '2026-11-17 15:00:00+00')), 0,
  'Ni los candidatos de otra inmobiliaria');

RESET ROLE;

-- ---------------------------------------------------------------------
-- El despachador en simulación
-- ---------------------------------------------------------------------
SELECT is(crm.despachar_reciclaje('2026-11-22 15:00:00+00'), 0, 'Un domingo no sale nada');

SELECT is(crm.despachar_reciclaje('2026-11-17 15:00:00+00'), 2,
  'En simulación cuenta a Ana y a Carla');
SELECT is(
  (SELECT count(*)::int FROM crm.reciclador_intentos
    WHERE contacto_id = 'c0610000-0000-0000-0000-000000000001' AND simulado AND envio_id IS NULL
      AND numero = 1),
  1, 'Queda un intento simulado, sin envío');
SELECT is((SELECT count(*)::int FROM pg_temp.peticiones), 0, 'Y no sale ninguna petición');
SELECT is(
  (SELECT cuerpo FROM crm.reciclador_intentos
    WHERE contacto_id = 'c0610000-0000-0000-0000-000000000001'),
  'Hola Ana, ¿sigues buscando inmueble? Aquí seguimos para ayudarte.',
  'Con el primer nombre en la plantilla');

SELECT is(crm.despachar_reciclaje('2026-11-17 16:00:00+00'), 0,
  'Una hora después no se le repite: entre intentos va el mismo silencio');

-- Al día siguiente, el segundo intento (Beto, ya con 28 h, entra con su primero).
SELECT is(crm.despachar_reciclaje('2026-11-18 15:00:00+00'), 3,
  'Al día siguiente: segundos intentos de Ana y Carla y primero de Beto');
SELECT is(
  (SELECT max(numero)::int FROM crm.reciclador_intentos
    WHERE contacto_id = 'c0610000-0000-0000-0000-000000000001'),
  2, 'El de Ana es el número 2');

-- Al tercer día, Ana ya llegó al tope.
SELECT ok(
  NOT EXISTS (SELECT 1 FROM crm.candidatos_reciclaje('11610000-0000-0000-0000-000000000001',
      '2026-11-19 15:00:00+00') WHERE nombre = 'Ana María'),
  'Con dos intentos, Ana ya no es candidata');

-- Ana contesta y el bot le responde: es otro silencio y el conteo vuelve a cero.
INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, ocurrido_at, wa_phone_number_id)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
   'c0610000-0000-0000-0000-000000000001', '2026-11-19 14:00:00+00', '312000000000061'),
  ('11111111-1111-1111-1111-111111111111', 'mensaje_saliente', 'agente_ia',
   'c0610000-0000-0000-0000-000000000001', '2026-11-19 14:01:00+00', '312000000000061');

SELECT is(
  (SELECT intento FROM crm.candidatos_reciclaje('11610000-0000-0000-0000-000000000001',
      '2026-11-20 15:00:00+00') WHERE nombre = 'Ana María'),
  1, 'Si contesta y se vuelve a callar, empieza otra vez por el primer intento');

-- ---------------------------------------------------------------------
-- De verdad
-- ---------------------------------------------------------------------
SELECT vault.create_secret('https://plataforma.prueba/', 'crm_plataforma_url');
SELECT vault.create_secret('token-de-prueba', 'crm_envio_token');

SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
  $$SELECT crm.configurar_reciclador('11610000-0000-0000-0000-000000000001', true, false,
      12, 2, 7, 50, 'fa610001-0000-0000-0000-000000000001')$$,
  'Con la plantilla aprobada se pasa a enviar de verdad');
RESET ROLE;

SELECT is(crm.despachar_reciclaje('2026-11-20 15:00:00+00'), 2,
  'Salen el de Ana (otro silencio) y el segundo de Beto');
SELECT is(
  (SELECT cuerpo -> 'origen' #>> '{}' FROM pg_temp.peticiones WHERE cuerpo ->> 'telefono' = '+573006100001'),
  'reciclador', 'La petición dice que viene del reciclador (la plataforma no anota relevo)');
SELECT is(
  (SELECT cuerpo #>> '{plantilla,variables,nombre}' FROM pg_temp.peticiones WHERE cuerpo ->> 'telefono' = '+573006100001'),
  'Ana', 'Y lleva la variable nombre para Meta');
SELECT is(
  (SELECT e.estado FROM crm.envios e
     JOIN crm.reciclador_intentos i ON i.envio_id = e.id
    WHERE i.contacto_id = 'c0610000-0000-0000-0000-000000000001' AND NOT i.simulado),
  'pendiente', 'Queda un envío pendiente enlazado al intento');

-- La plataforma contesta 409: el canal está roto.
INSERT INTO net._http_response (id, status_code, content)
SELECT e.solicitud_http, 409, '{"ok": false, "error": "La línea no tiene credencial"}'
  FROM crm.envios e
  JOIN crm.reciclador_intentos i ON i.envio_id = e.id
 WHERE i.contacto_id = 'c0610000-0000-0000-0000-000000000001' AND NOT i.simulado;

SELECT is(crm.anotar_respuestas_plataforma(), 1, 'Se anota la respuesta de la plataforma');
SELECT is(
  (SELECT count(*)::int FROM crm.reciclador_intentos
    WHERE contacto_id = 'c0610000-0000-0000-0000-000000000001' AND NOT simulado),
  0, 'Con el canal roto no salió nada: el intento no cuenta');
SELECT matches(
  (SELECT CASE WHEN activo THEN 'encendido' ELSE ultimo_aviso END
     FROM crm.reciclador_config WHERE linea_id = '11610000-0000-0000-0000-000000000001'),
  '^Se apagó: la plataforma respondió 409',
  'Y el reciclador se apaga con el motivo');

SELECT * FROM finish();
ROLLBACK;
