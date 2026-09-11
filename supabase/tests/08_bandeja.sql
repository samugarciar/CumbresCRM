-- =====================================================================
-- crm.bandeja_contactos — la consulta que sirve la pantalla principal.
--
-- Lo que se mide aquí: que busque como espera una persona (tolerando
-- erratas y formatos de teléfono), que los filtros filtren, que la
-- paginación no repita ni salte filas, y sobre todo QUE NO SE SALTE LA
-- RLS. Una búsqueda con fuga es una fuga con formulario.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(10);

DELETE FROM crm.contactos;

-- Alfa: cinco personas con fechas escalonadas, para poder paginar.
INSERT INTO crm.contactos
  (id, inmobiliaria_id, nombre, telefono_e164, tipo, ultima_actividad_at)
VALUES
  ('aa000001-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',
   'John Restrepo',  '+573001110001','cliente',     now() - interval '1 hour'),
  ('aa000002-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111',
   'Marcela Gómez',  '+573001110002','cliente',     now() - interval '2 hours'),
  ('aa000003-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111',
   'Pedro Arango',   '+573001110003','propietario', now() - interval '3 hours'),
  ('aa000004-0000-0000-0000-000000000004','11111111-1111-1111-1111-111111111111',
   'Sin Numero',      NULL,          'cliente',     now() - interval '4 hours'),
  ('aa000005-0000-0000-0000-000000000005','11111111-1111-1111-1111-111111111111',
   'Ana Velez',      '+573001110005','cliente',     now() - interval '5 hours');

-- Beta: una persona con un nombre muy buscable, para probar aislamiento.
INSERT INTO crm.contactos
  (id, inmobiliaria_id, nombre, telefono_e164, tipo, ultima_actividad_at)
VALUES
  ('bb000001-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222',
   'John Restrepo', '+573009990001','cliente', now());

SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

-- --- Búsqueda ---------------------------------------------------------
-- El fallo de escritura que de verdad ocurre aquí son los acentos.
SELECT is(
  (SELECT nombre FROM crm.bandeja_contactos('Gomez')),
  'Marcela Gómez',
  'Buscar "Gomez" sin tilde encuentra a "Gómez"'
);

-- Y lo que NO hace, escrito a propósito para que nadie lo "mejore"
-- bajando el umbral: una transposición como "Jhon" por "John" puntúa por
-- debajo del ruido, así que se prefiere no encontrarla antes que mostrar
-- a la persona equivocada.
SELECT is(
  (SELECT count(*) FROM crm.bandeja_contactos('Ana')),
  1::bigint,
  'Buscar "Ana" trae solo a Ana Velez, no a "Pedro ArANgo" por parecido difuso'
);

SELECT is(
  (SELECT nombre FROM crm.bandeja_contactos('restrepo')),
  'John Restrepo',
  'La búsqueda por apellido no distingue mayúsculas'
);

SELECT is(
  (SELECT nombre FROM crm.bandeja_contactos('300 111 0003')),
  'Pedro Arango',
  'Buscar el teléfono con espacios funciona: se comparan solo los dígitos'
);

-- --- AISLAMIENTO: la prueba que más importa de este archivo ------------
SELECT is(
  (SELECT count(*) FROM crm.bandeja_contactos('John Restrepo')),
  1::bigint,
  'Alfa encuentra UN John Restrepo, el suyo — el de Beta no aparece pese al nombre idéntico'
);

SELECT is(
  (SELECT count(*) FROM crm.bandeja_contactos('3009990001')),
  0::bigint,
  'Ni buscando el teléfono exacto de alguien de otra inmobiliaria'
);

-- --- Filtros ----------------------------------------------------------
SELECT is(
  (SELECT count(*) FROM crm.bandeja_contactos(NULL, 'propietario')),
  1::bigint,
  'El filtro por tipo deja solo a los propietarios'
);

SELECT is(
  (SELECT nombre FROM crm.bandeja_contactos(NULL, NULL, true)),
  'Sin Numero',
  'El filtro "sin teléfono" aísla a quienes no se puede llamar'
);

-- --- Paginación por cursor --------------------------------------------
-- Que la segunda página empiece justo donde terminó la primera, sin
-- repetir ni saltarse a nadie. Con offset esto se rompe en cuanto alguien
-- escribe mientras navegas.
SELECT is(
  (SELECT array_agg(nombre ORDER BY orden_at DESC)
     FROM crm.bandeja_contactos(NULL, NULL, NULL, NULL, NULL, 2)),
  ARRAY['John Restrepo', 'Marcela Gómez'],
  'La primera página trae los dos más recientes, en orden'
);

SELECT is(
  (SELECT array_agg(b2.nombre ORDER BY b2.orden_at DESC)
     FROM (SELECT orden_at, id FROM crm.bandeja_contactos(NULL, NULL, NULL, NULL, NULL, 2)
            ORDER BY orden_at DESC, id DESC LIMIT 1 OFFSET 1) cursor1
     CROSS JOIN LATERAL crm.bandeja_contactos(
       NULL, NULL, NULL, cursor1.orden_at, cursor1.id, 2) b2),
  ARRAY['Pedro Arango', 'Sin Numero'],
  'La segunda continúa exactamente desde el cursor, sin repetir ni saltar'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
