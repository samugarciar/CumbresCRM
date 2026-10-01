-- =====================================================================
-- crm.intentos_incorporacion: dos cerrojos, y una sola puerta.
--
-- La puerta es crm.registrar_intento_incorporacion(), que retira los
-- tokens. Esta prueba comprueba que no hay otra: ni un usuario con
-- sesión, ni la plataforma con service_role, pueden escribir directo.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(7);

SELECT table_privs_are('crm', 'intentos_incorporacion', 'authenticated', ARRAY['SELECT'],
  'Un usuario logueado solo puede leer: se retiró el permiso de escritura que regala el esquema');

SELECT table_privs_are('crm', 'intentos_incorporacion', 'service_role', ARRAY['SELECT'],
  'La plataforma tampoco escribe directo: su única puerta es la función');

SELECT table_privs_are('crm', 'intentos_incorporacion', 'anon', ARRAY[]::text[],
  'Un anónimo, nada');

SET LOCAL ROLE service_role;

SELECT throws_ok(
  $$INSERT INTO crm.intentos_incorporacion (inmobiliaria_id, embudo, resultado, error_codigo, error)
    VALUES ('11111111-1111-1111-1111-111111111111', 'comercial', 'error', '190',
            '{"token":"EAAGm0PX4ZCpsBAKZBzQ9xyzQ7ZB1ejemplo0de0token0ZD"}')$$,
  '42501', NULL,
  'Si la plataforma intenta insertar directo —saltándose la retirada del token—, falla'
);

SELECT lives_ok(
  $$SELECT crm.registrar_intento_incorporacion(
      '11111111-1111-1111-1111-111111111111', 'comercial', 'error', '190',
      '{"token":"EAAGm0PX4ZCpsBAKZBzQ9xyzQ7ZB1ejemplo0de0token0ZD"}')$$,
  'Por la función sí: corre como su dueño y no necesita el permiso'
);

SELECT is(
  (SELECT error->>'token' FROM crm.intentos_incorporacion WHERE error_codigo = '190'),
  '[token retirado]',
  'Y por la función el token se retira'
);

SELECT lives_ok(
  $$SELECT count(*) FROM crm.intentos_incorporacion$$,
  'La plataforma sigue pudiendo leer los intentos'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
