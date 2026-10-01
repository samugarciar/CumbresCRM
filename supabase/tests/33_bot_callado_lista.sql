-- =====================================================================
-- La lista de bots callados (decisión 25).
--
-- Lo que importa: que salgan TODOS, sea cual sea el motivo; que la hora
-- en que el bot vuelve solo sea la de los crones y no otra; y que no se
-- convierta en un aviso más de «Mi día».
--
-- La prueba fuerte es la de los crones: se adelanta el reloj de un lead,
-- se corre crm.reactivar_bots() y se mira que vuelva exactamente lo que
-- la lista decía que volvería, y nada de lo que decía que no.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(19);

DELETE FROM crm.contactos;

-- ALFA: los cuatro motivos posibles, más dos que NO deben salir.
INSERT INTO crm.contactos
  (id, inmobiliaria_id, nombre, telefono_e164,
   bot_activo, bot_motivo, bot_cambiado_at, bot_cambiado_por, bot_caduca, deleted_at)
VALUES
  ('c0330001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Manual', '+573003330001',
   false, 'manual', now() - interval '2 days', 'cccccccc-cccc-cccc-cccc-cccccccccccc', true, NULL),
  ('c0330002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'Escalado sin atender', '+573003330002',
   false, 'escalamiento', now() - interval '1 hour', NULL, true, NULL),
  ('c0330003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
   'Escalado atendido', '+573003330003',
   false, 'escalamiento', now() - interval '10 hours', NULL, true, NULL),
  ('c0330004-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111',
   'Escalado de antes del 1 oct', '+573003330004',
   false, 'escalamiento', now() - interval '3 days', NULL, false, NULL),
  ('c0330005-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111',
   'Relevo', '+573003330005',
   false, 'relevo', now() - interval '2 hours', NULL, true, NULL),
  ('c0330006-0000-0000-0000-000000000006', '11111111-1111-1111-1111-111111111111',
   'Bot hablando', '+573003330006',
   true, NULL, NULL, NULL, true, NULL),
  ('c0330007-0000-0000-0000-000000000007', '11111111-1111-1111-1111-111111111111',
   'Borrado', '+573003330007',
   false, 'manual', now() - interval '1 day', NULL, true, now()),
  -- BETA: uno callado, que Alfa no puede ver.
  ('b0330001-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
   'Callado de Beta', '+573003339001',
   false, 'manual', now() - interval '1 day', NULL, true, NULL);

-- Alguien del equipo dejó una nota en el escalado "atendido" DESPUÉS de
-- que el bot se callara: eso es atenderlo, y ese silencio ya no caduca.
INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, creado_por)
VALUES ('11111111-1111-1111-1111-111111111111', 'nota', 'humano',
        'c0330003-0000-0000-0000-000000000003', 'Lo llamé, quiere visitar el sábado',
        now() - interval '5 hours', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- La persona del escalado sin atender escribió dos veces.
INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
   'c0330002-0000-0000-0000-000000000002', '¿Me pueden llamar?', now() - interval '2 hours'),
  ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
   'c0330002-0000-0000-0000-000000000002', '¿Hola?', now() - interval '30 minutes');

-- Lo que ve un asesor de Alfa, en una tabla para no repetir la consulta.
SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;
CREATE TEMP TABLE vista_alfa AS SELECT * FROM crm.v_bot_callado;
RESET ROLE;

-- --- Quién sale ----------------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM vista_alfa),
  5,
  'Salen los cinco callados de Alfa: manual, escalados (tres) y relevo'
);

SELECT is(
  (SELECT array_agg(DISTINCT motivo ORDER BY motivo) FROM vista_alfa),
  ARRAY['escalamiento', 'manual', 'relevo'],
  'Sea cual sea el motivo'
);

SELECT ok(
  NOT EXISTS (SELECT 1 FROM vista_alfa
               WHERE contacto_id IN ('c0330006-0000-0000-0000-000000000006',
                                     'c0330007-0000-0000-0000-000000000007')),
  'No salen ni el que tiene el bot hablando ni el contacto borrado'
);

SELECT ok(
  NOT EXISTS (SELECT 1 FROM vista_alfa WHERE inmobiliaria_id <> '11111111-1111-1111-1111-111111111111'),
  'Ni el callado de Beta'
);

-- --- Cuándo vuelve, y por qué no ----------------------------------------
SELECT is(
  (SELECT vuelve_at FROM vista_alfa WHERE contacto_id = 'c0330002-0000-0000-0000-000000000002'),
  now() - interval '1 hour' + interval '6 hours',
  'El escalado sin atender vuelve solo a las 6 h de callarse'
);

SELECT is(
  (SELECT row(atendido, vuelve_at)::text FROM vista_alfa
    WHERE contacto_id = 'c0330003-0000-0000-0000-000000000003'),
  '(t,)',
  'El escalado que alguien atendió NO vuelve solo (decisión 25), y la lista dice por qué'
);

SELECT is(
  (SELECT row(bot_caduca, vuelve_at)::text FROM vista_alfa
    WHERE contacto_id = 'c0330004-0000-0000-0000-000000000004'),
  '(f,)',
  'El de antes del 1 oct tampoco: se dejó sin caducar a propósito'
);

SELECT is(
  (SELECT row(callado_por_nombre, vuelve_at)::text FROM vista_alfa
    WHERE contacto_id = 'c0330001-0000-0000-0000-000000000001'),
  '("Asesor Alfa",)',
  'El manual no vuelve nunca, y la lista dice quién lo calló'
);

SELECT is(
  (SELECT vuelve_at FROM vista_alfa WHERE contacto_id = 'c0330005-0000-0000-0000-000000000005'),
  crm.bot_vuelve_at('c0330005-0000-0000-0000-000000000005'),
  'El relevo vuelve a la misma hora que enseña la ficha'
);

-- --- La persona -----------------------------------------------------------
SELECT is(
  (SELECT ultimo_entrante_at FROM vista_alfa WHERE contacto_id = 'c0330002-0000-0000-0000-000000000002'),
  now() - interval '30 minutes',
  'Dice cuándo escribió la persona por última vez: el último de sus dos mensajes'
);

SELECT is(
  (SELECT ultimo_entrante_at FROM vista_alfa WHERE contacto_id = 'c0330001-0000-0000-0000-000000000001'),
  NULL,
  'Y nada si nunca escribió'
);

-- --- Las perillas son las de los crones -----------------------------------
CREATE OR REPLACE FUNCTION crm.ventana_silencio_escalamiento()
RETURNS interval LANGUAGE sql IMMUTABLE SET search_path = ''
AS $$ SELECT interval '2 hours'; $$;

SELECT is(
  (SELECT vuelve_at FROM crm.v_bot_callado WHERE contacto_id = 'c0330002-0000-0000-0000-000000000002'),
  now() - interval '1 hour' + interval '2 hours',
  'Si la perilla del escalamiento baja a 2 h, la lista lo sigue: no tiene su propio 6'
);

CREATE OR REPLACE FUNCTION crm.ventana_silencio_escalamiento()
RETURNS interval LANGUAGE sql IMMUTABLE SET search_path = ''
AS $$ SELECT interval '6 hours'; $$;

-- Se adelanta el reloj del escalado sin atender: ya le tocaría volver.
UPDATE crm.contactos SET bot_cambiado_at = now() - interval '7 hours'
 WHERE id = 'c0330002-0000-0000-0000-000000000002';

CREATE TEMP TABLE debian_volver AS
  SELECT contacto_id FROM crm.v_bot_callado
   WHERE motivo = 'escalamiento' AND vuelve_at <= now();

SELECT is(
  (SELECT array_agg(contacto_id) FROM debian_volver),
  ARRAY['c0330002-0000-0000-0000-000000000002'::uuid],
  'La lista dice que, de los escalados, solo le toca volver al que nadie atendió'
);

SELECT ok(
  crm.reactivar_bots() >= 1,
  'El cron corre'
);

SELECT is(
  (SELECT array_agg(c.id ORDER BY c.id) FROM crm.contactos c
    WHERE c.inmobiliaria_id = '11111111-1111-1111-1111-111111111111'
      AND c.bot_motivo = 'escalamiento' AND NOT c.bot_activo),
  ARRAY['c0330003-0000-0000-0000-000000000003'::uuid,
        'c0330004-0000-0000-0000-000000000004'::uuid],
  'Y hace exactamente eso: vuelve el que la lista decía, se quedan los que decía que no'
);

-- --- Un sitio donde mirar, no otro aviso ----------------------------------
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM crm.mi_dia(200)
    WHERE contacto_id IN ('c0330001-0000-0000-0000-000000000001',
                          'c0330005-0000-0000-0000-000000000005')),
  0,
  'El manual y el relevo salen en la lista pero NO en «Mi día»: son silencios normales'
);

RESET ROLE;

-- Intentar un DELETE no probaría nada: con los JOIN la vista no es
-- actualizable y Postgres lo rechaza antes de mirar permisos. Se mira el
-- permiso, que es lo que cambiaría el día que la vista se simplifique.
SELECT table_privs_are('crm', 'v_bot_callado', 'authenticated', ARRAY['SELECT'],
  'Un usuario logueado solo puede LEER la lista: los privilegios por defecto del esquema se retiraron');

SELECT table_privs_are('crm', 'v_bot_callado', 'anon', ARRAY[]::text[],
  'Y un anónimo, nada');
SET LOCAL "request.jwt.claims" = '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT array_agg(nombre) FROM crm.v_bot_callado),
  ARRAY['Callado de Beta'],
  'Beta ve solo el suyo'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
