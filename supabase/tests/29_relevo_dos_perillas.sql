-- =====================================================================
-- Las dos perillas del relevo: mover una no mueve la otra.
--
-- Hasta el 1 oct, crm.ventana_relevo() era a la vez la ventana del relevo
-- y el filtro de frescura de registrar_relevo. El autor del brief pidió
-- separarlas: si la ventana bajara a 2 h, un eco demorado 3 h dejaría de
-- contar como relevo sin que nadie lo hubiera decidido.
--
-- Comparar los valores de las dos funciones no prueba nada: los dos eran
-- 6 h (hasta el 26 oct, cuando la ventana bajó a 1 h) y lo habrían
-- seguido siendo aunque una llamara a la otra. Esta prueba
-- MUEVE cada perilla dentro de la transacción y mira qué cambia en el
-- comportamiento, que es lo único que importa.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(15);

DELETE FROM crm.contactos;
DELETE FROM crm.lineas;

INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre)
VALUES ('11111111-1111-1111-1111-111111111111', 'comercial', '290000000000001', 'Comercial');

INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164)
VALUES
  ('c0290001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Eco demorado', '+573005551001'),
  ('c0290002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'Mensaje viejo', '+573005551002');

-- --- Las dos perillas, y quién puede leerlas -------------------------
SELECT is(crm.frescura_relevo(), interval '6 hours',
  'La frescura del relevo arranca en 6 h');

SELECT is(crm.ventana_relevo(), interval '30 minutes',
  'Y la ventana en 30 min desde el 26 oct: bajarla no movió la frescura');

SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$SELECT crm.frescura_relevo()$$,
  '42501', NULL,
  'Un usuario logueado NO puede leer la frescura: solo la usa registrar_relevo, que corre como su dueño'
);

SELECT lives_ok(
  $$SELECT crm.ventana_relevo()$$,
  'La ventana sí sigue abierta: la necesita bot_vuelve_at, que corre con el rol de quien mira la ficha'
);

RESET ROLE;

-- =====================================================================
-- A · Bajar la VENTANA a 2 h no estrecha la frescura
--
-- El caso que motivó la separación: un eco que llega con 4 horas de
-- retraso. Con una sola perilla en 2 h se habría descartado, y el bot le
-- habría hablado encima a una persona que acababa de escribirle.
-- =====================================================================
CREATE OR REPLACE FUNCTION crm.ventana_relevo()
RETURNS interval LANGUAGE sql IMMUTABLE SET search_path = ''
AS $$ SELECT interval '2 hours'; $$;

SELECT is(crm.frescura_relevo(), interval '6 hours',
  'Con la ventana en 2 h, la frescura sigue en 6 h');

SET LOCAL ROLE service_role;

-- Desde el 26 oct un relevo no nace vencido: un eco más viejo que la
-- ventana no calla al bot para devolverle la voz en la siguiente pasada.
SELECT ok(
  NOT crm.registrar_relevo('290000000000001', '573005551001', now() - interval '4 hours'),
  'Un eco de hace 4 h no abre relevo con la ventana en 2 h: nacería vencido'
);

SELECT ok(
  crm.registrar_relevo('290000000000001', '573005551001', now() - interval '90 minutes'),
  'Uno de hace hora y media sí: está dentro de la ventana y de la frescura'
);

RESET ROLE;

SELECT is(
  (SELECT bot_motivo FROM crm.contactos WHERE id = 'c0290001-0000-0000-0000-000000000001'),
  'relevo',
  'Y el bot se calla, que es lo que tenía que pasar'
);

-- La ventana SÍ se movió donde tenía que moverse: la hora de vuelta y el
-- cron ya usan 2 h. Sin esto, la prueba no distinguiría "la frescura no
-- se movió" de "nada se movió".
SELECT is(
  crm.bot_vuelve_at('c0290001-0000-0000-0000-000000000001'),
  (SELECT bot_cambiado_at + interval '2 hours' FROM crm.contactos
    WHERE id = 'c0290001-0000-0000-0000-000000000001'),
  'La hora de vuelta que enseña la ficha sí usa la ventana nueva'
);

UPDATE crm.contactos SET bot_cambiado_at = now() - interval '3 hours'
 WHERE id = 'c0290001-0000-0000-0000-000000000001';

SELECT ok(
  crm.reactivar_relevos() >= 1,
  'Y el cron le devuelve la voz al bot: 3 h sin mensajes del equipo supera una ventana de 2 h'
);

SELECT ok(
  (SELECT bot_activo FROM crm.contactos WHERE id = 'c0290001-0000-0000-0000-000000000001'),
  'El bot vuelve a hablarle'
);

-- =====================================================================
-- B · Bajar la FRESCURA a 1 h no estrecha la ventana
-- =====================================================================
CREATE OR REPLACE FUNCTION crm.ventana_relevo()
RETURNS interval LANGUAGE sql IMMUTABLE SET search_path = ''
AS $$ SELECT interval '6 hours'; $$;

CREATE OR REPLACE FUNCTION crm.frescura_relevo()
RETURNS interval LANGUAGE sql IMMUTABLE SET search_path = ''
AS $$ SELECT interval '1 hour'; $$;

SELECT is(crm.ventana_relevo(), interval '6 hours',
  'Con la frescura en 1 h, la ventana sigue en 6 h');

SET LOCAL ROLE service_role;

SELECT ok(
  NOT crm.registrar_relevo('290000000000001', '573005551002', now() - interval '2 hours'),
  'Un mensaje de hace 2 h ya NO cuenta como relevo: la frescura bajó a 1 h'
);

SELECT ok(
  crm.registrar_relevo('290000000000001', '573005551002', now() - interval '30 minutes'),
  'Uno de hace media hora sí'
);

RESET ROLE;

SELECT is(
  crm.bot_vuelve_at('c0290002-0000-0000-0000-000000000002'),
  (SELECT bot_cambiado_at + interval '6 hours' FROM crm.contactos
    WHERE id = 'c0290002-0000-0000-0000-000000000002'),
  'Y su ventana sigue siendo de 6 h: bajar la frescura no acortó el relevo'
);

SELECT * FROM finish();
ROLLBACK;
