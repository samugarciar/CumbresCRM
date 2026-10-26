-- =====================================================================
-- El chat en vivo (25 oct 2026).
--
-- Lo que importa:
--  · crm.actividades está en la publicación de Realtime, y es la única
--    tabla del CRM que está: publicar otra es decidirlo, no un descuido;
--  · Realtime filtra con la misma política que la lectura, así que un
--    asesor de otra inmobiliaria no ve la fila (se comprueba con su JWT).
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(4);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND schemaname = 'crm' AND tablename = 'actividades'
  ),
  'crm.actividades está en supabase_realtime'
);

SELECT is(
  (SELECT array_agg(tablename::text ORDER BY tablename)
     FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'crm'),
  ARRAY['actividades'],
  'del CRM solo se publica crm.actividades'
);

-- Una nota en Alfa, y alguien de Beta intentando verla.
INSERT INTO crm.actividades (inmobiliaria_id, inmueble_id, tipo, origen, cuerpo)
SELECT '11111111-1111-1111-1111-111111111111', i.id, 'nota', 'humano', 'Solo para Alfa'
  FROM public.inmuebles i
 WHERE i.inmobiliaria_id = '11111111-1111-1111-1111-111111111111'
 LIMIT 1;

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',  -- Admin Beta, del seed
    'role', 'authenticated'
  )::text,
  true
);

SELECT is(
  (SELECT count(*)::int FROM crm.actividades WHERE cuerpo = 'Solo para Alfa'),
  0,
  'un asesor de Beta no ve la actividad de Alfa (tampoco por Realtime)'
);

-- Y el testigo: alguien de Alfa sí la ve. Sin esto, el 0 de arriba
-- también saldría si la nota no se hubiera insertado.
SELECT set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc',  -- Asesor Alfa, del seed
    'role', 'authenticated'
  )::text,
  true
);

SELECT is(
  (SELECT count(*)::int FROM crm.actividades WHERE cuerpo = 'Solo para Alfa'),
  1,
  'alguien de Alfa sí la ve'
);

SELECT * FROM finish();
ROLLBACK;
