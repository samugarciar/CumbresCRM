-- =====================================================================
-- Aislamiento y permisos del esquema `crm`.
--
-- Hereda la lección de la fase 0-B: en `public` las políticas están
-- declaradas TO public y lo único que deja fuera a un anónimo es que
-- auth.uid() sea nulo. En `crm` se corta antes — sin USAGE sobre el
-- esquema — y aquí se comprueba que siga así.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(14);

-- Datos de partida: un contacto por inmobiliaria. Se insertan como
-- postgres (superusuario, salta la RLS) para montar el escenario.
INSERT INTO crm.contactos (id, inmobiliaria_id, telefono_e164, telefono_crudo, nombre)
VALUES
  ('c1111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111',
   '+573001110001', '3001110001', 'Cliente de Alfa'),
  ('c2222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222',
   '+573002220002', '3002220002', 'Cliente de Beta');

-- ---------------------------------------------------------------------
-- Permisos a nivel de esquema
-- ---------------------------------------------------------------------
SELECT ok(
  NOT has_schema_privilege('anon', 'crm', 'USAGE'),
  'Un anónimo no tiene USAGE sobre el esquema crm: no puede ni nombrar sus tablas'
);

SELECT ok(
  has_schema_privilege('authenticated', 'crm', 'USAGE'),
  'Un usuario con sesión sí puede usar el esquema crm'
);

-- ---------------------------------------------------------------------
-- Aislamiento entre inmobiliarias
-- ---------------------------------------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is((SELECT count(*) FROM crm.contactos), 1::bigint,
  'Alfa ve exactamente 1 contacto: el suyo');

SELECT is((SELECT count(*) FROM crm.contactos
           WHERE id = 'c2222222-2222-2222-2222-222222222222'), 0::bigint,
  'Alfa no alcanza el contacto de Beta ni pidiéndolo por su id exacto');

SELECT throws_ok(
  $$INSERT INTO crm.contactos (inmobiliaria_id, telefono_e164)
    VALUES ('22222222-2222-2222-2222-222222222222', '+573009998888')$$,
  '42501', NULL,
  'Alfa no puede crear un contacto dentro de la inmobiliaria de Beta'
);

RESET ROLE;

SET LOCAL "request.jwt.claims" = '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is((SELECT count(*) FROM crm.contactos), 1::bigint,
  'Beta ve exactamente 1 contacto: el suyo');

SELECT is((SELECT count(*) FROM crm.contactos
           WHERE telefono_e164 = '+573001110001'), 0::bigint,
  'Beta no puede leer el teléfono del cliente de Alfa');

RESET ROLE;

-- ---------------------------------------------------------------------
-- Permisos por rol: borrar es solo de admin
-- ---------------------------------------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is((SELECT count(*) FROM crm.contactos), 1::bigint,
  'Un asesor SÍ ve los contactos de su inmobiliaria — el CRM es memoria compartida');

-- Sutileza que conviene tener escrita: cuando la RLS impide un DELETE,
-- Postgres NO lanza error — simplemente no encuentra filas que borrar.
-- Por eso se comprueba en dos pasos: que no reviente, y que la fila siga.
SELECT lives_ok(
  $$DELETE FROM crm.contactos WHERE id = 'c1111111-1111-1111-1111-111111111111'$$,
  'El DELETE de un asesor no lanza error: la RLS lo deja sin filas, no lo rechaza'
);

RESET ROLE;

SELECT is(
  (SELECT count(*) FROM crm.contactos
   WHERE id = 'c1111111-1111-1111-1111-111111111111'),
  1::bigint,
  'Y el contacto sigue ahí: la política de DELETE exige rol admin'
);

-- ---------------------------------------------------------------------
-- Integridad de la llave natural
-- ---------------------------------------------------------------------
SELECT throws_ok(
  $$INSERT INTO crm.contactos (inmobiliaria_id, telefono_e164)
    VALUES ('11111111-1111-1111-1111-111111111111', '+573001110001')$$,
  '23505', NULL,
  'El mismo teléfono no se puede repetir dentro de una inmobiliaria'
);

SELECT lives_ok(
  $$INSERT INTO crm.contactos (inmobiliaria_id, telefono_e164)
    VALUES ('22222222-2222-2222-2222-222222222222', '+573001110001')$$,
  'El mismo teléfono SÍ puede existir en dos inmobiliarias distintas: son bases separadas'
);

-- El punto del índice parcial: los contactos sin llave no se estorban.
SELECT lives_ok(
  $$INSERT INTO crm.contactos (inmobiliaria_id, telefono_e164, telefono_crudo, nombre)
    VALUES ('11111111-1111-1111-1111-111111111111', NULL, '32001234567', 'Dudoso uno'),
           ('11111111-1111-1111-1111-111111111111', NULL, 'llamar al fijo', 'Dudoso dos')$$,
  'Dos contactos sin teléfono normalizado conviven: el índice único es parcial'
);

SELECT throws_ok(
  $$INSERT INTO crm.contactos (inmobiliaria_id, telefono_e164)
    VALUES ('11111111-1111-1111-1111-111111111111', '3001234567')$$,
  '23514', NULL,
  'La columna solo admite E.164 con el más delante, no un número pelado'
);

SELECT * FROM finish();
ROLLBACK;
