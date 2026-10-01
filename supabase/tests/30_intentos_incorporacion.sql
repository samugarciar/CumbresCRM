-- =====================================================================
-- El registro de intentos de incorporación (decisión 28).
--
-- Lo que tiene que garantizar: que un intento fallido se guarda con el
-- error de Meta ENTERO, sin traducir; que solo la plataforma lo anota;
-- que cada inmobiliaria ve los suyos; y que un token que se cuele en el
-- error no llega nunca a la tabla.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(22);

DELETE FROM crm.intentos_incorporacion;

-- Dos errores de Meta con formas distintas, a propósito: el de la Graph
-- API y el del registro integrado del navegador. Si la tabla obligara a
-- una sola forma, uno de los dos se perdería.
CREATE TEMP TABLE errores (nombre text PRIMARY KEY, cuerpo jsonb);
INSERT INTO errores VALUES
  ('graph', '{"message":"(#2388091) Phone number is not eligible","type":"OAuthException","code":2388091,"error_subcode":2388092,"fbtrace_id":"AbCdEf123"}'),
  ('registro', '{"error_message":"The phone number is already registered to another account","error_id":524126,"session_id":"f1a2b3c4","timestamp":"1727800000"}');
GRANT SELECT ON errores TO authenticated, service_role;

SET LOCAL ROLE service_role;

-- --- Lo que se guarda --------------------------------------------------
SELECT ok(
  crm.registrar_intento_incorporacion(
    '11111111-1111-1111-1111-111111111111', 'comercial', 'error',
    '2388091', (SELECT cuerpo FROM errores WHERE nombre = 'graph'),
    '300000000000001', '400000000000001',
    now() - interval '10 minutes') IS NOT NULL,
  'La plataforma anota un intento fallido y recibe su id'
);

SELECT is(
  (SELECT error FROM crm.intentos_incorporacion WHERE error_codigo = '2388091'),
  (SELECT cuerpo FROM errores WHERE nombre = 'graph'),
  'El error de la Graph API se guarda ENTERO, con su subcódigo y su fbtrace_id'
);

SELECT lives_ok(
  $$SELECT crm.registrar_intento_incorporacion(
      '11111111-1111-1111-1111-111111111111', 'administrativa', 'error',
      '524126', (SELECT cuerpo FROM errores WHERE nombre = 'registro'))$$,
  'Y el del registro integrado, que tiene otra forma, también entra'
);

SELECT is(
  (SELECT error->>'error_message' FROM crm.intentos_incorporacion WHERE error_codigo = '524126'),
  'The phone number is already registered to another account',
  'Sin traducir: el mensaje sigue en inglés, como lo mandó Meta'
);

SELECT is(
  (SELECT ocurrido_at FROM crm.intentos_incorporacion WHERE error_codigo = '2388091'),
  now() - interval '10 minutes',
  'El momento es el que dio la plataforma, no el de la anotación'
);

SELECT lives_ok(
  $$SELECT crm.registrar_intento_incorporacion(
      '11111111-1111-1111-1111-111111111111', 'captacion', 'cancelado')$$,
  'Un intento cancelado puede no traer error: la persona cerró la ventana'
);

-- Un reloj adelantado en la plataforma no puede fechar un intento en el
-- futuro: lo pondría encima de los que de verdad pasaron después.
SELECT lives_ok(
  $$SELECT crm.registrar_intento_incorporacion(
      '11111111-1111-1111-1111-111111111111', 'administrativa', 'cancelado',
      p_ocurrido_at => now() + interval '1 day')$$,
  'Un intento fechado en el futuro no se rechaza: se anota'
);

SELECT ok(
  (SELECT ocurrido_at <= now() FROM crm.intentos_incorporacion
    WHERE embudo = 'administrativa' AND resultado = 'cancelado'),
  'Un intento fechado mañana se anota con la hora de ahora'
);

SELECT lives_ok(
  $$SELECT crm.registrar_intento_incorporacion(
      '11111111-1111-1111-1111-111111111111', 'comercial', 'exito',
      p_wa_phone_number_id => '300000000000001')$$,
  'Un éxito se anota sin error'
);

-- --- Lo que no puede entrar -------------------------------------------
SELECT throws_ok(
  $$SELECT crm.registrar_intento_incorporacion(
      '11111111-1111-1111-1111-111111111111', 'comercial', 'error')$$,
  '23514', NULL,
  'Un error SIN el objeto de Meta se rechaza: es lo único que esta tabla tiene de valioso'
);

SELECT throws_ok(
  $$SELECT crm.registrar_intento_incorporacion(
      '11111111-1111-1111-1111-111111111111', 'comercial', 'exito',
      '100', '{"code":100}')$$,
  '23514', NULL,
  'Un éxito con error es una contradicción y se rechaza'
);

SELECT throws_ok(
  $$SELECT crm.registrar_intento_incorporacion(
      '11111111-1111-1111-1111-111111111111', 'comercial', 'a_medias')$$,
  '23514', NULL,
  'Un resultado que no es exito, error ni cancelado se rechaza'
);

SELECT throws_ok(
  $$SELECT crm.registrar_intento_incorporacion(
      '11111111-1111-1111-1111-111111111111', 'ventas', 'cancelado')$$,
  '23503', NULL,
  'Un embudo que no existe se rechaza'
);

-- --- El token, retirado ------------------------------------------------
-- Un fallo plausible en la plataforma: mandar el contexto de la petición
-- en vez del error, con el token dentro.
SELECT lives_ok(
  $$SELECT crm.registrar_intento_incorporacion(
      '11111111-1111-1111-1111-111111111111', 'comercial', 'error',
      '190',
      '{"code":190,"message":"Invalid OAuth access token","peticion":{"headers":{"Authorization":"Bearer EAAGm0PX4ZCpsBAKZBzQ9xyzQ7ZB1example0TOKEN0de0prueba0ZCZCZD"}}}')$$,
  'Un intento con un token dentro del error se anota igual: el intento no se pierde'
);

SELECT ok(
  (SELECT error::text !~ 'EAA[A-Za-z0-9]{30,}' AND token_retirado
     FROM crm.intentos_incorporacion WHERE error_codigo = '190'),
  'Pero el token no llega a la tabla, y la fila queda marcada'
);

SELECT is(
  (SELECT error->>'message' FROM crm.intentos_incorporacion WHERE error_codigo = '190'),
  'Invalid OAuth access token',
  'Y el resto del error sigue tal cual'
);

-- No es idempotente, a propósito.
SELECT ok(
  crm.registrar_intento_incorporacion(
    '11111111-1111-1111-1111-111111111111', 'captacion', 'cancelado') IS NOT NULL,
  'Un segundo intento igual al de antes se anota'
);

SELECT is(
  (SELECT count(*)::int FROM crm.intentos_incorporacion WHERE embudo = 'captacion'),
  2,
  'Dos intentos iguales son dos filas: cada uno se gastó sobre el número'
);

RESET ROLE;

-- --- Quién lo anota y quién lo ve -------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$SELECT crm.registrar_intento_incorporacion(
      '11111111-1111-1111-1111-111111111111', 'comercial', 'cancelado')$$,
  '42501', NULL,
  'Un asesor NO puede anotar intentos: los anota solo la plataforma'
);

SELECT throws_ok(
  $$INSERT INTO crm.intentos_incorporacion (inmobiliaria_id, embudo, resultado)
    VALUES ('11111111-1111-1111-1111-111111111111', 'comercial', 'cancelado')$$,
  '42501', NULL,
  'Ni escribiendo directo en la tabla'
);

SELECT is(
  (SELECT count(*)::int FROM crm.intentos_incorporacion),
  7,
  'Un asesor de Alfa ve los siete intentos de su inmobiliaria'
);

RESET ROLE;
SET LOCAL "request.jwt.claims" = '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM crm.intentos_incorporacion),
  0,
  'Beta no ve ninguno de Alfa'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
