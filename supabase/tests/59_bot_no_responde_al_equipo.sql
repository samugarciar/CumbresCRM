-- =====================================================================
-- PRUEBA 59: el bot no le responde a la gente del equipo
-- (20261104100001)
--
-- Un asesor le escribe a la línea comercial desde su celular, con el
-- número que tiene en /asesores. El bot no le contesta aunque su ficha
-- diga «encendido», la oficina le escribe sin abrir relevo, la ficha sabe
-- de quién es, y si lo desactivan vuelve a ser un contacto como cualquiera.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(13);

DELETE FROM crm.lineas;

INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre)
VALUES ('11111111-1111-1111-1111-111111111111', 'comercial', '590000000000001', 'Comercial 312');

-- En /asesores el número se escribe como sea: sin 57 y con espacios.
UPDATE public.usuarios
   SET telefono = '300 555 5901', activo = true
 WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164) VALUES
  ('aaaa0059-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Asesor Alfa (celular)', '+573005555901'),
  ('aaaa0059-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'Clienta de Alfa', '+573005555902');

-- =====================================================================
-- 1 · El bot
-- =====================================================================
SELECT is(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573005555901', '590000000000001'),
  false,
  'Al asesor el bot no le responde, aunque en su ficha esté encendido'
);

SELECT is(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '573005555901', '590000000000001'),
  false,
  'Tampoco con el número escrito de otra forma'
);

SELECT is(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573005555902', '590000000000001'),
  true,
  'A la clienta sí'
);

SELECT is(
  crm.bot_puede_responder('22222222-2222-2222-2222-222222222222', '+573005555901', NULL),
  true,
  'En otra inmobiliaria ese número es un contacto más'
);

-- =====================================================================
-- 2 · El relevo
-- =====================================================================
SELECT is(
  crm.registrar_relevo('590000000000001', '+573005555901', now()),
  false,
  'Si la oficina le escribe, no se abre relevo'
);

SELECT is(
  (SELECT row(bot_activo, bot_motivo)::text FROM crm.contactos
    WHERE id = 'aaaa0059-0000-0000-0000-000000000001'),
  '(t,)',
  'Y su ficha queda como estaba'
);

SELECT is(
  (SELECT count(*)::int FROM crm.actividades
    WHERE contacto_id = 'aaaa0059-0000-0000-0000-000000000001' AND tipo = 'sistema'),
  0,
  'Sin avisos de «el bot deja de / vuelve a responderle» en su historial'
);

SELECT is(
  crm.registrar_relevo('590000000000001', '+573005555902', now()),
  true,
  'Con la clienta el relevo funciona como siempre'
);

-- =====================================================================
-- 3 · La ficha
-- =====================================================================
SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;

SELECT is(
  crm.del_equipo('aaaa0059-0000-0000-0000-000000000001'),
  'Asesor Alfa',
  'La ficha sabe de quién del equipo es el número'
);

SELECT is(
  crm.del_equipo('aaaa0059-0000-0000-0000-000000000002'),
  NULL,
  'De la clienta, de nadie'
);

SELECT throws_ok(
  $$SELECT crm.telefono_del_equipo('11111111-1111-1111-1111-111111111111', '+573005555901')$$,
  '42501',
  NULL,
  'La pregunta de sistema no se llama desde el navegador'
);

-- =====================================================================
-- 4 · Desactivado, vuelve a ser un contacto como cualquiera
-- =====================================================================
RESET ROLE;
UPDATE public.usuarios SET activo = false WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

SELECT is(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573005555901', '590000000000001'),
  true,
  'Al asesor desactivado el bot le vuelve a responder'
);

SELECT is(
  crm.registrar_relevo('590000000000001', '+573005555901', now()),
  true,
  'Y el relevo lo vuelve a callar cuando la oficina le escribe'
);

SELECT * FROM finish();
ROLLBACK;
