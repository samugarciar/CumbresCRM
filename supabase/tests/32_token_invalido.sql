-- =====================================================================
-- Un token que Meta rechaza deja la línea en un estado visible, y el
-- token no aparece en ningún sitio donde lo pueda leer una persona.
-- (Ajuste a la decisión 23.)
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(21);

DELETE FROM crm.lineas;

-- Un token con la forma de los de Meta: EAA y muchos caracteres.
CREATE TEMP TABLE t (token text);
INSERT INTO t VALUES ('EAAGm0PX4ZCpsBAKZBzQ9xyzQ7ZB1ejemplo0de0token0de0prueba0ZD');
GRANT SELECT ON t TO service_role;

SELECT ok(
  crm.conectar_linea('11111111-1111-1111-1111-111111111111', 'comercial',
                     'waba-alfa', '320000000000001', 'coexistencia',
                     (SELECT token FROM t)) IS NOT NULL,
  'La línea comercial queda conectada'
);

SELECT is(
  (SELECT token_invalido_at FROM crm.lineas WHERE wa_phone_number_id = '320000000000001'),
  NULL,
  'Recién conectada, no se sabe de ningún rechazo'
);

SET LOCAL ROLE service_role;

-- --- Meta rechaza el token ---------------------------------------------
-- El mensaje viene con el token dentro: es el caso que no puede pasar.
SELECT ok(
  crm.registrar_estado_linea('320000000000001', 'token_invalido', NULL, 190,
    'Error validating access token: Session has expired (token ' || (SELECT token FROM t) || ')'),
  'La plataforma anota que Meta rechazó el token'
);

RESET ROLE;

SELECT is(
  (SELECT token_invalido_at IS NOT NULL AND token_error_codigo = 190
     FROM crm.lineas WHERE wa_phone_number_id = '320000000000001'),
  true,
  'La línea queda marcada, con el código de Meta'
);

SELECT is(
  (SELECT token_error FROM crm.lineas WHERE wa_phone_number_id = '320000000000001'),
  'Error validating access token: Session has expired (token [token retirado])',
  'El mensaje se guarda sin el token, y con todo lo demás tal cual'
);

SELECT is(
  (SELECT count(*)::int FROM crm.lineas l
    WHERE to_jsonb(l)::text LIKE '%' || (SELECT token FROM t) || '%'),
  0,
  'El token no está en ninguna columna de la línea'
);

-- --- La pantalla lo ve -------------------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT token_error_codigo FROM crm.lineas WHERE wa_phone_number_id = '320000000000001'),
  190,
  'Un asesor de Alfa ve el estado: la pantalla de líneas lo puede enseñar'
);

SELECT throws_ok(
  $$SELECT crm.registrar_estado_linea('320000000000001', 'token_valido')$$,
  '42501', NULL,
  'Pero no lo puede apagar: la alarma la limpia la plataforma o una reconexión, no un clic'
);

SELECT throws_ok(
  $$SELECT crm.retirar_token('x')$$,
  '42501', NULL,
  'Y no puede llamar a retirar_token: solo la usan funciones del sistema'
);

RESET ROLE;

-- --- El reloj es el del primer rechazo --------------------------------
UPDATE crm.lineas SET token_invalido_at = now() - interval '2 days'
 WHERE wa_phone_number_id = '320000000000001';

SET LOCAL ROLE service_role;

SELECT ok(
  crm.registrar_estado_linea('320000000000001', 'token_invalido', NULL, 190,
                             'Error validating access token: The user has not authorized application'),
  'Un segundo rechazo se anota'
);

RESET ROLE;

SELECT is(
  (SELECT token_invalido_at FROM crm.lineas WHERE wa_phone_number_id = '320000000000001'),
  now() - interval '2 days',
  'Sin reiniciar el reloj: la línea lleva dos días caída, no un minuto'
);

SELECT is(
  (SELECT token_error FROM crm.lineas WHERE wa_phone_number_id = '320000000000001'),
  'Error validating access token: The user has not authorized application',
  'El mensaje sí es el del último rechazo, que es el vigente'
);

-- --- Cómo se limpia -----------------------------------------------------
SET LOCAL ROLE service_role;

SELECT ok(
  crm.registrar_estado_linea('320000000000001', 'token_valido'),
  'La plataforma anota que la credencial volvió a funcionar'
);

RESET ROLE;

SELECT is(
  (SELECT row(token_invalido_at, token_error_codigo, token_error)::text
     FROM crm.lineas WHERE wa_phone_number_id = '320000000000001'),
  '(,,)',
  'Y la línea queda limpia'
);

SET LOCAL ROLE service_role;
SELECT ok(
  crm.registrar_estado_linea('320000000000001', 'token_invalido', NULL, 190, 'Session has expired'),
  'Otro rechazo, para probar la reconexión'
);
RESET ROLE;

SELECT ok(
  crm.conectar_linea('11111111-1111-1111-1111-111111111111', 'comercial',
                     'waba-alfa', '320000000000001', 'coexistencia',
                     'EAAG-token-nuevo') IS NOT NULL,
  'Se reconecta con un token nuevo'
);

SELECT ok(
  (SELECT token_invalido_at IS NULL AND token_error IS NULL
     FROM crm.lineas WHERE wa_phone_number_id = '320000000000001'),
  'Y reconectar limpia la alarma del token viejo'
);

-- --- El token tampoco sale por los otros caminos -----------------------
SET LOCAL ROLE service_role;

SELECT ok(
  crm.registrar_estado_linea('320000000000001', 'historial_error', NULL, 131000,
    'Something went wrong with ' || (SELECT token FROM t)),
  'Un error del historial con el token dentro se anota'
);

SELECT is(
  (SELECT historial_error FROM crm.lineas WHERE wa_phone_number_id = '320000000000001'),
  'Something went wrong with [token retirado]',
  'Pero también pasa por retirar_token'
);

SELECT throws_ok(
  format('SELECT crm.registrar_estado_linea(%L, %L)', '320000000000001', (SELECT token FROM t)),
  '22023',
  'Evento de línea desconocido: [token retirado]',
  'Ni un evento equivocado que traiga el token lo saca en el mensaje de error'
);

SELECT ok(
  NOT crm.registrar_estado_linea('999999999999999', 'token_invalido', NULL, 190, 'x'),
  'Un número sin línea devuelve false, como los demás eventos'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
