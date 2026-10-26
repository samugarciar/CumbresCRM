-- =====================================================================
-- El escalamiento se ancla al más reciente (20261026100004).
--
-- Antes se tomaba el PRIMER escalamiento de la conversación: un contacto
-- nuevo heredaba el de la era Kommo («Pidió persona hace 2 meses») y un
-- segundo pedido de ayuda, días después, no volvía a callar al bot.
--
-- El puente contacto ↔ conversación lo arma la proyección real, como en
-- las pruebas 11 y 17.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(9);

DELETE FROM crm.contactos;

INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono)
VALUES ('e5100001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '+573005100001'),
       ('e5100002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', '+573005100002'),
       ('e5100003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', '+573005100003');

INSERT INTO public.agente_comercial_mensajes (id, conversacion_id, rol, contenido)
VALUES ('e5100011-0000-0000-0000-000000000011', 'e5100001-0000-0000-0000-000000000001', 'usuario', 'Hola'),
       ('e5100012-0000-0000-0000-000000000012', 'e5100002-0000-0000-0000-000000000002', 'usuario', 'Hola'),
       ('e5100013-0000-0000-0000-000000000013', 'e5100003-0000-0000-0000-000000000003', 'usuario', 'Hola');

-- 1 · Lleva diez días en el CRM. Pidió una persona hace cinco días (el bot
--     se calló y volvió hace cuatro) y otra vez hace una hora.
-- 2 · Nació ayer en el CRM; el único pedido es de hace dos meses (Kommo).
-- 3 · Pidió una persona hace dos horas y alguien le encendió el bot a mano
--     hace una hora.
UPDATE crm.contactos SET created_at = now() - interval '10 days',
                         bot_activo = true, bot_cambiado_at = now() - interval '4 days'
 WHERE telefono_e164 = '+573005100001';
UPDATE crm.contactos SET created_at = now() - interval '1 day'
 WHERE telefono_e164 = '+573005100002';
UPDATE crm.contactos SET created_at = now() - interval '1 day',
                         bot_activo = true, bot_cambiado_at = now() - interval '1 hour'
 WHERE telefono_e164 = '+573005100003';

UPDATE crm.oportunidades o SET created_at = c.created_at, escalado_at = NULL
  FROM crm.contactos c
 WHERE c.id = o.contacto_id AND c.telefono_e164 LIKE '+57300510000%';

-- El primer pedido de 1 ya se había anotado.
UPDATE crm.oportunidades o SET escalado_at = now() - interval '5 days'
  FROM crm.contactos c
 WHERE c.id = o.contacto_id AND c.telefono_e164 = '+573005100001';

INSERT INTO public.agente_comercial_uso
  (inmobiliaria_id, conversacion_id, modelo, etapa, escalado, created_at)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'e5100001-0000-0000-0000-000000000001',
   'claude-opus-5', 'CONSULTA', true, now() - interval '5 days'),
  ('11111111-1111-1111-1111-111111111111', 'e5100001-0000-0000-0000-000000000001',
   'claude-opus-5', 'CONSULTA', true, now() - interval '1 hour'),
  ('11111111-1111-1111-1111-111111111111', 'e5100002-0000-0000-0000-000000000002',
   'claude-opus-5', 'CONSULTA', true, now() - interval '60 days'),
  ('11111111-1111-1111-1111-111111111111', 'e5100003-0000-0000-0000-000000000003',
   'claude-opus-5', 'CONSULTA', true, now() - interval '2 hours');

SELECT lives_ok($$SELECT crm.sincronizar_escalamientos()$$, 'La pasada corre');

-- --- Un segundo pedido, días después ---------------------------------------
SELECT is(
  (SELECT o.escalado_at FROM crm.oportunidades o JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573005100001'),
  now() - interval '1 hour',
  'La oportunidad se queda con el pedido más reciente, no con el primero'
);

SELECT is(
  (SELECT row(bot_activo, bot_motivo)::text FROM crm.contactos WHERE telefono_e164 = '+573005100001'),
  '(f,escalamiento)',
  'Y el bot se vuelve a callar: pidió otra vez hablar con alguien'
);

-- --- Un pedido de antes de que existiera el contacto -----------------------
SELECT is(
  (SELECT o.escalado_at FROM crm.oportunidades o JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573005100002'),
  NULL,
  'El pedido de la era Kommo, anterior al contacto, no cuenta: nada de «Pidió persona hace 2 meses»'
);

SELECT ok(
  (SELECT bot_activo FROM crm.contactos WHERE telefono_e164 = '+573005100002'),
  'Ni calla al bot'
);

-- --- Un encendido a mano posterior se respeta -------------------------------
SELECT is(
  (SELECT o.escalado_at FROM crm.oportunidades o JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573005100003'),
  now() - interval '2 hours',
  'El pedido se anota en la oportunidad'
);

SELECT ok(
  (SELECT bot_activo FROM crm.contactos WHERE telefono_e164 = '+573005100003'),
  'Pero el bot sigue hablando: alguien lo encendió a mano después del pedido'
);

-- --- Hacia atrás no se mueve -------------------------------------------------
SELECT is(crm.sincronizar_escalamientos(), 0,
  'Una segunda pasada no encuentra nada nuevo');

UPDATE crm.oportunidades o SET escalado_at = now() - interval '30 minutes'
  FROM crm.contactos c
 WHERE c.id = o.contacto_id AND c.telefono_e164 = '+573005100003';
SELECT is(crm.sincronizar_escalamientos(), 0,
  'Y un escalado_at más nuevo que el del agente no se pisa con uno más viejo');

SELECT * FROM finish();
ROLLBACK;
