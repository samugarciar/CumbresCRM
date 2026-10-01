-- =====================================================================
-- crm.etapas, cerrada a escritura de usuarios.
--
-- El 26 sep una sesión de Beta renombró una etapa para todas las
-- inmobiliarias. Esta prueba repite ese ataque y espera que falle. Y deja
-- una guarda general: ninguna tabla de `crm` sin RLS, para que la próxima
-- tabla global no nazca abierta como nació esta.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(10);

-- --- La guarda general ---------------------------------------------------
SELECT is(
  (SELECT array_agg(c.relname::text ORDER BY c.relname)
     FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'crm' AND c.relkind = 'r' AND NOT c.relrowsecurity),
  NULL,
  'Ninguna tabla de crm sin RLS: una tabla nueva que nazca sin ella tumba esta prueba'
);

SELECT table_privs_are('crm', 'etapas', 'authenticated', ARRAY['SELECT'],
  'Un usuario logueado solo puede LEER las etapas');

SELECT table_privs_are('crm', 'etapas', 'anon', ARRAY[]::text[],
  'Un anónimo, nada');

-- --- El ataque del 26 sep, repetido --------------------------------------
CREATE TEMP TABLE antes AS
  SELECT codigo, etiqueta, dias_pudricion FROM crm.etapas;
GRANT SELECT ON antes TO authenticated;

SET LOCAL "request.jwt.claims" = '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$UPDATE crm.etapas SET etiqueta = 'Hackeado por Beta', dias_pudricion = 1 WHERE codigo = 'nuevo'$$,
  '42501', NULL,
  'Beta NO puede renombrar una etapa de todos'
);

SELECT throws_ok(
  $$INSERT INTO crm.etapas (codigo, orden, etiqueta, dias_pudricion, automatica, embudo)
    VALUES ('inventada', 99, 'Inventada', 3, false, 'comercial')$$,
  '42501', NULL,
  'Ni inventar una en el embudo comercial de todos'
);

SELECT throws_ok(
  $$DELETE FROM crm.etapas WHERE codigo = 'nuevo'$$,
  '42501', NULL,
  'Ni borrarla'
);

-- --- Leer sigue igual ----------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM crm.etapas),
  (SELECT count(*)::int FROM antes),
  'Pero las sigue viendo todas: es un catálogo global'
);

SELECT lives_ok(
  $$SELECT * FROM crm.v_oportunidades LIMIT 1$$,
  'La vista de oportunidades, que cruza con las etapas, sigue funcionando para un usuario'
);

RESET ROLE;

SELECT is(
  (SELECT count(*)::int FROM crm.etapas e
     JOIN antes a USING (codigo)
    WHERE e.etiqueta = a.etiqueta
      AND e.dias_pudricion IS NOT DISTINCT FROM a.dias_pudricion),
  (SELECT count(*)::int FROM antes),
  'Y ninguna etapa cambió'
);

-- --- La RLS como segundo cerrojo -----------------------------------------
-- Si alguien devolviera el permiso por descuido, la RLS sigue sin dejar
-- escribir: no hay política de escritura.
GRANT UPDATE ON crm.etapas TO authenticated;
SET LOCAL ROLE authenticated;

SELECT is_empty(
  $$UPDATE crm.etapas SET etiqueta = 'Hackeado por Beta' WHERE codigo = 'nuevo' RETURNING codigo$$,
  'Aun con el permiso devuelto, la RLS no deja cambiar ninguna fila'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
