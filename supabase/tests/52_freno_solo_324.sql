-- =====================================================================
-- El freno de la 324 no calla al bot en la línea oficial (20261026100005).
--
-- crm.frenos_bot frena al bot para quien no está en el CRM, por lo que
-- entra por la 324. Un mensaje que entra por una línea de crm.lineas (la
-- 312, Cloud API) no lo mira; uno que llega sin línea (n8n), sí.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(8);

DELETE FROM crm.lineas;
DELETE FROM crm.contactos WHERE inmobiliaria_id = '11111111-1111-1111-1111-111111111111';

INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre, activa)
VALUES ('11111111-1111-1111-1111-111111111111', 'comercial', '520000000000001', 'Comercial 312', true),
       ('11111111-1111-1111-1111-111111111111', 'administrativa', '520000000000002', 'Apagada', false);

-- Pidió un asesor por la 324: el freno lo calló. No está en el CRM.
INSERT INTO crm.frenos_bot (inmobiliaria_id, telefono_e164, bot_activo, bot_motivo, bot_cambiado_at)
VALUES ('11111111-1111-1111-1111-111111111111', '+573005200001', false, 'escalamiento', now());

-- Un freno de Beta, para ver que la línea de Alfa no le sirve.
INSERT INTO crm.frenos_bot (inmobiliaria_id, telefono_e164, bot_activo, bot_motivo, bot_cambiado_at)
VALUES ('22222222-2222-2222-2222-222222222222', '+573005200003', false, 'escalamiento', now());

-- Y alguien en el CRM con el bot callado a mano.
INSERT INTO crm.contactos (inmobiliaria_id, nombre, telefono_e164, bot_activo, bot_motivo, bot_cambiado_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'Callado a mano', '+573005200002', false, 'manual', now());

SET LOCAL ROLE service_role;

SELECT ok(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573005200001', '520000000000001'),
  'Un freno callado no silencia lo que entra por la línea oficial'
);

SELECT ok(
  NOT crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573005200001', NULL),
  'Y sí silencia lo que llega sin línea (n8n, la 324)'
);

SELECT ok(
  NOT crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '573005200001'),
  'La versión de dos argumentos sigue igual que hoy'
);

SELECT ok(
  NOT crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573005200001', '520000000000002')
  AND NOT crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573005200001', '999999999999999'),
  'Una línea apagada o desconocida no cuenta como oficial: el freno manda'
);

SELECT ok(
  NOT crm.bot_puede_responder('22222222-2222-2222-2222-222222222222', '+573005200003', '520000000000001'),
  'La línea de una inmobiliaria no le sirve a otra: el freno de Beta sigue mandando'
);

SELECT ok(
  NOT crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573005200002', '520000000000001'),
  'El silencio del CRM (contactos.bot_activo) aplica siempre, también en la línea oficial'
);

RESET ROLE;

SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$SELECT crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573005200001', '520000000000001')$$,
  '42501', NULL,
  'La nueva nace cerrada: desde una sesión de usuario no se llama'
);

RESET ROLE;

SELECT ok(
  NOT has_function_privilege('anon', 'crm.bot_puede_responder(uuid, text, text)', 'EXECUTE'),
  'Ni anon'
);

SELECT * FROM finish();
ROLLBACK;
