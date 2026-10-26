-- =====================================================================
-- Una sola regla para «Esperando respuesta» (20261026100001).
--
-- La bandeja (filtro 🔥 y columna), los contadores de las pestañas y la
-- ficha tienen que dar LA MISMA respuesta. Antes la bandeja tomaba la
-- respuesta del bot como atención y la ficha contaba el aviso de
-- cambiar_bot como si alguien hubiera contestado.
--
-- Cada caso se pregunta a las tres funciones a la vez.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(11);

DELETE FROM crm.contactos WHERE inmobiliaria_id = '11111111-1111-1111-1111-111111111111';

-- Seis personas de Alfa. Todas escribieron hace 30 minutos.
INSERT INTO crm.contactos
  (id, inmobiliaria_id, nombre, telefono_e164, bot_activo, bot_motivo, bot_cambiado_at)
VALUES
  ('e4800001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Bot activo que contestó', '+573004800001', true, NULL, NULL),
  ('e4800002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'Callado por relevo, solo contestó el bot', '+573004800002', false, 'relevo', now() - interval '20 minutes'),
  ('e4800003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
   'Callado por escalamiento, solo contestó el bot', '+573004800003', false, 'escalamiento', now() - interval '20 minutes'),
  ('e4800004-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111',
   'Le contestó un asesor', '+573004800004', false, 'relevo', now() - interval '20 minutes'),
  ('e4800005-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111',
   'Marcado como atendido', '+573004800005', true, NULL, NULL),
  ('e4800006-0000-0000-0000-000000000006', '11111111-1111-1111-1111-111111111111',
   'Solo le cambiaron el bot', '+573004800006', true, NULL, NULL);

INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, creado_por)
SELECT '11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
       c.id, '¿Sigue disponible?', now() - interval '30 minutes', NULL
  FROM crm.contactos c
 WHERE c.inmobiliaria_id = '11111111-1111-1111-1111-111111111111';

-- El bot les contestó a los tres primeros.
INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'mensaje_saliente', 'agente_ia',
   'e4800001-0000-0000-0000-000000000001', 'Sí, sigue disponible', now() - interval '29 minutes'),
  ('11111111-1111-1111-1111-111111111111', 'mensaje_saliente', 'agente_ia',
   'e4800002-0000-0000-0000-000000000002', 'Sí, sigue disponible', now() - interval '29 minutes'),
  ('11111111-1111-1111-1111-111111111111', 'mensaje_saliente', 'agente_ia',
   'e4800003-0000-0000-0000-000000000003', 'Ya te paso con un asesor', now() - interval '29 minutes');

-- Al cuarto le escribió una persona del equipo desde el CRM.
INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, creado_por)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'mensaje_saliente', 'humano',
   'e4800004-0000-0000-0000-000000000004', 'Hola, te escribe Julián', now() - interval '20 minutes',
   'cccccccc-cccc-cccc-cccc-cccccccccccc');

-- Compara las tres funciones para un contacto. Devuelve un texto con
-- los tres valores para que el mensaje de falla diga cuál discrepa.
CREATE FUNCTION pg_temp.las_tres(p_id uuid) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT format('bandeja=%s filtro=%s ficha=%s',
    (SELECT esperando_respuesta FROM crm.bandeja_contactos(p_limite => 200) b WHERE b.id = p_id),
    EXISTS (SELECT 1 FROM crm.bandeja_contactos(p_limite => 200, p_solo_esperando => true) b WHERE b.id = p_id)
      AND NOT EXISTS (SELECT 1 FROM crm.bandeja_contactos(p_limite => 200, p_solo_esperando => false) b WHERE b.id = p_id),
    (SELECT esperando_segundos IS NOT NULL FROM crm.resumen_contacto(p_id)))
$$;
GRANT EXECUTE ON FUNCTION pg_temp.las_tres(uuid) TO authenticated;

SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(pg_temp.las_tres('e4800001-0000-0000-0000-000000000001'),
  'bandeja=f filtro=f ficha=f',
  'Bot activo y ya contestó: no espera, ni en la bandeja ni en el filtro ni en la ficha');

SELECT is(pg_temp.las_tres('e4800002-0000-0000-0000-000000000002'),
  'bandeja=t filtro=t ficha=t',
  'Bot callado por relevo y solo contestó el bot: espera en las tres');

SELECT is(pg_temp.las_tres('e4800003-0000-0000-0000-000000000003'),
  'bandeja=t filtro=t ficha=t',
  'Bot callado por escalamiento y solo contestó el bot: espera en las tres');

SELECT is(pg_temp.las_tres('e4800004-0000-0000-0000-000000000004'),
  'bandeja=f filtro=f ficha=f',
  'Le contestó un asesor: no espera');

SELECT is(pg_temp.las_tres('e4800005-0000-0000-0000-000000000005'),
  'bandeja=t filtro=t ficha=t',
  'Nadie le ha contestado: espera');

SELECT lives_ok(
  $$SELECT crm.marcar_atendido('e4800005-0000-0000-0000-000000000005')$$,
  'Se marca como atendido'
);

SELECT is(pg_temp.las_tres('e4800005-0000-0000-0000-000000000005'),
  'bandeja=f filtro=f ficha=f',
  'La nota de «marcar atendido» cuenta como respuesta del equipo');

SELECT lives_ok(
  $$SELECT crm.cambiar_bot('e4800006-0000-0000-0000-000000000006', false)$$,
  'Se apaga el bot a mano, sin escribirle'
);

SELECT is(pg_temp.las_tres('e4800006-0000-0000-0000-000000000006'),
  'bandeja=t filtro=t ficha=t',
  'Apagar el bot no es responder: deja un aviso de sistema y la persona sigue esperando');

SELECT ok(
  (SELECT esperando_segundos FROM crm.resumen_contacto('e4800006-0000-0000-0000-000000000006'))
    BETWEEN 1700 AND 1900,
  'Y la ficha cuenta la espera desde su último mensaje (~30 min)'
);

-- El número 🔥 de la pestaña es el número de filas del filtro.
SELECT is(
  (SELECT comercial_esperando FROM crm.conteo_bandeja()),
  (SELECT count(*) FROM crm.bandeja_contactos(p_limite => 200, p_canal => 'comercial', p_solo_esperando => true)),
  'El 🔥 de la pestaña Comercial coincide con las filas del filtro'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
