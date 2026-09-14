-- =====================================================================
-- Cerrar las oportunidades que se apagaron.
--
-- Lo que se mide: que cierre a quien lleva meses callado, que NO cierre
-- a quien está esperando respuesta nuestra, que NO cierre a quien tiene
-- una visita por delante, y que todo lo que cierre se pueda deshacer.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(12);

DELETE FROM crm.contactos;

INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, ultima_actividad_at)
VALUES
  ('aa000001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Fantasma', '+573001110001', now() - interval '60 days'),
  ('aa000002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'Esperando respuesta', '+573001110002', now() - interval '60 days'),
  ('aa000004-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111',
   'Reciente', '+573001110004', now() - interval '2 days');

-- Fantasma: habló el bot al final y el cliente no volvió.
INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, ocurrido_at, metadata)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
   'aa000001-0000-0000-0000-000000000001', now() - interval '61 days', '{"origen_tabla":"t","origen_id":"f1"}'),
  ('11111111-1111-1111-1111-111111111111', 'mensaje_saliente', 'agente_ia',
   'aa000001-0000-0000-0000-000000000001', now() - interval '60 days', '{"origen_tabla":"t","origen_id":"f2"}'),
-- Esperando respuesta: el ÚLTIMO que habló fue el cliente.
  ('11111111-1111-1111-1111-111111111111', 'mensaje_saliente', 'agente_ia',
   'aa000002-0000-0000-0000-000000000002', now() - interval '61 days', '{"origen_tabla":"t","origen_id":"e1"}'),
  ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
   'aa000002-0000-0000-0000-000000000002', now() - interval '60 days', '{"origen_tabla":"t","origen_id":"e2"}'),
-- Reciente: habló hace dos días.
  ('11111111-1111-1111-1111-111111111111', 'mensaje_saliente', 'agente_ia',
   'aa000004-0000-0000-0000-000000000004', now() - interval '2 days', '{"origen_tabla":"t","origen_id":"r1"}');

-- La cita futura del tercero.
INSERT INTO public.citas
  (id, inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono)
VALUES ('cc00aa01-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'a3333333-3333-3333-3333-333333333333',
        'a1111111-1111-1111-1111-111111111111',
        current_date + 5, '09:00', '09:30',
        'Con visita pendiente', '+573001110003');

-- Al tercero lo crea la proyección de la cita, y se le envejece todo a
-- mano: así lo ÚNICO que lo salva de ser un fantasma es tener una visita
-- por delante, que es justo lo que esta prueba mide.
UPDATE crm.contactos SET ultima_actividad_at = now() - interval '60 days'
 WHERE telefono_e164 = '+573001110003';

-- Ya no hace falta envejecer `etapa_at`: la guarda pregunta por
-- transiciones HUMANAS, no por el reloj de la etapa. Se comprueba justo
-- eso — que una tarjeta que alguien movió a mano hoy NO se cierre aunque
-- la persona lleve 60 días callada.
SELECT crm.mover_etapa(
  (SELECT id FROM crm.oportunidades WHERE contacto_id = 'aa000004-0000-0000-0000-000000000004'),
  'calificado', 'la trabajo yo');

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades WHERE estado = 'abierta'),
  4,
  'De partida hay cuatro oportunidades abiertas'
);

-- --- El cierre --------------------------------------------------------
SELECT is(
  crm.cerrar_fantasmas(30),
  1,
  'Solo se cierra UNA de las cuatro'
);

SELECT is(
  (SELECT estado FROM crm.oportunidades
    WHERE contacto_id = 'aa000001-0000-0000-0000-000000000001'),
  'perdida',
  'La que lleva 60 días callada, cerrada'
);

SELECT is(
  (SELECT motivo_perdida FROM crm.oportunidades
    WHERE contacto_id = 'aa000001-0000-0000-0000-000000000001'),
  'no_responde',
  'Con motivo, porque perder sin motivo es perder el dato'
);

-- LA AFIRMACIÓN QUE MÁS IMPORTA de este archivo: si el último que habló
-- fue el cliente, el silencio es NUESTRO. Cerrarlo como "no responde"
-- sería echarle a él la culpa de que no le contestamos.
SELECT is(
  (SELECT estado FROM crm.oportunidades
    WHERE contacto_id = 'aa000002-0000-0000-0000-000000000002'),
  'abierta',
  'Quien escribió último y espera respuesta NO se cierra: el callado somos nosotros'
);

SELECT is(
  (SELECT o.estado FROM crm.oportunidades o
     JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573001110003'),
  'abierta',
  'Quien tiene una visita por delante tampoco: eso no es un fantasma'
);

SELECT is(
  (SELECT estado FROM crm.oportunidades
    WHERE contacto_id = 'aa000004-0000-0000-0000-000000000004'),
  'abierta',
  'Y quien habló hace dos días, menos'
);

-- --- La huella --------------------------------------------------------
SELECT is(
  (SELECT cerrada_por FROM crm.oportunidades
    WHERE contacto_id = 'aa000001-0000-0000-0000-000000000001'),
  NULL,
  'cerrada_por en NULL: la huella de que esto lo cerró una regla, no una persona'
);

SELECT is(
  (SELECT t.origen FROM crm.transiciones t
     JOIN crm.oportunidades o ON o.id = t.oportunidad_id
    WHERE o.contacto_id = 'aa000001-0000-0000-0000-000000000001'
    ORDER BY t.id DESC LIMIT 1),
  'sistema',
  'Y el historial dice que fue el sistema: así se pueden encontrar todos'
);

-- --- Deshacer ---------------------------------------------------------
-- Una función que cierra en masa sin una que reabra es una función en la
-- que no se puede confiar.
SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT lives_ok(
  format($$SELECT crm.reabrir_oportunidad(%L)$$,
         (SELECT id FROM crm.oportunidades
           WHERE contacto_id = 'aa000001-0000-0000-0000-000000000001')),
  'Se puede reabrir'
);

SELECT is(
  (SELECT estado FROM crm.oportunidades
    WHERE contacto_id = 'aa000001-0000-0000-0000-000000000001'),
  'abierta',
  'Y vuelve a estar viva, con su etapa intacta'
);

RESET ROLE;

-- Y reabrir REINICIA el reloj, así que el cron de esta noche no la vuelve
-- a cerrar. Sin eso, reabrir sería un pulso contra el cron que el asesor
-- pierde siempre.
SELECT is(
  crm.cerrar_fantasmas(30),
  0,
  'La reabierta NO se vuelve a cerrar: reabrir le da 30 días nuevos'
);

SELECT * FROM finish();
ROLLBACK;
