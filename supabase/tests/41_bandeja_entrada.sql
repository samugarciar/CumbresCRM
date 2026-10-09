-- =====================================================================
-- Pruebas de Bandeja de Entrada: Turno de respuesta, último mensaje,
-- filtro p_solo_esperando y función marcar_atendido.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(14);

-- Limpieza
DELETE FROM crm.lineas;
DELETE FROM crm.contactos;
DELETE FROM crm.eventos;

-- Simular columna wa_phone_number_id en public si no existe en la linea base
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'agente_comercial_mensajes' AND column_name = 'wa_phone_number_id'
  ) THEN
    ALTER TABLE public.agente_comercial_mensajes ADD COLUMN wa_phone_number_id text;
  END IF;
END $$;

-- 0. Crear líneas para Alfa
INSERT INTO crm.lineas (inmobiliaria_id, wa_phone_number_id, telefono_e164, nombre, embudo, activa)
VALUES
  ('11111111-1111-1111-1111-111111111111', '100000000000041', '+573241234541', 'Línea Comercial 324', 'comercial', true),
  ('11111111-1111-1111-1111-111111111111', '100000000000042', '+573201234542', 'Línea Administrativa 320', 'administrativa', true);

-- 1. Crear contacto comercial y mensaje entrante
INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono, cliente_nombre)
VALUES ('f4100001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '+573004100001', 'Cliente Comercial');

INSERT INTO public.agente_comercial_mensajes
  (id, conversacion_id, rol, contenido, wa_phone_number_id, created_at)
VALUES
  ('f4100010-0000-0000-0000-000000000010', 'f4100001-0000-0000-0000-000000000001',
   'usuario', 'Hola, sigo esperando respuesta sobre el apartamento', '100000000000041', now() - interval '10 minutes');

-- 2. Crear contacto administrativo por la línea 320
INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono, cliente_nombre)
VALUES ('f4100002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', '+573004100002', 'Inquilino Admin');

INSERT INTO public.agente_comercial_mensajes
  (id, conversacion_id, rol, contenido, wa_phone_number_id, created_at)
VALUES
  ('f4100020-0000-0000-0000-000000000020', 'f4100002-0000-0000-0000-000000000002',
   'usuario', 'Tengo un daño en la tubería del baño', '100000000000042', now() - interval '5 minutes');

CREATE TEMP TABLE c_espera AS
  SELECT id FROM crm.contactos WHERE telefono_e164 = '+573004100001';

CREATE TEMP TABLE c_admin AS
  SELECT id FROM crm.contactos WHERE telefono_e164 = '+573004100002';

GRANT SELECT ON c_espera TO authenticated;
GRANT SELECT ON c_admin TO authenticated;

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

-- Test 5: Filtro por canal 'comercial' solo trae el contacto comercial
SELECT is(
  (SELECT count(*)::int FROM crm.bandeja_contactos(p_canal => 'comercial') WHERE id = (SELECT id FROM c_admin)),
  0,
  'Filtro p_canal => comercial excluye al contacto administrativo'
);

-- Test 6: Filtro por canal 'administrativa_captacion' solo trae el contacto administrativo
SELECT is(
  (SELECT count(*)::int FROM crm.bandeja_contactos(p_canal => 'administrativa_captacion') WHERE id = (SELECT id FROM c_admin)),
  1,
  'Filtro p_canal => administrativa_captacion incluye al contacto administrativo'
);

-- Test 7: Metadatos de canal y linea_nombre son correctos
SELECT is(
  (SELECT canal FROM crm.bandeja_contactos() WHERE id = (SELECT id FROM c_admin)),
  'administrativa',
  'Metadato canal es administrativa para el contacto del 320'
);

SELECT is(
  (SELECT linea_nombre FROM crm.bandeja_contactos() WHERE id = (SELECT id FROM c_admin)),
  'Línea Administrativa 320',
  'Metadato linea_nombre refleja Línea Administrativa 320'
);

-- Test 9: crm.conteo_bandeja desglosa correctamente
SELECT is(
  (SELECT comercial_esperando FROM crm.conteo_bandeja()),
  1::bigint,
  'conteo_bandeja reporta 1 contacto comercial esperando'
);

SELECT is(
  (SELECT admin_captacion_esperando FROM crm.conteo_bandeja()),
  1::bigint,
  'conteo_bandeja reporta 1 contacto administrativo esperando'
);

-- Test 11: marcar_atendido ejecuta con éxito
SELECT lives_ok(
  $$SELECT crm.marcar_atendido((SELECT id FROM c_espera))$$,
  'crm.marcar_atendido ejecuta sin error como usuario autenticado'
);

-- Test 12: Tras marcar_atendido, esperando_respuesta pasa a false
SELECT is(
  (SELECT esperando_respuesta FROM crm.bandeja_contactos() WHERE id = (SELECT id FROM c_espera)),
  false,
  'Tras marcar_atendido, esperando_respuesta pasa a false'
);

-- Test 13: Tras marcar_atendido, sin_leer es 0
SELECT is(
  (SELECT sin_leer FROM crm.bandeja_contactos() WHERE id = (SELECT id FROM c_espera)),
  0::bigint,
  'Tras marcar_atendido, sin_leer es 0'
);

-- Test 14: Se dejó rastro de la nota en actividades
RESET ROLE;

SELECT is(
  (SELECT count(*)::int FROM crm.actividades WHERE contacto_id = (SELECT id FROM c_espera) AND tipo = 'nota' AND cuerpo = 'Conversación marcada como atendida'),
  1,
  'marcar_atendido inserta una actividad de tipo nota'
);

SELECT * FROM finish();
ROLLBACK;
