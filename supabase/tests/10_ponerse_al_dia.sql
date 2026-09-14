-- =====================================================================
-- "Ponerse al día": marcas de lectura y hechos duros.
--
-- Lo que se mide: que cada quien vea SUS lecturas y no las de otro, que
-- el contador de no leídos cuente bien, y que los hechos del resumen
-- salgan de contar actividades y no de adivinar.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(11);

DELETE FROM crm.contactos;

INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164)
VALUES ('dd000001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', 'Persona Alfa', '+573001110001');

-- Tres hechos, escalonados en el tiempo.
INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, metadata)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
   'dd000001-0000-0000-0000-000000000001', 'Hola, me interesa',
   now() - interval '3 hours', '{"origen_tabla":"t","origen_id":"1"}'),
  ('11111111-1111-1111-1111-111111111111', 'mensaje_saliente', 'agente_ia',
   'dd000001-0000-0000-0000-000000000001', 'Con gusto',
   now() - interval '2 hours', '{"origen_tabla":"t","origen_id":"2"}'),
  ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
   'dd000001-0000-0000-0000-000000000001', '¿Sigue disponible?',
   now() - interval '1 hour', '{"origen_tabla":"t","origen_id":"3"}');

SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

-- --- Sin haber leído nunca -------------------------------------------
SELECT is(
  (SELECT sin_leer FROM crm.resumen_contacto('dd000001-0000-0000-0000-000000000001')),
  3::bigint,
  'Sin marca de lectura, todo está sin leer'
);

SELECT is(
  (SELECT visto_hasta FROM crm.resumen_contacto('dd000001-0000-0000-0000-000000000001')),
  NULL,
  'Y no hay "visto hasta": nunca se abrió la ficha'
);

-- --- Los hechos duros -------------------------------------------------
SELECT is(
  (SELECT mensajes_cliente FROM crm.resumen_contacto('dd000001-0000-0000-0000-000000000001')),
  2::bigint,
  'Cuenta los mensajes del cliente'
);

SELECT is(
  (SELECT mensajes_bot FROM crm.resumen_contacto('dd000001-0000-0000-0000-000000000001')),
  1::bigint,
  'Y los del bot por separado — no son lo mismo al leer una conversación'
);

-- LA AFIRMACIÓN QUE MÁS IMPORTA de este archivo: el cliente escribió
-- hace una hora y solo le contestó el bot. Eso es una persona esperando.
SELECT ok(
  (SELECT esperando_segundos FROM crm.resumen_contacto('dd000001-0000-0000-0000-000000000001'))
    BETWEEN 3500 AND 3700,
  'Lleva ~1 hora esperando: contestó el bot, no una persona'
);

-- --- Marcar como leído ------------------------------------------------
SELECT lives_ok(
  $$SELECT crm.marcar_leido('dd000001-0000-0000-0000-000000000001')$$,
  'Marcar como leído funciona'
);

SELECT is(
  (SELECT sin_leer FROM crm.resumen_contacto('dd000001-0000-0000-0000-000000000001')),
  0::bigint,
  'Tras abrir la ficha ya no queda nada sin leer'
);

-- Llega un hecho nuevo después de haber leído.
RESET ROLE;
INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, metadata)
VALUES ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
        'dd000001-0000-0000-0000-000000000001', 'Buenas?',
        now() + interval '1 minute', '{"origen_tabla":"t","origen_id":"4"}');

SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT sin_leer FROM crm.resumen_contacto('dd000001-0000-0000-0000-000000000001')),
  1::bigint,
  'Un hecho posterior a tu última visita vuelve a contar como nuevo'
);

SELECT is(
  (SELECT sin_leer FROM crm.bandeja_contactos()
    WHERE id = 'dd000001-0000-0000-0000-000000000001'),
  1::bigint,
  'Y la bandeja lo refleja sin que haya que abrir la ficha'
);

-- --- Aislamiento entre personas ---------------------------------------
-- Lo leído es de cada quien. Que un asesor herede el "ya visto" de otro
-- sería justo lo contrario de lo que esta capa viene a resolver.
RESET ROLE;
SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT sin_leer FROM crm.resumen_contacto('dd000001-0000-0000-0000-000000000001')),
  4::bigint,
  'Para OTRO usuario está todo sin leer: la lectura no se hereda'
);

SELECT is(
  (SELECT count(*) FROM crm.lecturas),
  0::bigint,
  'Y ni siquiera ve las marcas de lectura ajenas'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
