-- =====================================================================
-- La bandeja de reactivación.
--
-- Lo que se mide: que NADIE que pidió salir pueda colarse en un lote
-- —es lo único de esta pantalla que no se puede deshacer—, que el orden
-- sea del más callado al menos, y que la lista diga qué pidió cada uno,
-- que es lo que la separa de una guía telefónica.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(11);

DELETE FROM crm.contactos;

INSERT INTO crm.contactos
  (id, inmobiliaria_id, nombre, telefono_e164, ultima_actividad_at,
   consentimiento, consentimiento_at, consentimiento_canal)
VALUES
  -- El más callado de todos: tiene que salir primero.
  ('ea000001-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'Cuatro meses', '+573001121111',
   now() - interval '120 days', true, now() - interval '150 days', 'whatsapp'),
  -- Callado, pero menos.
  ('ea000002-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111', 'Tres semanas', '+573001121112',
   now() - interval '21 days', true, now() - interval '60 days', 'whatsapp'),
  -- Pidió salir. No puede aparecer jamás.
  ('ea000003-0000-0000-0000-000000000003',
   '11111111-1111-1111-1111-111111111111', 'Pidió salir', '+573001121113',
   now() - interval '90 days', true, now() - interval '100 days', 'whatsapp'),
  -- Nunca consintió: nunca nos escribió.
  ('ea000004-0000-0000-0000-000000000004',
   '11111111-1111-1111-1111-111111111111', 'Nunca escribió', '+573001121114',
   now() - interval '90 days', false, NULL, NULL),
  -- Habló ayer: no está dormido.
  ('ea000005-0000-0000-0000-000000000005',
   '11111111-1111-1111-1111-111111111111', 'Habló ayer', '+573001121115',
   now() - interval '1 day', true, now() - interval '30 days', 'whatsapp');

UPDATE crm.contactos SET opt_out = true, opt_out_at = now()
 WHERE id = 'ea000003-0000-0000-0000-000000000003';

INSERT INTO crm.requerimientos
  (inmobiliaria_id, contacto_id, ciudad, barrios, tipo_inmueble,
   tipo_transaccion, precio_max, habitaciones_min)
VALUES ('11111111-1111-1111-1111-111111111111',
        'ea000001-0000-0000-0000-000000000001',
        'Bello', ARRAY['Niquia'], ARRAY['apartamento'],
        'arriendo', 1800000, 3);

-- --- Quién sale y quién no -------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM crm.reactivables(14, 50, 0)),
  2,
  'Solo los dos dormidos con consentimiento y sin opt-out'
);

SELECT is(
  (SELECT count(*)::int FROM crm.reactivables(14, 50, 0)
    WHERE contacto_id = 'ea000003-0000-0000-0000-000000000003'),
  0,
  'Quien pidió salir NO aparece: es lo único de esta pantalla que no se deshace'
);

SELECT is(
  (SELECT count(*)::int FROM crm.reactivables(14, 50, 0)
    WHERE contacto_id = 'ea000004-0000-0000-0000-000000000004'),
  0,
  'Y quien nunca nos escribió tampoco: no hay consentimiento que invocar'
);

SELECT is(
  (SELECT count(*)::int FROM crm.reactivables(14, 50, 0)
    WHERE contacto_id = 'ea000005-0000-0000-0000-000000000005'),
  0,
  'Quien habló ayer no está dormido'
);

-- --- El orden, que es la mitad del valor -----------------------------
SELECT is(
  (SELECT nombre FROM crm.reactivables(14, 50, 0) LIMIT 1),
  'Cuatro meses',
  'Primero el MÁS callado: al que lleva cuatro meses no le escribe nadie nunca'
);

-- --- Lo que pidió ----------------------------------------------------
SELECT ok(
  (SELECT busca FROM crm.reactivables(14, 50, 0)
    WHERE contacto_id = 'ea000001-0000-0000-0000-000000000001')
    LIKE '%apartamento en Niquia%',
  'La lista dice qué buscaba: sin eso es una guía telefónica'
);

SELECT ok(
  (SELECT busca FROM crm.reactivables(14, 50, 0)
    WHERE contacto_id = 'ea000001-0000-0000-0000-000000000001')
    LIKE '%3+ hab%',
  'Con el detalle que hace que el mensaje no sea genérico'
);

SELECT is(
  (SELECT busca FROM crm.reactivables(14, 50, 0)
    WHERE contacto_id = 'ea000002-0000-0000-0000-000000000002'),
  NULL,
  'Y NULL para quien nunca lo dijo: a ese hay que escribirle otra cosa'
);

-- --- Paginación y total ----------------------------------------------
SELECT is(crm.reactivables_total(14), 2, 'El total cuenta a los mismos que la lista');

SELECT is(
  (SELECT count(*)::int FROM crm.reactivables(14, 1, 1)),
  1,
  'La paginación salta: el coste es proporcional a la página, no al público'
);

-- --- El idioma de las plantillas, que Meta exige ----------------------
SELECT throws_ok(
  $$UPDATE crm.plantillas SET idioma = 'español' WHERE true$$,
  '23514',
  NULL,
  'El idioma tiene que ser un código de Meta, no una palabra'
);

SELECT * FROM finish();
ROLLBACK;
