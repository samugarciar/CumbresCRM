-- =====================================================================
-- Las citas que ya tenía una persona se enlazan cuando entra al CRM
-- (20261026100007).
--
-- Con solo líneas oficiales, la cita de alguien que el CRM no conoce no
-- entra. Cuando esa persona escribe por la línea oficial y nace su
-- contacto, sus citas futuras y sus solicitudes pendientes aparecen en su
-- ficha.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(7);

DELETE FROM crm.lineas;
DELETE FROM crm.contactos;
DELETE FROM crm.preferencias;
DELETE FROM public.citas;
DELETE FROM public.solicitudes_apertura;

INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre)
VALUES ('11111111-1111-1111-1111-111111111111', 'comercial', '540000000000001', 'Comercial 312');

INSERT INTO crm.preferencias (inmobiliaria_id, solo_lineas_oficiales, solo_lineas_desde)
VALUES ('11111111-1111-1111-1111-111111111111', true, now() - interval '1 day');

-- El agente le agendó por la 324 (Kommo) antes de que existiera en el CRM:
-- una visita de mañana, una de la semana pasada, y pidió otro horario.
INSERT INTO public.citas
  (id, inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono)
VALUES
  ('cc540001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'a3333333-3333-3333-3333-333333333333', 'a1111111-1111-1111-1111-111111111111',
   crm.hoy() + 1, '09:00', '09:30', 'Agendada antes', '300 540 00 01'),
  ('cc540002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'a3333333-3333-3333-3333-333333333333', 'a1111111-1111-1111-1111-111111111111',
   crm.hoy() - 7, '09:00', '09:30', 'Agendada antes', '+573005400001'),
  -- La de otra persona no se le pega.
  ('cc540003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
   'a3333333-3333-3333-3333-333333333333', 'a1111111-1111-1111-1111-111111111111',
   crm.hoy() + 1, '10:00', '10:30', 'Otra persona', '+573005409999');

INSERT INTO public.solicitudes_apertura
  (inmobiliaria_id, inmueble_id, fecha, hora_inicio, hora_fin, cliente_nombre, cliente_telefono)
VALUES ('11111111-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111',
        crm.hoy() + 2, '18:00', '19:00', 'Agendada antes', '3005400001');

SELECT is(
  (SELECT count(*)::int FROM crm.contactos WHERE telefono_e164 = '+573005400001'),
  0,
  'Con solo líneas oficiales, la cita de alguien que no está en el CRM no lo crea'
);

-- Ahora escribe por la línea oficial: nace su contacto.
INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono, cliente_nombre)
VALUES ('e5400001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        '+573005400001', 'Agendada antes');
INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido, wa_phone_number_id, wa_message_id)
VALUES ('e5400001-0000-0000-0000-000000000001', 'usuario', 'Hola, ¿me confirman la visita de mañana?',
        '540000000000001', 'wamid.54.1');

SELECT is(
  (SELECT count(*)::int FROM crm.contactos WHERE telefono_e164 = '+573005400001'),
  1,
  'Nace el contacto'
);

SELECT is(
  (SELECT a.cita_id FROM crm.actividades a JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE c.telefono_e164 = '+573005400001' AND a.tipo = 'visita_agendada'),
  'cc540001-0000-0000-0000-000000000001'::uuid,
  'Y su visita de mañana, agendada antes de que existiera, queda enlazada'
);

SELECT is(
  (SELECT count(*)::int FROM crm.actividades WHERE cita_id = 'cc540002-0000-0000-0000-000000000002'),
  0,
  'La de la semana pasada no: solo las de hoy en adelante'
);

SELECT is(
  (SELECT count(*)::int FROM crm.actividades a JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE c.telefono_e164 = '+573005400001' AND a.tipo = 'solicitud_apertura'),
  1,
  'Y el horario que pidió y sigue pendiente'
);

SELECT is(
  (SELECT count(*)::int FROM crm.actividades WHERE cita_id = 'cc540003-0000-0000-0000-000000000003'),
  0,
  'La cita de otra persona no se le pega'
);

-- Idempotente: si la cita cambia y la proyección normal corre, no se duplica.
UPDATE public.citas SET notas = 'Trae los documentos' WHERE id = 'cc540001-0000-0000-0000-000000000001';

SELECT is(
  (SELECT count(*)::int FROM crm.actividades
    WHERE cita_id = 'cc540001-0000-0000-0000-000000000001' AND tipo = 'visita_agendada'),
  1,
  'Una sola visita agendada aunque la proyección de la cita vuelva a correr'
);

SELECT * FROM finish();
ROLLBACK;
