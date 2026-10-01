-- =====================================================================
-- La ventana de 24 h, por número.
--
-- Dos cosas que importan por igual:
--   · que HOY, sin la columna en public, la proyección siga funcionando
--     exactamente igual — es el camino de cada mensaje de cada cliente;
--   · que el día que la plataforma cree la columna, el número llegue
--     solo y la ventana se mida por línea.
-- La columna de la plataforma se SIMULA aquí con un ALTER dentro de la
-- transacción, que se deshace al final: es la forma real que tendrá.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(18);

DELETE FROM crm.lineas;

INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre) VALUES
  ('11111111-1111-1111-1111-111111111111', 'comercial',      '360000000000001', 'Comercial'),
  ('11111111-1111-1111-1111-111111111111', 'administrativa', '360000000000002', 'Administrativa'),
  ('22222222-2222-2222-2222-222222222222', 'comercial',      '360000000000009', 'Comercial Beta');

INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono) VALUES
  ('f3600001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '+573003601111'),
  ('f3600002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', '+573003602222');

-- --- Hoy: public no tiene la columna --------------------------------------
INSERT INTO public.agente_comercial_mensajes (id, conversacion_id, rol, contenido)
VALUES ('f3600010-0000-0000-0000-000000000010', 'f3600001-0000-0000-0000-000000000001',
        'usuario', 'Hola, ¿siguen teniendo el apartamento?');

SELECT is(
  (SELECT count(*)::int FROM crm.actividades
    WHERE metadata->>'origen_id' = 'f3600010-0000-0000-0000-000000000010'),
  1,
  'Sin la columna en public, la proyección funciona igual que siempre'
);

SELECT is(
  (SELECT wa_phone_number_id FROM crm.actividades
    WHERE metadata->>'origen_id' = 'f3600010-0000-0000-0000-000000000010'),
  NULL,
  'Y el mensaje entra sin número'
);

SELECT is(
  (SELECT count(*)::int FROM crm.eventos WHERE estado = 'fallido'
    AND fila_origen_id = 'f3600010-0000-0000-0000-000000000010'),
  0,
  'Sin dejar ningún fallo en crm.eventos'
);

-- --- El día que la plataforma cree la columna ------------------------------
ALTER TABLE public.agente_comercial_mensajes ADD COLUMN wa_phone_number_id text;

-- Persona 2: le escribió a la comercial hace 1 h y a la administrativa
-- hace 30 h. Ningún mensaje sin número.
INSERT INTO public.agente_comercial_mensajes
  (id, conversacion_id, rol, contenido, created_at, wa_phone_number_id) VALUES
  ('f3600020-0000-0000-0000-000000000020', 'f3600002-0000-0000-0000-000000000002',
   'usuario', '¿Y el de Laureles?', now() - interval '1 hour', '360000000000001'),
  ('f3600021-0000-0000-0000-000000000021', 'f3600002-0000-0000-0000-000000000002',
   'usuario', 'Ya pagué el canon de este mes', now() - interval '30 hours', '360000000000002'),
  ('f3600022-0000-0000-0000-000000000022', 'f3600002-0000-0000-0000-000000000002',
   'usuario', 'Gracias', now() - interval '40 hours', '   ');

CREATE TEMP TABLE c AS
  SELECT id FROM crm.contactos WHERE telefono_e164 = '+573003602222';
GRANT SELECT ON c TO authenticated;

SELECT is(
  (SELECT wa_phone_number_id FROM crm.actividades
    WHERE metadata->>'origen_id' = 'f3600020-0000-0000-0000-000000000020'),
  '360000000000001',
  'Con la columna, el número llega solo a la actividad'
);

SELECT is(
  (SELECT wa_phone_number_id FROM crm.actividades
    WHERE metadata->>'origen_id' = 'f3600022-0000-0000-0000-000000000022'),
  NULL,
  'Un número en blanco cuenta como ninguno'
);

-- --- La ventana, por línea -------------------------------------------------
SELECT ok(
  crm.puede_escribir_libre((SELECT id FROM c)),
  'Sin pedir línea, la ventana es la de siempre: escribió hace 1 h'
);

SELECT ok(
  crm.puede_escribir_libre((SELECT id FROM c), '360000000000001'),
  'Por la comercial, abierta: le escribió por ahí hace 1 h'
);

SELECT ok(
  NOT crm.puede_escribir_libre((SELECT id FROM c), '360000000000002'),
  'Por la administrativa, CERRADA: su último mensaje por ahí fue hace 30 h'
);

SELECT is(
  crm.ventana_whatsapp((SELECT id FROM c), '360000000000002'),
  now() - interval '30 hours' + interval '24 hours',
  'Y la ventana de esa línea cerró a las 24 h de ese mensaje'
);

-- Persona 1 solo tiene un mensaje SIN número, de ahora mismo.
SELECT ok(
  crm.puede_escribir_libre((SELECT id FROM crm.contactos WHERE telefono_e164 = '+573003601111'),
                           '360000000000002'),
  'Un mensaje sin número abre la ventana de todas las líneas: es lo de antes, y caduca solo'
);

-- --- encolar_envio, que es donde la regla no se puede saltar --------------
SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$SELECT crm.encolar_envio((SELECT id FROM c), 'Le confirmo el pago', NULL, NULL, '360000000000002')$$,
  '23514', NULL,
  'Texto libre por la línea cerrada se rechaza, aunque la otra línea esté abierta'
);

SELECT lives_ok(
  $$SELECT crm.encolar_envio((SELECT id FROM c), 'Sí, sigue disponible', NULL, NULL, '360000000000001')$$,
  'Por la línea abierta, pasa'
);

SELECT is(
  (SELECT wa_phone_number_id FROM crm.envios WHERE cuerpo = 'Sí, sigue disponible'),
  '360000000000001',
  'Y el envío queda anotado con su línea'
);

SELECT lives_ok(
  $$SELECT crm.encolar_envio(p_contacto_id => (SELECT id FROM c), p_cuerpo => 'Sin línea')$$,
  'La llamada de antes, sin línea y con argumentos con nombre, sigue funcionando'
);

SELECT throws_ok(
  $$SELECT crm.encolar_envio((SELECT id FROM c), 'Hola', NULL, NULL, '360000000000009')$$,
  '22023', NULL,
  'Encolar por una línea de otra inmobiliaria se rechaza'
);

RESET ROLE;

-- --- El reintento: un mensaje de un asesor, por crm.backfill ---------------
INSERT INTO public.agente_comercial_mensajes
  (id, conversacion_id, rol, contenido, wa_phone_number_id)
VALUES ('f3600030-0000-0000-0000-000000000030', 'f3600002-0000-0000-0000-000000000002',
        'asesor', 'Hola, soy Gisela, te ayudo con el pago', '360000000000002');

-- Como si la proyección en vivo hubiera fallado: se borra y se reintenta
-- por el mismo camino que usa crm.reintentar_eventos.
DELETE FROM crm.actividades WHERE metadata->>'origen_id' = 'f3600030-0000-0000-0000-000000000030';
SELECT lives_ok(
  $$SELECT crm.backfill('11111111-1111-1111-1111-111111111111')$$,
  'El reintento corre'
);

SELECT is(
  (SELECT origen FROM crm.actividades
    WHERE metadata->>'origen_id' = 'f3600030-0000-0000-0000-000000000030'),
  'humano',
  'Reintentado, el mensaje de un asesor es de una PERSONA, no del bot'
);

SELECT is(
  (SELECT wa_phone_number_id FROM crm.actividades
    WHERE metadata->>'origen_id' = 'f3600030-0000-0000-0000-000000000030'),
  '360000000000002',
  'Y conserva su número'
);

SELECT * FROM finish();
ROLLBACK;
