-- =====================================================================
-- Las vistas del CRM son de solo lectura (20261026100008).
--
-- El CRM lee public por vistas y nunca escribe ahí. Una vista simple es
-- actualizable sola en Postgres: sin el REVOKE, authenticated podía
-- escribir a través de ella.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(3);

SELECT is_empty(
  $$SELECT c.relname || ': ' || p.privilegio
      FROM pg_class c
      CROSS JOIN (VALUES ('INSERT'), ('UPDATE'), ('DELETE')) p(privilegio)
     WHERE c.relnamespace = 'crm'::regnamespace
       AND c.relkind = 'v'
       AND has_table_privilege('authenticated', c.oid, p.privilegio)$$,
  'Ninguna vista de crm deja escribir a authenticated'
);

SELECT ok(
  has_table_privilege('authenticated', 'crm.v_timeline', 'SELECT')
  AND has_table_privilege('authenticated', 'crm.v_citas', 'SELECT')
  AND has_table_privilege('authenticated', 'crm.v_oportunidades', 'SELECT'),
  'Leer sí: las pantallas siguen funcionando'
);

SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$UPDATE crm.v_asesores SET nombre_completo = 'Otro nombre'
     WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  '42501', NULL,
  'Cambiar un usuario de la plataforma a través de la vista ya no se puede'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
