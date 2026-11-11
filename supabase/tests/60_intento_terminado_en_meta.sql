-- =====================================================================
-- «terminado_en_meta»: Meta avisó que el registro terminó, pero la
-- plataforma todavía no tiene el código (migración 20261111100001).
--
-- Lo que tiene que garantizar: que se anota con el número y la cuenta que
-- mandó Meta, sin exigir error; que convive con el 'exito' del mismo
-- número; y que el resto de valores sigue rechazándose.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(5);

DELETE FROM crm.intentos_incorporacion;

SET LOCAL ROLE service_role;

SELECT lives_ok(
  $$SELECT crm.registrar_intento_incorporacion(
      '11111111-1111-1111-1111-111111111111', 'administrativa', 'terminado_en_meta',
      p_error => '{"coexistencia":true,"business_id":"600000000000001"}',
      p_wa_phone_number_id => '600000000000002',
      p_waba_id => '600000000000003')$$,
  'El aviso de Meta se anota con el número, la cuenta y lo que mandó la ventana'
);

SELECT lives_ok(
  $$SELECT crm.registrar_intento_incorporacion(
      '11111111-1111-1111-1111-111111111111', 'administrativa', 'terminado_en_meta')$$,
  'Sin datos de Meta también se anota: no es un error'
);

SELECT lives_ok(
  $$SELECT crm.registrar_intento_incorporacion(
      '11111111-1111-1111-1111-111111111111', 'administrativa', 'exito',
      p_wa_phone_number_id => '600000000000002', p_waba_id => '600000000000003')$$,
  'Después llega el código y el éxito del mismo número queda en su propia fila'
);

SELECT is(
  (SELECT array_agg(resultado ORDER BY resultado) FROM crm.intentos_incorporacion
    WHERE wa_phone_number_id = '600000000000002'),
  ARRAY['exito', 'terminado_en_meta'],
  'Del mismo número quedan el aviso de Meta y el éxito de la plataforma'
);

SELECT throws_ok(
  $$SELECT crm.registrar_intento_incorporacion(
      '11111111-1111-1111-1111-111111111111', 'administrativa', 'terminado')$$,
  '23514', NULL,
  'Un resultado fuera de la lista sigue rechazándose'
);

SELECT * FROM finish();
ROLLBACK;
