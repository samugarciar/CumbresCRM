-- =====================================================================
-- El request_id de la sincronización (decisión 28, segunda mitad).
--
-- Dos cosas a la vez: que el recibo de Meta se guarde bien, y que la
-- firma de registrar_estado_linea siga aceptando TODAS las llamadas que
-- aceptaba antes. Añadir un parámetro crea una función nueva; si la vieja
-- no se borra, quedan dos y la llamada de cinco argumentos se vuelve
-- ambigua. Las llamadas de abajo son las del contrato de la nota 9, tal
-- como las escribirá la plataforma.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(20);

DELETE FROM crm.lineas;

SELECT ok(
  crm.conectar_linea('11111111-1111-1111-1111-111111111111', 'comercial',
                     'waba-alfa', '310000000000001', 'coexistencia',
                     'EAAG-token-31') IS NOT NULL,
  'La línea comercial queda conectada'
);

-- --- La firma ----------------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'crm' AND p.proname = 'registrar_estado_linea'),
  1,
  'Hay UNA sola registrar_estado_linea: la de cinco argumentos se borró al añadir el sexto'
);

SELECT has_function('crm', 'registrar_estado_linea',
  ARRAY['text', 'text', 'integer', 'integer', 'text', 'text'],
  'Y es la que acepta el request_id al final');

SET LOCAL ROLE service_role;

-- --- Las llamadas de antes siguen valiendo ----------------------------
SELECT ok(
  crm.registrar_estado_linea('310000000000001', 'contactos_solicitados'),
  'La llamada de dos argumentos, sin recibo, sigue funcionando'
);

SELECT is(
  (SELECT contactos_request_id FROM crm.lineas WHERE wa_phone_number_id = '310000000000001'),
  NULL,
  'Y deja el recibo vacío: no se inventa'
);

-- --- El recibo -----------------------------------------------------------
-- Una primera petición de hace una hora, anotada sin recibo.
RESET ROLE;
UPDATE crm.lineas SET contactos_solicitados_at = now() - interval '1 hour'
 WHERE wa_phone_number_id = '310000000000001';
SET LOCAL ROLE service_role;

SELECT ok(
  crm.registrar_estado_linea('310000000000001', 'contactos_solicitados',
                             p_request_id => 'req-contactos-1'),
  'Un reintento con el recibo de Meta se acepta'
);

SELECT is(
  (SELECT contactos_request_id FROM crm.lineas WHERE wa_phone_number_id = '310000000000001'),
  'req-contactos-1',
  'Y completa el recibo que faltaba'
);

SELECT is(
  (SELECT contactos_solicitados_at FROM crm.lineas WHERE wa_phone_number_id = '310000000000001'),
  now() - interval '1 hour',
  'Sin mover la fecha de la primera petición'
);

SELECT ok(
  crm.registrar_estado_linea('310000000000001', 'contactos_solicitados',
                             p_request_id => 'req-contactos-2'),
  'Un reintento con otro recibo no falla: la base anota hechos, no los discute'
);

SELECT is(
  (SELECT contactos_request_id FROM crm.lineas WHERE wa_phone_number_id = '310000000000001'),
  'req-contactos-1',
  'Un segundo recibo distinto no pisa el primero: Meta acepta una sola petición por ciclo'
);

-- Con argumentos con nombre, que es como llama supabase-js con .rpc().
SELECT ok(
  crm.registrar_estado_linea(p_wa_phone_number_id => '310000000000001',
                             p_evento             => 'historial_solicitado',
                             p_request_id         => 'req-historial-1'),
  'El historial se anota con su propio recibo, con argumentos con nombre'
);

SELECT is(
  (SELECT contactos_request_id || ' / ' || historial_request_id
     FROM crm.lineas WHERE wa_phone_number_id = '310000000000001'),
  'req-contactos-1 / req-historial-1',
  'Cada solicitud guarda el suyo: son dos peticiones a Meta, no una'
);

-- --- El recibo no viaja con los lotes ---------------------------------
SELECT throws_ok(
  $$SELECT crm.registrar_estado_linea('310000000000001', 'historial_progreso', 40,
                                      p_request_id => 'req-historial-1')$$,
  '22023', NULL,
  'Un request_id en un lote se rechaza: Meta no lo manda en los lotes, y la plataforma tiene que saberlo'
);

SELECT ok(
  crm.registrar_estado_linea('310000000000001', 'historial_progreso', 40,
                             p_request_id => '   '),
  'Un request_id en blanco cuenta como ninguno'
);

-- La forma de cinco argumentos, posicional, exactamente como la escribe
-- el contrato para un error del historial.
SELECT ok(
  crm.registrar_estado_linea('310000000000001', 'historial_error', NULL, 2593109,
                             'History sync is turned off by the business'),
  'La llamada de cinco argumentos posicionales sigue funcionando'
);

SELECT is(
  (SELECT historial_error_codigo FROM crm.lineas WHERE wa_phone_number_id = '310000000000001'),
  2593109,
  'Y anota el error como siempre'
);

RESET ROLE;

-- --- Reconectar empieza un ciclo nuevo --------------------------------
SELECT ok(
  crm.conectar_linea('11111111-1111-1111-1111-111111111111', 'comercial',
                     'waba-alfa', '310000000000001', 'coexistencia',
                     'EAAG-token-31-bis') IS NOT NULL,
  'Se reconecta la línea'
);

SELECT is(
  (SELECT row(contactos_request_id, historial_request_id)::text
     FROM crm.lineas WHERE wa_phone_number_id = '310000000000001'),
  '(,)',
  'Al reconectar, los recibos del ciclo anterior se vacían como todo lo demás'
);

-- --- Quién puede llamarla ---------------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$SELECT crm.registrar_estado_linea('310000000000001', 'historial_solicitado',
                                      p_request_id => 'req-falso')$$,
  '42501', NULL,
  'Ni un admin logueado puede anotar estados de línea: la función nueva nació cerrada'
);

SELECT throws_ok(
  $$SELECT crm.registrar_estado_linea('310000000000001', 'suscripcion_verificada')$$,
  '42501', NULL,
  'Tampoco con la llamada corta de antes'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
