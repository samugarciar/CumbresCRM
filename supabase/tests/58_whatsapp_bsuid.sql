-- =====================================================================
-- PRUEBA 58: la gente con «@» que no nos ha dado su número
-- (20261028100001)
--
-- Sin teléfono, Meta manda el BSUID («CO.1349…») y la plataforma lleva la
-- conversación con él donde iría el teléfono. Aquí: el contacto nace con
-- esa identidad y sin teléfono crudo, el siguiente mensaje cae en el mismo
-- contacto, apagarle el bot a mano se respeta, y el relevo lo encuentra.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(8);

DELETE FROM crm.lineas;
DELETE FROM crm.contactos;
DELETE FROM crm.preferencias;

INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre)
VALUES ('11111111-1111-1111-1111-111111111111', 'comercial', '580000000000001', 'Comercial 312');

INSERT INTO crm.preferencias (inmobiliaria_id, solo_lineas_oficiales, solo_lineas_desde)
VALUES ('11111111-1111-1111-1111-111111111111', true, now() - interval '1 day');

INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono, cliente_nombre)
VALUES ('e5800001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'CO.13491208655302741918', '@DavidPrueba');

INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido, wa_phone_number_id, wa_message_id)
VALUES ('e5800001-0000-0000-0000-000000000001', 'usuario', 'Hola, me interesa el apartamento',
        '580000000000001', 'wamid.58.1');

-- =====================================================================
-- 1 · El contacto nace con su BSUID
-- =====================================================================
SELECT is(
  (SELECT count(*)::int FROM crm.identidades
    WHERE tipo = 'whatsapp_bsuid' AND valor = 'CO.13491208655302741918'),
  1,
  'El contacto nace con el BSUID como identidad'
);

SELECT is(
  (SELECT row(c.nombre, c.telefono_e164 IS NULL, c.telefono_crudo IS NULL)::text
     FROM crm.contactos c
     JOIN crm.identidades i ON i.contacto_id = c.id
    WHERE i.tipo = 'whatsapp_bsuid'),
  '(@DavidPrueba,t,t)',
  'Con su nombre de WhatsApp, sin teléfono y sin guardar el BSUID como teléfono crudo'
);

SELECT is(
  (SELECT count(*)::int FROM crm.actividades a
     JOIN crm.identidades i ON i.contacto_id = a.contacto_id
    WHERE i.tipo = 'whatsapp_bsuid' AND a.tipo = 'mensaje_entrante'),
  1,
  'Y su mensaje está en el chat del CRM'
);

INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido, wa_phone_number_id, wa_message_id)
VALUES ('e5800001-0000-0000-0000-000000000001', 'agente', 'Claro, te cuento.',
        '580000000000001', 'wamid.58.2');

SELECT is(
  (SELECT count(DISTINCT a.contacto_id)::int FROM crm.actividades a
    WHERE a.metadata->>'origen_id' IN (
      SELECT id::text FROM public.agente_comercial_mensajes
       WHERE conversacion_id = 'e5800001-0000-0000-0000-000000000001')),
  1,
  'El siguiente mensaje cae en el mismo contacto, no en uno nuevo'
);

-- =====================================================================
-- 2 · El bot y el relevo lo encuentran por su BSUID
-- =====================================================================
SELECT is(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', 'CO.13491208655302741918', '580000000000001'),
  true,
  'Con el bot encendido, puede responderle'
);

UPDATE crm.contactos c
   SET bot_activo = false, bot_motivo = 'manual', bot_cambiado_at = now()
  FROM crm.identidades i
 WHERE i.contacto_id = c.id AND i.tipo = 'whatsapp_bsuid';

SELECT is(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', 'CO.13491208655302741918', '580000000000001'),
  false,
  'Apagado a mano desde el CRM, el bot no le responde'
);

UPDATE crm.contactos c
   SET bot_activo = true, bot_motivo = NULL, bot_cambiado_at = now()
  FROM crm.identidades i
 WHERE i.contacto_id = c.id AND i.tipo = 'whatsapp_bsuid';

SELECT is(
  crm.registrar_relevo('580000000000001', 'CO.13491208655302741918', now()),
  true,
  'Un asesor le escribe desde el CRM: el relevo lo encuentra por su BSUID'
);

SELECT is(
  (SELECT row(c.bot_activo, c.bot_motivo)::text
     FROM crm.contactos c JOIN crm.identidades i ON i.contacto_id = c.id
    WHERE i.tipo = 'whatsapp_bsuid'),
  '(f,relevo)',
  'Y el bot queda callado por relevo, como con cualquier contacto'
);

SELECT * FROM finish();
ROLLBACK;
