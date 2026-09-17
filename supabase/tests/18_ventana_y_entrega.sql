-- =====================================================================
-- La ventana de WhatsApp y los envíos que no llegan.
--
-- Lo que se mide: que la alerta de escalamiento quepa DENTRO de la
-- ventana de 24 h de Meta (antes saltaba a las 48, o sea siempre tarde:
-- el asesor abría el chat, escribía, y el cliente no recibía nada), que
-- se sepa cuándo se cierra la ventana antes de escribir, y que un envío
-- que WhatsApp rechaza no se quede callado.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(12);

DELETE FROM crm.contactos;

INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164)
VALUES ('e0000001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', 'Ana Ruiz', '+573001117771'),
       ('e0000002-0000-0000-0000-000000000002',
        '11111111-1111-1111-1111-111111111111', 'Nunca escribió', '+573001117772');

-- --- El umbral, ahora en un solo sitio -------------------------------
SELECT is(
  crm.ventana_escalamiento(), interval '8 hours',
  'El escalamiento es "reciente" 8 horas, no 48: tiene que caber dentro de la ventana de 24 h de Meta'
);

-- --- La ventana de 24 horas ------------------------------------------
SELECT is(
  crm.ventana_whatsapp('e0000002-0000-0000-0000-000000000002'),
  NULL,
  'Quien nunca nos escribió no tiene ventana: nunca la hubo'
);

INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
        'e0000001-0000-0000-0000-000000000001', 'Hola, sigo interesada',
        now() - interval '3 hours');

SELECT ok(
  crm.ventana_whatsapp('e0000001-0000-0000-0000-000000000001') > now(),
  'Escribió hace 3 horas: la ventana sigue abierta'
);

-- Que contestemos NOSOTROS no mueve nada. Solo el cliente la abre, y es
-- justo el error que llevaría a creer que hay margen cuando no lo hay.
INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'mensaje_saliente', 'agente_ia',
        'e0000001-0000-0000-0000-000000000001', 'Claro, te cuento', now());

SELECT ok(
  crm.ventana_whatsapp('e0000001-0000-0000-0000-000000000001')
    < now() + interval '21 hours 5 minutes',
  'Nuestro mensaje NO reabre la ventana: sigue contando desde el del cliente'
);

INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
        'e0000002-0000-0000-0000-000000000002', 'Pregunté hace mucho',
        now() - interval '9 days');

SELECT ok(
  crm.ventana_whatsapp('e0000002-0000-0000-0000-000000000002') < now(),
  'Nueve días de silencio: la ventana está cerrada y solo caben plantillas aprobadas'
);

-- --- Los acuses de WhatsApp ------------------------------------------
INSERT INTO crm.envios
  (id, inmobiliaria_id, contacto_id, cuerpo, canal, estado, wa_message_id)
VALUES ('e0000010-0000-0000-0000-000000000010',
        '11111111-1111-1111-1111-111111111111',
        'e0000001-0000-0000-0000-000000000001',
        'Hola Ana, te comparto un apartamento', 'meta', 'enviado', 'wamid.TEST1');

SELECT ok(
  crm.registrar_estado_envio('wamid.TEST1', 'entregado'),
  'Un acuse de entrega avanza el envío'
);

-- Los acuses de WhatsApp llegan desordenados. Sin la guarda, un 'sent'
-- que llega tarde borraría un 'delivered' ya anotado.
SELECT ok(
  NOT crm.registrar_estado_envio('wamid.TEST1', 'enviado'),
  'Pero un acuse viejo que llega tarde NO hace retroceder el estado'
);

SELECT is(
  (SELECT estado FROM crm.envios WHERE id = 'e0000010-0000-0000-0000-000000000010'),
  'entregado',
  'Y el estado se queda en el más avanzado'
);

SELECT throws_ok(
  $$SELECT crm.registrar_estado_envio('wamid.TEST1', 'inventado')$$,
  NULL, NULL,
  'Un estado que Meta no manda revienta en vez de guardarse'
);

-- --- La alerta: un mensaje que no llegó ------------------------------
INSERT INTO crm.envios
  (id, inmobiliaria_id, contacto_id, cuerpo, canal, estado,
   wa_message_id, error_codigo, error, fallido_at)
VALUES ('e0000011-0000-0000-0000-000000000011',
        '11111111-1111-1111-1111-111111111111',
        'e0000002-0000-0000-0000-000000000002',
        'Hola, ¿sigues buscando?', 'meta', 'fallido',
        'wamid.TEST2', 131047,
        'Pasaron más de 24 h desde su último mensaje: solo se puede con plantilla aprobada',
        now() - interval '10 minutes');

SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT prioridad::int FROM crm.mi_dia(200)
    WHERE tipo = 'envio_fallido'
      AND contacto_id = 'e0000002-0000-0000-0000-000000000002'),
  1,
  'Un mensaje que no llegó sale ARRIBA: es el único caso en que el asesor cree que hizo su trabajo y no lo hizo'
);

SELECT ok(
  (SELECT detalle FROM crm.mi_dia(200)
    WHERE tipo = 'envio_fallido'
      AND contacto_id = 'e0000002-0000-0000-0000-000000000002')
    LIKE '%24 h%',
  'Y dice POR QUÉ no llegó, no solo que falló'
);

SELECT lives_ok(
  $$SELECT crm.marcar_envio_visto('e0000011-0000-0000-0000-000000000011')$$,
  'La alerta se puede dar por vista: una alerta que no se cierra se vuelve ruido'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
