-- =====================================================================
-- Proyección de la 312 (20261026100006).
--
--  1. La etiqueta [ESCALAR] del agente no llega al chat del CRM: se quita
--     y queda en metadata.escalado.
--  2. Con solo líneas oficiales, un contacto nuevo nace solo con su
--     teléfono, sin las identidades de Kommo de la conversación.
--  3. Si otra transacción crea a la misma persona a la vez, no queda un
--     contacto duplicado y huérfano.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(10);

DELETE FROM crm.lineas;
DELETE FROM crm.contactos;
DELETE FROM crm.preferencias;

INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre)
VALUES ('11111111-1111-1111-1111-111111111111', 'comercial', '530000000000001', 'Comercial 312');

-- =====================================================================
-- 1 · [ESCALAR]
-- =====================================================================
INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono, cliente_nombre)
VALUES ('e5300001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '+573005300001', 'Pide asesor');

INSERT INTO public.agente_comercial_mensajes (id, conversacion_id, rol, contenido, created_at, wa_phone_number_id)
VALUES
  ('e5300011-0000-0000-0000-000000000011', 'e5300001-0000-0000-0000-000000000001', 'usuario',
   'Quiero hablar con alguien', now() - interval '3 minutes', '530000000000001'),
  ('e5300012-0000-0000-0000-000000000012', 'e5300001-0000-0000-0000-000000000001', 'agente',
   '[ESCALAR] Claro, ya le aviso a un asesor del equipo.', now() - interval '2 minutes', '530000000000001'),
  ('e5300013-0000-0000-0000-000000000013', 'e5300001-0000-0000-0000-000000000001', 'agente',
   '  [escalar]Te escribe alguien en un momento.', now() - interval '1 minute', '530000000000001'),
  ('e5300014-0000-0000-0000-000000000014', 'e5300001-0000-0000-0000-000000000001', 'agente',
   'Con gusto te ayudo.', now(), '530000000000001');

SELECT is(
  (SELECT cuerpo FROM crm.actividades WHERE metadata->>'origen_id' = 'e5300012-0000-0000-0000-000000000012'),
  'Claro, ya le aviso a un asesor del equipo.',
  'El chat del CRM no enseña la etiqueta [ESCALAR]'
);

SELECT is(
  (SELECT (metadata->>'escalado')::boolean FROM crm.actividades
    WHERE metadata->>'origen_id' = 'e5300012-0000-0000-0000-000000000012'),
  true,
  'Y queda dicho en metadata.escalado'
);

SELECT is(
  (SELECT cuerpo FROM crm.actividades WHERE metadata->>'origen_id' = 'e5300013-0000-0000-0000-000000000013'),
  'Te escribe alguien en un momento.',
  'Sin distinguir mayúsculas, y con espacios delante'
);

SELECT is(
  (SELECT row(cuerpo, metadata ? 'escalado')::text FROM crm.actividades
    WHERE metadata->>'origen_id' = 'e5300014-0000-0000-0000-000000000014'),
  '("Con gusto te ayudo.",f)',
  'Una respuesta normal no cambia ni lleva la marca'
);

-- =====================================================================
-- 2 · Solo líneas oficiales: el contacto nuevo nace con su teléfono
-- =====================================================================
INSERT INTO crm.preferencias (inmobiliaria_id, solo_lineas_oficiales, solo_lineas_desde)
VALUES ('11111111-1111-1111-1111-111111111111', true, now() - interval '1 day');

-- Una conversación que arrastra el lead y el contacto de la era Kommo.
INSERT INTO public.agente_comercial_conversaciones
  (id, inmobiliaria_id, telefono, cliente_nombre, kommo_lead_id, kommo_contact_id)
VALUES ('e5300002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
        '+573005300002', 'Viene de Kommo', '9530001', '8530001');

INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido, wa_phone_number_id, wa_message_id)
VALUES ('e5300002-0000-0000-0000-000000000002', 'usuario', 'Hola, escribo por la línea nueva',
        '530000000000001', 'wamid.53.1');

SELECT is(
  (SELECT array_agg(i.tipo ORDER BY i.tipo) FROM crm.identidades i
     JOIN crm.contactos c ON c.id = i.contacto_id
    WHERE c.telefono_e164 = '+573005300002'),
  ARRAY['telefono_e164'],
  'Un contacto nuevo por la línea oficial solo tiene la identidad de su teléfono'
);

SELECT is(
  (SELECT count(*)::int FROM crm.identidades WHERE valor IN ('9530001', '8530001')),
  0,
  'Ni kommo_lead ni kommo_contact: son de la era anterior'
);

-- Con la preferencia apagada todo sigue como antes (la prueba 07 lo cubre
-- a fondo; aquí, solo que la rama vieja sigue viva).
UPDATE crm.preferencias SET solo_lineas_oficiales = false;

INSERT INTO public.agente_comercial_conversaciones
  (id, inmobiliaria_id, telefono, cliente_nombre, kommo_lead_id)
VALUES ('e5300003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
        '+573005300003', 'Kommo de siempre', '9530003');
INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido)
VALUES ('e5300003-0000-0000-0000-000000000003', 'usuario', 'Hola por Kommo');

SELECT is(
  (SELECT array_agg(i.tipo ORDER BY i.tipo) FROM crm.identidades i
     JOIN crm.contactos c ON c.id = i.contacto_id
    WHERE c.telefono_e164 = '+573005300003'),
  ARRAY['kommo_lead', 'telefono_e164'],
  'Con la preferencia apagada se siguen guardando las identidades de Kommo'
);

-- =====================================================================
-- 3 · La carrera de dos mensajes simultáneos
--
-- Una sola sesión no puede correr dos transacciones a la vez. Se simula lo
-- que ve la segunda: entre que busca la identidad (y no la encuentra) y
-- que la guarda, la primera ya creó a la persona. Un trigger de prueba
-- sobre crm.contactos mete esa identidad, apuntando a otro contacto, justo
-- cuando resolver_contacto crea el suyo.
-- =====================================================================
INSERT INTO crm.contactos (id, inmobiliaria_id, nombre)
VALUES ('c5300009-0000-0000-0000-000000000009', '11111111-1111-1111-1111-111111111111', 'La creó la otra transacción');

CREATE FUNCTION pg_temp.la_otra_gano() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.id <> 'c5300009-0000-0000-0000-000000000009' THEN
    INSERT INTO crm.identidades (inmobiliaria_id, contacto_id, tipo, valor, origen)
    VALUES (NEW.inmobiliaria_id, 'c5300009-0000-0000-0000-000000000009', 'telefono_e164', '+573005300009', 'whatsapp')
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NULL;
END $$;

CREATE TRIGGER la_otra_gano AFTER INSERT ON crm.contactos
  FOR EACH ROW EXECUTE FUNCTION pg_temp.la_otra_gano();

CREATE TEMP TABLE resuelto AS
SELECT crm.resolver_contacto(
  '11111111-1111-1111-1111-111111111111',
  '[{"tipo":"telefono_e164","valor":"+573005300009"}]'::jsonb,
  'Segundo mensaje', 'whatsapp', 'cliente', '+573005300009') AS id;

DROP TRIGGER la_otra_gano ON crm.contactos;

SELECT is(
  (SELECT id FROM resuelto),
  'c5300009-0000-0000-0000-000000000009'::uuid,
  'Quien pierde la carrera usa el contacto que creó la otra'
);

SELECT is(
  (SELECT count(*)::int FROM crm.contactos
    WHERE inmobiliaria_id = '11111111-1111-1111-1111-111111111111'
      AND (nombre = 'Segundo mensaje' OR telefono_crudo = '+573005300009')
      AND id <> 'c5300009-0000-0000-0000-000000000009'),
  0,
  'Y no deja un contacto duplicado y huérfano'
);

SELECT is(
  (SELECT nombre FROM crm.contactos WHERE id = 'c5300009-0000-0000-0000-000000000009'),
  crm.mejor_nombre('La creó la otra transacción', 'Segundo mensaje'),
  'Y al contacto que ganó se le aplica el nombre como a cualquiera (mejor_nombre decide, no el orden)'
);

SELECT * FROM finish();
ROLLBACK;
