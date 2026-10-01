-- =====================================================================
-- La ventana del silencio por escalamiento: 6 horas, y quién la decide.
--
-- El 1/oct había 35 contactos con el bot callado, 34 por escalamiento, y
-- 7 de las 12 conversaciones con actividad de ese día estaban mudas. Con
-- 3 días de vigencia y 4-13 apagones diarios, el stock de callados quedó
-- del mismo orden que las conversaciones activas: desde Kommo parecía que
-- el bot no le contestaba a nadie.
--
-- Lo que esta prueba fija no es el número, es DÓNDE vive el número:
--   · el plazo lo decide crm.ventana_silencio_escalamiento(), no el
--     comando del cron. Con `p_dias` el plazo vivía en cron.job, y esa
--     separación ya costó cuatro días de caducidad muerta;
--   · el agendado es sin argumentos, así que la firma no se puede
--     desencontrar con lo agendado (la prueba 19 lo ejecuta de verdad);
--   · la firma vieja NO existe: si sobreviviera, algo podría seguir
--     llamándola con un 3 y nadie se enteraría.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(14);

DELETE FROM crm.contactos;

-- =====================================================================
-- 1 · La perilla
-- =====================================================================
SELECT is(
  crm.ventana_silencio_escalamiento(),
  interval '6 hours',
  'El silencio por escalamiento dura 6 h, lo mismo que el relevo'
);

SELECT is(
  crm.ventana_silencio_escalamiento(),
  crm.ventana_relevo(),
  'Las dos reglas del bot se miden con el mismo plazo: una sola idea que recordar'
);

-- =====================================================================
-- 2 · El borde, que es lo único que de verdad hay que probar
--
-- La prueba 17 ya cubre el fondo (manual no caduca, una nota cuenta,
-- abrir la ficha no). Aquí solo se mira el filo de la ventana.
-- =====================================================================
INSERT INTO crm.contactos
  (id, inmobiliaria_id, nombre, telefono_e164,
   bot_activo, bot_motivo, bot_cambiado_at)
VALUES
  -- Siete horas: la ventana ya venció.
  ('b2800001-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'Venció', '+573001128801',
   false, 'escalamiento', now() - interval '7 hours'),
  -- Cinco horas: todavía dentro. Antes de hoy habría esperado 3 días.
  ('b2800002-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111', 'Aún dentro', '+573001128802',
   false, 'escalamiento', now() - interval '5 hours'),
  -- A mano hace una semana: no caduca nunca, ni con la ventana corta.
  ('b2800003-0000-0000-0000-000000000003',
   '11111111-1111-1111-1111-111111111111', 'Me encargo yo', '+573001128803',
   false, 'manual', now() - interval '7 days');

-- Y el cuarto: escaló hace siete horas, pero su silencio está marcado como
-- "lo atiende una persona". Son los 36 que ya estaban callados cuando la
-- ventana bajó de 3 días a 6 h: la regla nueva no es retroactiva.
INSERT INTO crm.contactos
  (id, inmobiliaria_id, nombre, telefono_e164,
   bot_activo, bot_motivo, bot_cambiado_at, bot_caduca)
VALUES
  ('b2800004-0000-0000-0000-000000000004',
   '11111111-1111-1111-1111-111111111111', 'Lo lleva una persona', '+573001128804',
   false, 'escalamiento', now() - interval '7 hours', false);

SELECT is(
  crm.reactivar_bots(), 1,
  'Vuelve exactamente uno: el que pasó de las 6 h y sí caduca'
);

SELECT ok(
  (SELECT NOT bot_activo FROM crm.contactos
    WHERE id = 'b2800004-0000-0000-0000-000000000004'),
  'El marcado como "lo atiende una persona" no vuelve, aunque pasen las 6 h'
);

SELECT ok(
  (SELECT bot_activo AND bot_motivo IS NULL FROM crm.contactos
    WHERE id = 'b2800001-0000-0000-0000-000000000001'),
  'El de 7 h recupera la voz y se queda sin motivo: ya no hay silencio que explicar'
);

SELECT ok(
  (SELECT NOT bot_activo FROM crm.contactos
    WHERE id = 'b2800002-0000-0000-0000-000000000002'),
  'El de 5 h sigue callado: la asesora todavía tiene su hora larga para llegar'
);

SELECT ok(
  (SELECT NOT bot_activo FROM crm.contactos
    WHERE id = 'b2800003-0000-0000-0000-000000000003'),
  'El silencio a mano no lo toca la ventana: alguien dijo que se encargaba'
);

-- El rastro tiene que hablar de horas. Si dijera "días" después de este
-- cambio, el historial estaría mintiéndole a quien abre la ficha.
SELECT ok(
  (SELECT cuerpo LIKE '%6 horas%' FROM crm.actividades
    WHERE contacto_id = 'b2800001-0000-0000-0000-000000000001'
      AND tipo = 'sistema'),
  'El historial dice cuántas HORAS pasaron, no cuántos días'
);

-- =====================================================================
-- 3 · El agendado, que es la mitad que falla en silencio
-- =====================================================================
SELECT is(
  (SELECT schedule FROM cron.job WHERE jobname = 'crm_reactivar_bots'),
  '2-59/5 * * * *',
  'Corre cada 5 min: con un cron diario el plazo lo fijaría el cron y no la regla'
);

SELECT isnt(
  (SELECT schedule FROM cron.job WHERE jobname = 'crm_reactivar_bots'),
  (SELECT schedule FROM cron.job WHERE jobname = 'crm_reactivar_relevos'),
  'Y no comparte minuto con el relevo, como ningún par de crones de este proyecto'
);

SELECT is(
  (SELECT count(*)::int FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'crm' AND p.proname = 'reactivar_bots'
      AND p.pronargs > 0),
  0,
  'No queda ninguna firma con argumentos: el plazo no puede volver a vivir en cron.job'
);

-- =====================================================================
-- 4 · Callado NO es abandonado
--
-- Era la condición de la decisión: los que se quedan sin caducidad siguen
-- a la vista en «Mi día», porque conservan motivo 'escalamiento' y nadie
-- los ha atendido. Si dejaran de salir, esto no sería "lo atiende una
-- persona", sería perderlos.
-- =====================================================================
SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM crm.mi_dia(200)
    WHERE tipo = 'bot_callado'
      AND contacto_id = 'b2800004-0000-0000-0000-000000000004'),
  1,
  'El que espera a una persona sigue saliendo en «Mi día»: callado y a la vista'
);

-- Y encender el bot a mano cierra ese capítulo: el próximo silencio de esta
-- persona vuelve a caducar como cualquier otro. Sin esto, el marcado sería
-- una trampa para dentro de un mes.
--
-- En sentencia aparte, por lo mismo que la 17 lo hace con
-- bot_puede_responder: dentro de una sola sentencia el subselect lee la
-- instantánea de antes del UPDATE y la prueba pasaría o fallaría por el
-- motivo equivocado.
SELECT ok(
  crm.cambiar_bot('b2800004-0000-0000-0000-000000000004', true),
  'Un asesor puede encenderle el bot a quien estaba esperando una persona'
);

SELECT ok(
  (SELECT bot_caduca FROM crm.contactos
    WHERE id = 'b2800004-0000-0000-0000-000000000004'),
  'Y al encenderlo se devuelve la caducidad: bot_caduca vale para el silencio, no para la persona'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
