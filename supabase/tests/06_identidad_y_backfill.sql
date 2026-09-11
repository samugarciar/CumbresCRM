-- =====================================================================
-- Identidad multicanal y backfill.
--
-- Dos propiedades que el CRM necesita y que son fáciles de romper sin
-- darse cuenta:
--
--   1. UNIFICACIÓN — la misma persona escrita de tres formas distintas,
--      en tres tablas distintas, es UN contacto con UN timeline.
--   2. IDEMPOTENCIA — correr el backfill dos veces no duplica nada. Sin
--      esto, cualquier reintento ensucia la base y nadie se atreve a
--      volver a correrlo.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(12);

-- Estado limpio y determinista: sin lo que el seed y los triggers ya
-- hayan dejado. Todo se revierte al final.
DELETE FROM crm.contactos;
DELETE FROM public.citas;
DELETE FROM public.solicitudes_apertura;
DELETE FROM public.agente_comercial_conversaciones;

-- El backfill existe para datos que YA estaban antes de que hubiera
-- triggers. Se apagan para reproducir esa situación y probarlo solo.
ALTER TABLE public.agente_comercial_mensajes DISABLE TRIGGER crm_proyectar_mensaje;
ALTER TABLE public.citas                     DISABLE TRIGGER crm_proyectar_cita;
ALTER TABLE public.solicitudes_apertura      DISABLE TRIGGER crm_proyectar_solicitud;

-- ---------------------------------------------------------------------
-- Ana: teléfono bueno, y aparece en las TRES fuentes escrita distinto
-- ---------------------------------------------------------------------
INSERT INTO public.agente_comercial_conversaciones
  (id, inmobiliaria_id, telefono, cliente_nombre, kommo_lead_id, kommo_contact_id)
VALUES ('e1111111-1111-1111-1111-111111111111',
        '11111111-1111-1111-1111-111111111111',
        '3001112233', 'Ana Prueba', '51000001', '77000001');

INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido)
VALUES ('e1111111-1111-1111-1111-111111111111', 'usuario', 'Buenas, ¿está disponible?'),
       ('e1111111-1111-1111-1111-111111111111', 'agente',  'Sí, con mucho gusto.');

INSERT INTO public.citas
  (inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono)
VALUES ('11111111-1111-1111-1111-111111111111',
        'a3333333-3333-3333-3333-333333333333',
        'a1111111-1111-1111-1111-111111111111',
        current_date + 1, '11:00', '11:30', 'Ana P.', '+57 300 111 2233');

INSERT INTO public.solicitudes_apertura
  (inmobiliaria_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono)
VALUES ('11111111-1111-1111-1111-111111111111',
        'a1111111-1111-1111-1111-111111111111',
        current_date + 2, '18:00', '19:00', 'ANA PRUEBA', '300 111 22 33');

-- ---------------------------------------------------------------------
-- Beto: de los 225 reales — conversación de verdad, sin teléfono usable
-- ---------------------------------------------------------------------
INSERT INTO public.agente_comercial_conversaciones
  (id, inmobiliaria_id, telefono, cliente_nombre, kommo_lead_id, kommo_contact_id)
VALUES ('e2222222-2222-2222-2222-222222222222',
        '11111111-1111-1111-1111-111111111111',
        '50123456', 'Beto Prueba', '51000002', '77000002');

INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido)
VALUES ('e2222222-2222-2222-2222-222222222222', 'usuario', 'Hola');

-- ---------------------------------------------------------------------
SELECT lives_ok(
  $$SELECT crm.backfill('11111111-1111-1111-1111-111111111111')$$,
  'El backfill corre sin errores'
);

SELECT is((SELECT count(*) FROM crm.contactos), 2::bigint,
  'Dos personas: Ana aparece en tres fuentes pero es UN contacto');

SELECT is(
  (SELECT telefono_e164 FROM crm.contactos WHERE nombre LIKE 'Ana%'),
  '+573001112233',
  'Ana quedó con su teléfono normalizado, escrito de tres formas distintas');

SELECT is(
  (SELECT count(*) FROM crm.identidades i
     JOIN crm.contactos c ON c.id = i.contacto_id
    WHERE c.nombre LIKE 'Ana%'),
  3::bigint,
  'Ana tiene tres identidades: teléfono, lead y contacto de Kommo');

-- Cuatro y no tres: lo que escribió Ana y lo que contestó el bot son
-- hechos distintos, y el timeline los separa. Esa distinción es lo que
-- permite después responder "¿quién le habló y quién no?".
SELECT is(
  (SELECT count(DISTINCT a.tipo) FROM crm.actividades a
     JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE c.nombre LIKE 'Ana%'),
  4::bigint,
  'Su timeline junta mensaje del cliente, respuesta del bot, visita y solicitud');

SELECT is(
  (SELECT count(*) FROM crm.actividades a
     JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE c.nombre LIKE 'Ana%' AND a.origen = 'agente_ia'),
  1::bigint,
  'Y la respuesta del bot queda marcada como tal, no como si fuera un asesor');

-- --- Beto: el caso de los 225 -----------------------------------------
SELECT is(
  (SELECT telefono_e164 FROM crm.contactos WHERE nombre = 'Beto Prueba'),
  NULL,
  'Beto no tiene teléfono: el valor raro no se convierte en llave');

SELECT is(
  (SELECT telefono_crudo FROM crm.contactos WHERE nombre = 'Beto Prueba'),
  '50123456',
  'Pero el valor crudo se conserva, para poder revisarlo a mano');

SELECT is(
  (SELECT count(*) FROM crm.identidades i
     JOIN crm.contactos c ON c.id = i.contacto_id
    WHERE c.nombre = 'Beto Prueba' AND i.tipo = 'kommo_lead'),
  1::bigint,
  'Beto SÍ es reconocible: entra con su identidad de Kommo');

SELECT isnt(
  (SELECT ultima_actividad_at FROM crm.contactos WHERE nombre LIKE 'Ana%'),
  NULL,
  'La bandeja sabe por dónde ordenar: última actividad poblada');

-- --- Idempotencia ------------------------------------------------------
-- Sin esto nadie se atreve a reejecutar el backfill, y un backfill que
-- solo se puede correr una vez es un backfill que no se puede arreglar.
SELECT is(
  (WITH antes AS (SELECT count(*) n FROM crm.contactos),
        corrida AS (SELECT crm.backfill('11111111-1111-1111-1111-111111111111')),
        despues AS (SELECT count(*) n FROM crm.contactos)
   SELECT (SELECT n FROM despues) - (SELECT n FROM antes)),
  0::bigint,
  'Correrlo otra vez no crea ni un contacto de más');

SELECT is(
  (SELECT count(*) FROM crm.actividades),
  5::bigint,
  'Ni una actividad de más: 2 mensajes de Ana + visita + solicitud + 1 de Beto');

SELECT * FROM finish();
ROLLBACK;
