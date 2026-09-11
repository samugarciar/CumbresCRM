-- =====================================================================
-- La convención `kommo-<contact_id>` y la recuperación de teléfonos.
--
-- Contexto: desde el 11 ago 2026, cuando un contacto de Kommo llega sin
-- `custom_fields_values`, n8n escribe `telefono = 'kommo-<contact_id>'`
-- a propósito. Son 226 conversaciones reales (27% del tráfico), con
-- mensajes y nombre, de personas a las que no se puede llamar.
--
-- Esto ya funcionaba por diseño. Estas pruebas lo convierten en una
-- decisión explícita, para que el próximo que toque crm.resolver_contacto
-- no lo rompa sin enterarse.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(8);

DELETE FROM crm.contactos;
DELETE FROM public.citas;
DELETE FROM public.solicitudes_apertura;
DELETE FROM public.agente_comercial_conversaciones;

ALTER TABLE public.agente_comercial_mensajes DISABLE TRIGGER crm_proyectar_mensaje;

-- ---------------------------------------------------------------------
-- EL CASO DE LOS GEMELOS — visto 3 veces en producción
--
-- El webhook llega antes de que Kommo pueble el teléfono: se crea la
-- conversación `kommo-*`, y segundos después otra con el número real. Son
-- dos filas (la tabla es única por teléfono) pero UNA persona.
-- ---------------------------------------------------------------------
INSERT INTO public.agente_comercial_conversaciones
  (id, inmobiliaria_id, telefono, cliente_nombre, kommo_lead_id, kommo_contact_id, created_at)
VALUES
  ('f1111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111',
   'kommo-50604099', 'JLFR', '60000001', '50604099', now() - interval '10 minutes'),
  ('f2222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111',
   '+573201234529', 'JLFR', '60000002', '50604099', now() - interval '9 minutes');

INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido)
VALUES ('f1111111-1111-1111-1111-111111111111','usuario','buenas tardes'),
       ('f2222222-2222-2222-2222-222222222222','usuario','sigo interesado');

-- Conversación con el prefijo pero SIN la columna poblada: prueba que la
-- identidad se puede extraer del propio valor.
INSERT INTO public.agente_comercial_conversaciones
  (id, inmobiliaria_id, telefono, cliente_nombre, kommo_lead_id, kommo_contact_id, created_at)
VALUES
  ('f3333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111',
   'kommo-51111111', '☺️', '60000003', NULL, now() - interval '8 minutes');

INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido)
VALUES ('f3333333-3333-3333-3333-333333333333','usuario','hola');

-- Alguien que sí dio su número, y quedó en la bitácora de herramientas.
INSERT INTO public.agente_comercial_conversaciones
  (id, inmobiliaria_id, telefono, cliente_nombre, kommo_lead_id, kommo_contact_id, created_at)
VALUES
  ('f4444444-4444-4444-4444-444444444444','11111111-1111-1111-1111-111111111111',
   'kommo-52000001', 'Recuperable', '60000004', '52000001', now() - interval '7 minutes');

INSERT INTO public.agente_comercial_mensajes
  (conversacion_id, rol, contenido, herramientas_usadas)
VALUES
  ('f4444444-4444-4444-4444-444444444444','agente','Listo, queda agendada',
   '[{"nombre":"agendar_cita","entrada":{"cliente_telefono":"3009998877"},"salida":{"success":true}}]'::jsonb);

-- Y alguien con DOS números distintos: no se decide solo.
INSERT INTO public.agente_comercial_conversaciones
  (id, inmobiliaria_id, telefono, cliente_nombre, kommo_lead_id, kommo_contact_id, created_at)
VALUES
  ('f5555555-5555-5555-5555-555555555555','11111111-1111-1111-1111-111111111111',
   'kommo-52000002', 'Ambiguo', '60000005', '52000002', now() - interval '6 minutes');

INSERT INTO public.agente_comercial_mensajes
  (conversacion_id, rol, contenido, herramientas_usadas)
VALUES
  ('f5555555-5555-5555-5555-555555555555','agente','ok',
   '[{"nombre":"agendar_cita","entrada":{"cliente_telefono":"3001111111"}},
     {"nombre":"solicitar_apertura_de_agenda","entrada":{"cliente_telefono":"3002222222"}}]'::jsonb);

SELECT crm.backfill('11111111-1111-1111-1111-111111111111');

-- ---------------------------------------------------------------------
SELECT is((SELECT count(*) FROM crm.contactos WHERE nombre = 'JLFR'), 1::bigint,
  'Los gemelos son UNA persona: se unieron por su kommo_contact compartido');

SELECT is(
  (SELECT telefono_e164 FROM crm.contactos WHERE nombre = 'JLFR'),
  '+573201234529',
  'Y el teléfono real quedó puesto: la segunda conversación lo aportó');

SELECT is(
  (SELECT count(*) FROM crm.actividades a
     JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE c.nombre = 'JLFR'),
  2::bigint,
  'Su timeline junta los mensajes de las DOS conversaciones');

SELECT is(
  (SELECT count(*) FROM crm.identidades i
     JOIN crm.contactos c ON c.id = i.contacto_id
    WHERE c.nombre = 'JLFR' AND i.tipo = 'kommo_lead'),
  2::bigint,
  'Conserva los dos leads de Kommo: ninguna pista se tira');

SELECT is(
  (SELECT count(*) FROM crm.identidades i
     JOIN crm.contactos c ON c.id = i.contacto_id
    WHERE c.nombre = '☺️' AND i.tipo = 'kommo_contact' AND i.valor = '51111111'),
  1::bigint,
  'Con la columna vacía, el id se extrae del propio "kommo-51111111"');

-- --- Recuperación de teléfonos ----------------------------------------
SELECT lives_ok(
  $$SELECT crm.recuperar_telefonos_desde_herramientas('11111111-1111-1111-1111-111111111111')$$,
  'La recuperación corre sin errores'
);

SELECT is(
  (SELECT telefono_e164 FROM crm.contactos WHERE nombre = 'Recuperable'),
  '+573009998877',
  'Se recuperó el número que el agente capturó al agendar la cita');

SELECT is(
  (SELECT telefono_e164 FROM crm.contactos WHERE nombre = 'Ambiguo'),
  NULL,
  'Con dos números distintos NO se elige uno: eso es revisión humana');

SELECT * FROM finish();
ROLLBACK;
