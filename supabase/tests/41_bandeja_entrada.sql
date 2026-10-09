-- =====================================================================
-- Pruebas de Bandeja de Entrada: Turno de respuesta, último mensaje,
-- filtro p_solo_esperando y función marcar_atendido.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(8);

-- Limpieza
DELETE FROM crm.lineas;
DELETE FROM crm.contactos;
DELETE FROM crm.eventos;

-- 1. Crear contacto y mensaje entrante
INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono, cliente_nombre)
VALUES ('f4100001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '+573004100001', 'Cliente Esperando');

INSERT INTO public.agente_comercial_mensajes
  (id, conversacion_id, rol, contenido, created_at)
VALUES
  ('f4100010-0000-0000-0000-000000000010', 'f4100001-0000-0000-0000-000000000001',
   'usuario', 'Hola, sigo esperando respuesta sobre el apartamento', now() - interval '10 minutes');

CREATE TEMP TABLE c_espera AS
  SELECT id FROM crm.contactos WHERE telefono_e164 = '+573004100001';

GRANT SELECT ON c_espera TO authenticated;

SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

-- Test 1: esperando_respuesta es true
SELECT is(
  (SELECT esperando_respuesta FROM crm.bandeja_contactos() WHERE id = (SELECT id FROM c_espera)),
  true,
  'Contacto con mensaje entrante sin responder tiene esperando_respuesta = true'
);

-- Test 2: ultimo_mensaje trae el texto entrante
SELECT is(
  (SELECT ultimo_mensaje FROM crm.bandeja_contactos() WHERE id = (SELECT id FROM c_espera)),
  'Hola, sigo esperando respuesta sobre el apartamento',
  'ultimo_mensaje contiene el texto del mensaje más reciente'
);

-- Test 3: Filtro p_solo_esperando => true lo incluye
SELECT is(
  (SELECT count(*)::int FROM crm.bandeja_contactos(p_solo_esperando => true) WHERE id = (SELECT id FROM c_espera)),
  1,
  'Filtro p_solo_esperando => true incluye al contacto que espera'
);

-- Test 4: Filtro p_solo_esperando => false lo excluye
SELECT is(
  (SELECT count(*)::int FROM crm.bandeja_contactos(p_solo_esperando => false) WHERE id = (SELECT id FROM c_espera)),
  0,
  'Filtro p_solo_esperando => false excluye al contacto que espera'
);

-- Test 5: marcar_atendido ejecuta con éxito
SELECT lives_ok(
  $$SELECT crm.marcar_atendido((SELECT id FROM c_espera))$$,
  'crm.marcar_atendido ejecuta sin error como usuario autenticado'
);

-- Test 6: Tras marcar_atendido, esperando_respuesta pasa a false
SELECT is(
  (SELECT esperando_respuesta FROM crm.bandeja_contactos() WHERE id = (SELECT id FROM c_espera)),
  false,
  'Tras marcar_atendido, esperando_respuesta pasa a false'
);

-- Test 7: Tras marcar_atendido, sin_leer es 0
SELECT is(
  (SELECT sin_leer FROM crm.bandeja_contactos() WHERE id = (SELECT id FROM c_espera)),
  0::bigint,
  'Tras marcar_atendido, sin_leer es 0'
);

-- Test 8: Se dejó rastro de la nota en actividades
RESET ROLE;

SELECT is(
  (SELECT count(*)::int FROM crm.actividades WHERE contacto_id = (SELECT id FROM c_espera) AND tipo = 'nota' AND cuerpo = 'Conversación marcada como atendida'),
  1,
  'marcar_atendido inserta una actividad de tipo nota'
);

SELECT * FROM finish();
ROLLBACK;
