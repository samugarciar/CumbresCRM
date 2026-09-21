-- =====================================================================
-- La prueba más importante del proyecto: que una inmobiliaria no pueda
-- ver NADA de otra. El CRM va a concentrar datos personales de clientes
-- (nombres, teléfonos, conversaciones), así que un fallo de RLS aquí no
-- es un bug de funcionalidad: es una fuga de datos.
--
-- Los datos vienen de supabase/seed.sql: Alfa (1111…) y Beta (2222…).
-- Se simula la sesión igual que lo hace PostgREST en producción: rol
-- `authenticated` + el claim `sub` del JWT, que es lo que lee auth.uid().
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(12);

-- ---------------------------------------------------------------------
-- Sesión de Alfa
-- ---------------------------------------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*) FROM inmuebles),
  1::bigint,
  'Alfa ve exactamente 1 inmueble: el suyo'
);

SELECT is(
  (SELECT count(*) FROM inmuebles WHERE inmobiliaria_id = '22222222-2222-2222-2222-222222222222'),
  0::bigint,
  'Alfa no ve NINGÚN inmueble de Beta, ni filtrando por su inmobiliaria_id'
);

-- Se afirma AISLAMIENTO, no un número exacto. Antes decía "Alfa ve 1
-- cita" y eso ataba la prueba a cuántas filas trae el seed hoy: cargar
-- el fixture del histórico la hacía fallar sin que nada estuviera roto.
-- Una prueba que grita cuando no pasa nada acaba ignorándose, y ese es
-- el día en que deja de avisar de lo que sí importa.
SELECT ok(
  (SELECT count(*) FROM citas) > 0,
  'Alfa ve citas'
);

SELECT is(
  (SELECT count(*) FROM citas WHERE inmobiliaria_id = '22222222-2222-2222-2222-222222222222'),
  0::bigint,
  'Alfa no ve las citas de Beta'
);

-- Alfa tiene dos: Admin Alfa y Asesor Alfa. Lo que importa es que no
-- aparezca ninguno de Beta.
SELECT is(
  (SELECT count(*) FROM usuarios),
  2::bigint,
  'Alfa ve los 2 usuarios de su inmobiliaria, y solo esos'
);

SELECT is(
  (SELECT count(*) FROM inmobiliarias),
  1::bigint,
  'Alfa ve solo su propia inmobiliaria'
);

RESET ROLE;

-- ---------------------------------------------------------------------
-- Sesión de Beta — el espejo, para descartar que el aislamiento funcione
-- por casualidad en una sola dirección
-- ---------------------------------------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*) FROM inmuebles),
  1::bigint,
  'Beta ve exactamente 1 inmueble: el suyo'
);

SELECT is(
  (SELECT count(*) FROM inmuebles WHERE id = 'a1111111-1111-1111-1111-111111111111'),
  0::bigint,
  'Beta no alcanza el inmueble de Alfa ni pidiéndolo por su id exacto'
);

SELECT is(
  (SELECT count(*) FROM citas WHERE cliente_telefono = '+573000000001'),
  0::bigint,
  'Beta no puede leer el teléfono del cliente de Alfa'
);

RESET ROLE;

-- ---------------------------------------------------------------------
-- Visitante sin sesión (rol `anon`)
--
-- LIMPIAR LAS CLAIMS ES OBLIGATORIO, y no es un detalle de la prueba.
-- Las políticas de esta base están declaradas `TO public`, así que
-- TAMBIÉN se evalúan para el rol `anon`. Lo único que deja a un anónimo
-- fuera es que `auth.uid()` sea NULO. Si aquí no se borraran las claims
-- de Beta, seguirían vivas en la transacción, `auth.uid()` devolvería a
-- Beta y un "anónimo" vería sus citas — que es exactamente lo que pasó la
-- primera vez que se corrió esta prueba.
--
-- auth.uid() hace nullif(current_setting(...), ''), así que la cadena
-- vacía es la forma de simular "sin sesión".
--
-- ACTUALIZADO EL 21 SEP 2026, y el cambio cuenta algo.
--
-- Esta prueba afirmaba que `anon` SÍ tenía el GRANT sobre citas y que lo
-- paraba la RLS — la distinción entre "tener permiso sobre la tabla" y
-- "que una política te deje ver filas". Era cierto cuando se escribió.
--
-- Al regenerar la línea base desde producción se vio que ya no: el
-- permiso está REVOCADO. La garantía se volvió más fuerte, porque el
-- corte ocurre antes de llegar a la RLS. Lo que había en local era un
-- esquema más laxo que el real, y la prueba estaba midiendo contra él.
-- ---------------------------------------------------------------------
SELECT ok(
  NOT has_table_privilege('anon', 'public.citas', 'SELECT'),
  'Un anónimo ni siquiera puede leer la tabla de citas: el corte es ANTES de la RLS'
);

SET LOCAL "request.jwt.claims" = '';
SET LOCAL ROLE anon;

SELECT throws_ok(
  $$SELECT count(*) FROM citas$$,
  '42501',
  NULL,
  'Y si lo intenta, le responde el permiso, no la política'
);

RESET ROLE;

SELECT ok(
  NOT has_table_privilege('anon', 'public.inmuebles', 'SELECT'),
  'Un anónimo ni siquiera tiene permiso de lectura sobre inmuebles'
);

SELECT * FROM finish();
ROLLBACK;
