-- =====================================================================
-- Fotos, audios y documentos de WhatsApp en el CRM (25 oct 2026).
--
-- Lo que importa:
--  · un mensaje con `medio` deja ese medio en actividades.metadata, tal cual;
--  · un mensaje de texto no trae la llave `medio`;
--  · el cuerpo sigue siendo `contenido` (la nota de voz transcrita).
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(4);

DELETE FROM crm.lineas;
DELETE FROM crm.contactos;
DELETE FROM crm.preferencias;

-- Las columnas de la plataforma, por si la base local no las tiene.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'agente_comercial_mensajes' AND column_name = 'wa_phone_number_id'
  ) THEN
    ALTER TABLE public.agente_comercial_mensajes ADD COLUMN wa_phone_number_id text;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'agente_comercial_mensajes' AND column_name = 'medio'
  ) THEN
    ALTER TABLE public.agente_comercial_mensajes ADD COLUMN medio jsonb;
  END IF;
END $$;

INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre) VALUES
  ('11111111-1111-1111-1111-111111111111', 'comercial', '312000000000047', 'Comercial 312');

INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono, cliente_nombre) VALUES
  ('f4700001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '+573004700001', 'Cliente con audio');

INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido, wa_message_id, wa_phone_number_id, medio)
VALUES (
  'f4700001-0000-0000-0000-000000000001', 'usuario', '[nota de voz] Busco apartamento en Belén',
  'wamid.medio47', '312000000000047',
  '{"tipo": "audio", "mime": "audio/ogg", "ruta": "11111111-1111-1111-1111-111111111111/573004700001/wamid.medio47.ogg", "voz": true, "texto": "Busco apartamento en Belén"}'::jsonb
);

INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido, wa_message_id, wa_phone_number_id)
VALUES ('f4700001-0000-0000-0000-000000000001', 'usuario', 'Y tiene parqueadero?', 'wamid.texto47', '312000000000047');

SELECT is(
  (SELECT metadata -> 'medio' ->> 'ruta' FROM crm.actividades WHERE metadata ->> 'wa_message_id' = 'wamid.medio47'),
  '11111111-1111-1111-1111-111111111111/573004700001/wamid.medio47.ogg',
  'La ruta del medio pasa a actividades.metadata');

SELECT is(
  (SELECT metadata -> 'medio' ->> 'tipo' FROM crm.actividades WHERE metadata ->> 'wa_message_id' = 'wamid.medio47'),
  'audio',
  'El tipo del medio pasa tal cual');

SELECT is(
  (SELECT cuerpo FROM crm.actividades WHERE metadata ->> 'wa_message_id' = 'wamid.medio47'),
  '[nota de voz] Busco apartamento en Belén',
  'El cuerpo sigue siendo el contenido: la nota de voz transcrita');

SELECT is(
  (SELECT metadata ? 'medio' FROM crm.actividades WHERE metadata ->> 'wa_message_id' = 'wamid.texto47'),
  false,
  'Un mensaje de texto no trae la llave medio');

SELECT * FROM finish();
ROLLBACK;
