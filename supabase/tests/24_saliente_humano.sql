-- =====================================================================
-- Un mensaje escrito por un asesor llega al CRM como humano.
--
-- Es el agujero que lleva semanas abierto: 7.819 mensajes salientes en
-- producción y TODOS del bot, porque las respuestas de las personas se
-- escribían en Kommo. Con el canal propio empiezan a llegar, y la
-- atribución tiene que ser correcta desde el primero.
--
-- No es cosmético. crm.bot_atendido_desde() decide si alguien atendió un
-- lead buscando salientes con origen 'humano'. Si un mensaje de asesor se
-- firma como del bot, la caducidad del silencio le devuelve la voz al bot
-- sobre una conversación que una persona SÍ estaba llevando.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(7);

DELETE FROM crm.contactos;

INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono)
VALUES ('fb000001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', '+573001151111');

-- Los tres roles, por el camino real de la proyección.
INSERT INTO public.agente_comercial_mensajes (id, conversacion_id, rol, contenido)
VALUES ('fb000002-0000-0000-0000-000000000002',
        'fb000001-0000-0000-0000-000000000001', 'usuario', 'Hola, busco apartamento'),
       ('fb000003-0000-0000-0000-000000000003',
        'fb000001-0000-0000-0000-000000000001', 'agente',  'Claro, ¿en qué zona?'),
       ('fb000004-0000-0000-0000-000000000004',
        'fb000001-0000-0000-0000-000000000001', 'asesor',  'Hola, soy Gisela, yo te ayudo');

SELECT is(
  (SELECT origen FROM crm.actividades
    WHERE metadata->>'origen_id' = 'fb000002-0000-0000-0000-000000000002'),
  'humano',
  'El mensaje del cliente entra como humano'
);

SELECT is(
  (SELECT origen FROM crm.actividades
    WHERE metadata->>'origen_id' = 'fb000003-0000-0000-0000-000000000003'),
  'agente_ia',
  'El del bot, como agente'
);

SELECT is(
  (SELECT origen FROM crm.actividades
    WHERE metadata->>'origen_id' = 'fb000004-0000-0000-0000-000000000004'),
  'humano',
  'Y el del ASESOR como humano: antes el ELSE se lo tragaba y lo firmaba el bot'
);

SELECT is(
  (SELECT tipo FROM crm.actividades
    WHERE metadata->>'origen_id' = 'fb000004-0000-0000-0000-000000000004'),
  'mensaje_saliente',
  'Sigue siendo saliente, que es lo que es'
);

-- --- La consecuencia que de verdad importa ---------------------------
SELECT ok(
  crm.bot_atendido_desde(
    (SELECT id FROM crm.contactos WHERE telefono_e164 = '+573001151111'),
    now() - interval '1 hour'),
  'Y por fin CUENTA como que alguien atendió: es lo que impide que la caducidad le devuelva la voz al bot encima de un asesor'
);

-- El del bot no debe contar como atención humana, o la caducidad no
-- caducaría nunca.
DELETE FROM crm.actividades
 WHERE metadata->>'origen_id' = 'fb000004-0000-0000-0000-000000000004';

SELECT ok(
  NOT crm.bot_atendido_desde(
    (SELECT id FROM crm.contactos WHERE telefono_e164 = '+573001151111'),
    now() - interval '1 hour'),
  'Sin el mensaje del asesor NO cuenta: el del bot no es atención humana'
);

-- --- Los tres roles que la base admite -------------------------------
SELECT throws_ok(
  $$INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido)
    VALUES ('fb000001-0000-0000-0000-000000000001', 'gerente', 'hola')$$,
  '23514',
  NULL,
  'Y un rol inventado sigue sin caber: usuario, agente o asesor'
);

SELECT * FROM finish();
ROLLBACK;
