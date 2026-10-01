-- =====================================================================
-- La cuarentena de la libreta del celular (decisión 26): construida y
-- desconectada.
--
-- Lo primero que vigila esta prueba es que NADA la alimente: ni una
-- función, ni un trigger, ni service_role. El día que Cumbres dé el visto
-- bueno legal, activarla obliga a cambiar esta prueba, y eso tiene que
-- hacerse a sabiendas.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(15);

DELETE FROM crm.lineas;

INSERT INTO crm.lineas (id, inmobiliaria_id, embudo, wa_phone_number_id, nombre)
VALUES ('c1350000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'comercial', '350000000000001', 'Comercial');

-- --- Nada la alimenta ----------------------------------------------------
SELECT is(
  (SELECT array_agg(p.proname::text ORDER BY p.proname)
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'crm' AND p.prosrc ILIKE '%contactos_importados%'),
  NULL,
  'Ninguna función de crm toca la cuarentena: sin el visto bueno legal de Cumbres, nada la alimenta'
);

SELECT is(
  (SELECT count(*)::int FROM pg_trigger t
    WHERE t.tgrelid = 'crm.contactos_importados'::regclass AND NOT t.tgisinternal),
  0,
  'Ni un trigger'
);

SELECT table_privs_are('crm', 'contactos_importados', 'service_role', ARRAY['DELETE', 'SELECT'],
  'Ni la plataforma puede escribir en ella: a service_role se le retiró el INSERT');

SET LOCAL ROLE service_role;

SELECT throws_ok(
  $$INSERT INTO crm.contactos_importados (inmobiliaria_id, linea_id, telefono_crudo)
    VALUES ('11111111-1111-1111-1111-111111111111', 'c1350000-0000-0000-0000-000000000001', '573001112233')$$,
  '42501', NULL,
  'Y si lo intenta, falla'
);

RESET ROLE;

SELECT table_privs_are('crm', 'contactos_importados', 'authenticated', ARRAY['DELETE', 'SELECT'],
  'Un usuario logueado tampoco escribe: solo lee y borra, y la RLS dice quién');

SELECT table_privs_are('crm', 'contactos_importados', 'anon', ARRAY[]::text[],
  'Un anónimo, nada');

-- --- La forma, con datos puestos a mano desde aquí ------------------------
-- Solo el dueño de la tabla (la migración, esta prueba) puede insertar.
INSERT INTO crm.contactos_importados
  (inmobiliaria_id, linea_id, telefono_crudo, telefono_e164, nombre, nombre_corto, meta_at)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'c1350000-0000-0000-0000-000000000001',
   '573001112233', '+573001112233', 'Mamá', 'Mamá', now() - interval '1 day');

SELECT throws_ok(
  $$INSERT INTO crm.contactos_importados (inmobiliaria_id, linea_id, telefono_crudo)
    VALUES ('11111111-1111-1111-1111-111111111111', 'c1350000-0000-0000-0000-000000000001', '573001112233')$$,
  '23505', NULL,
  'El mismo número en la misma libreta no se duplica'
);

SELECT throws_ok(
  $$INSERT INTO crm.contactos_importados (inmobiliaria_id, linea_id, telefono_crudo, promovido_at, promovido_como)
    VALUES ('11111111-1111-1111-1111-111111111111', 'c1350000-0000-0000-0000-000000000001',
            '573009998877', now(), 'manual')$$,
  '23514', NULL,
  'Una promoción manual sin autor se rechaza: "alguien lo revisó" es una persona'
);

SELECT throws_ok(
  $$INSERT INTO crm.contactos_importados (inmobiliaria_id, linea_id, telefono_crudo, promovido_como)
    VALUES ('11111111-1111-1111-1111-111111111111', 'c1350000-0000-0000-0000-000000000001',
            '573009998866', 'coincidencia')$$,
  '23514', NULL,
  'Ni promovido a medias'
);

-- --- Quién la ve -----------------------------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM crm.contactos_importados),
  1,
  'El admin de Alfa ve la libreta importada de su línea'
);

RESET ROLE;
SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM crm.contactos_importados),
  0,
  'Un asesor de Alfa NO: es la libreta personal de alguien del equipo'
);

RESET ROLE;
SET LOCAL "request.jwt.claims" = '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM crm.contactos_importados),
  0,
  'Ni el admin de Beta'
);

RESET ROLE;

-- --- Borrar siempre se puede -----------------------------------------------
SET LOCAL ROLE service_role;

SELECT lives_ok(
  $$DELETE FROM crm.contactos_importados WHERE telefono_crudo = '573001112233'$$,
  'La plataforma sí puede borrar: retirar datos personales nunca se bloquea'
);

RESET ROLE;

INSERT INTO crm.contactos_importados (inmobiliaria_id, linea_id, telefono_crudo)
VALUES ('11111111-1111-1111-1111-111111111111', 'c1350000-0000-0000-0000-000000000001', '573004445566');

SELECT lives_ok(
  $$DELETE FROM crm.lineas WHERE id = 'c1350000-0000-0000-0000-000000000001'$$,
  'Una línea con libreta importada se deja borrar'
);

SELECT is(
  (SELECT count(*)::int FROM crm.contactos_importados),
  0,
  'Y borrar la línea borra su libreta: no se guarda la libreta de un celular desconectado'
);

SELECT * FROM finish();
ROLLBACK;
