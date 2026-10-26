-- =====================================================================
-- Relevo de 1 hora, separado del escalamiento (20261026100002).
--
-- Decisión de Samuel: cuando alguien del equipo le escribe al cliente,
-- el bot se calla, pero vuelve solo si el asesor no escribe en 1 hora.
-- El escalamiento sigue en 6 h. Y quien pidió una persona y la tuvo
-- también recupera el bot si el asesor no vuelve a escribir.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(17);

DELETE FROM crm.contactos;
DELETE FROM crm.lineas;

INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre)
VALUES ('11111111-1111-1111-1111-111111111111', 'comercial', '490000000000001', 'Comercial');

INSERT INTO crm.contactos
  (id, inmobiliaria_id, nombre, telefono_e164, bot_activo, bot_motivo, bot_cambiado_at, bot_caduca)
VALUES
  ('c0490001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Hace 61 minutos', '+573004900001', false, 'relevo', now() - interval '61 minutes', true),
  ('c0490002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'Hace 59 minutos', '+573004900002', false, 'relevo', now() - interval '59 minutes', true),
  ('c0490003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
   'Pidió una persona', '+573004900003', false, 'escalamiento', now() - interval '40 minutes', true),
  ('c0490004-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111',
   'Bot hablando', '+573004900004', true, NULL, NULL, true),
  ('c0490005-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111',
   'Escalado sin caducidad', '+573004900005', false, 'escalamiento', now() - interval '40 minutes', false),
  ('c0490006-0000-0000-0000-000000000006', '11111111-1111-1111-1111-111111111111',
   'Escalado esperando', '+573004900006', false, 'escalamiento', now() - interval '2 hours', true);

-- --- Las perillas ---------------------------------------------------------
SELECT is(crm.ventana_relevo(), interval '1 hour',
  'El relevo dura 1 hora');

SELECT is(crm.ventana_silencio_escalamiento(), interval '6 hours',
  'Y el escalamiento sigue en 6 horas: es otra perilla');

-- --- La vuelta, en el borde ------------------------------------------------
SELECT is(crm.reactivar_relevos(), 1,
  'Vuelve uno solo: el de hace 61 minutos');

SELECT ok(
  (SELECT bot_activo FROM crm.contactos WHERE id = 'c0490001-0000-0000-0000-000000000001')
  AND NOT (SELECT bot_activo FROM crm.contactos WHERE id = 'c0490002-0000-0000-0000-000000000002'),
  'A los 61 minutos el bot vuelve; a los 59, todavía no'
);

SELECT is(
  (SELECT cuerpo FROM crm.actividades
    WHERE contacto_id = 'c0490001-0000-0000-0000-000000000001' AND tipo = 'sistema'),
  'El bot vuelve a responderle: pasó 1 hora sin que nadie del equipo le escribiera.',
  'El aviso dice «1 hora», sacado de la perilla y en singular'
);

SELECT is(crm.duracion_legible(interval '30 minutes') || ' / ' || crm.duracion_legible(interval '6 hours'),
  '30 minutos / 6 horas',
  'Y se lee bien con otras perillas: en minutos o en horas');

-- --- Escalado y luego escribe el asesor -----------------------------------
SET LOCAL ROLE service_role;
SELECT ok(
  crm.registrar_relevo('490000000000001', '573004900003', now() - interval '5 minutes'),
  'Un asesor le escribe a quien pidió una persona'
);
RESET ROLE;

SELECT is(
  (SELECT row(bot_activo, bot_motivo, bot_cambiado_at = now() - interval '5 minutes')::text
     FROM crm.contactos WHERE id = 'c0490003-0000-0000-0000-000000000003'),
  '(f,relevo,t)',
  'Queda en relevo, contado desde el mensaje del asesor'
);

SELECT is(
  (SELECT cuerpo FROM crm.actividades
    WHERE contacto_id = 'c0490003-0000-0000-0000-000000000003' AND tipo = 'sistema'),
  'Alguien del equipo atendió a quien pidió una persona: el bot vuelve si nadie le escribe en 1 hora.',
  'Y el historial lo explica'
);

SELECT is(
  crm.bot_vuelve_at('c0490003-0000-0000-0000-000000000003'),
  now() - interval '5 minutes' + interval '1 hour',
  'La ficha sabe que vuelve una hora después del mensaje del asesor'
);

-- Pasa la hora sin que nadie vuelva a escribir.
UPDATE crm.contactos SET bot_cambiado_at = now() - interval '61 minutes'
 WHERE id = 'c0490003-0000-0000-0000-000000000003';

SELECT is(crm.reactivar_relevos(), 1,
  'A los 61 minutos sin mensajes del equipo, el cron lo encuentra');

SELECT ok(
  (SELECT bot_activo FROM crm.contactos WHERE id = 'c0490003-0000-0000-0000-000000000003'),
  'Y el bot vuelve también para el que había escalado'
);

-- --- Un escalamiento que alguien dejó sin caducidad no se toca --------------
SET LOCAL ROLE service_role;
SELECT ok(
  NOT crm.registrar_relevo('490000000000001', '573004900005'),
  'Un escalamiento sin caducidad no pasa a relevo: manda quien lo decidió'
);

-- --- Un eco atrasado no abre relevo ----------------------------------------
SELECT ok(
  NOT crm.registrar_relevo('490000000000001', '573004900004', now() - interval '90 minutes'),
  'Un eco que llega con hora y media de retraso no abre relevo: nacería vencido'
);
RESET ROLE;

SELECT is(
  (SELECT row(bot_activo, count(a.id))::text
     FROM crm.contactos c
     LEFT JOIN crm.actividades a ON a.contacto_id = c.id AND a.tipo = 'sistema'
    WHERE c.id = 'c0490004-0000-0000-0000-000000000004'
    GROUP BY c.bot_activo),
  '(t,0)',
  'Y el bot sigue hablando, sin avisos en el historial'
);

-- --- Cuándo vuelve un escalamiento sin atender -----------------------------
SELECT is(
  crm.bot_vuelve_at('c0490006-0000-0000-0000-000000000006'),
  now() - interval '2 hours' + interval '6 hours',
  'Un escalamiento sin atender que caduca vuelve a las 6 horas, y la ficha lo sabe'
);

SELECT is(
  crm.bot_vuelve_at('c0490005-0000-0000-0000-000000000005'),
  NULL,
  'Uno sin caducidad no tiene hora de vuelta'
);

SELECT * FROM finish();
ROLLBACK;
