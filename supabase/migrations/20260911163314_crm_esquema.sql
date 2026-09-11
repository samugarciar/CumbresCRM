-- =====================================================================
-- El esquema `crm` y sus permisos.
--
-- Este esquema es del repo CumbresCRM. El repo CumbresStateInventory es
-- dueño de `public` y no lo toca. Las migraciones del CRM se generan con
-- `supabase db diff --schema crm`: una migración del CRM que toque
-- `public` es un error de revisión.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS crm;

-- ---------------------------------------------------------------------
-- `anon` no debe alcanzar NADA del CRM.
--
-- No es paranoia: en `public` el rol `anon` tiene GRANT de SELECT sobre
-- `citas` (viene del acceso del agente por PostgREST) y lo único que lo
-- detiene es que `auth.uid()` sea nulo, porque las políticas están
-- declaradas TO public. Aquí se corta antes: sin USAGE sobre el esquema,
-- un anónimo no puede ni nombrar una tabla del CRM.
-- ---------------------------------------------------------------------
REVOKE ALL ON SCHEMA crm FROM anon;

GRANT USAGE ON SCHEMA crm TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- Privilegios por defecto: valen para lo que se cree DESPUÉS de esto, y
-- solo para objetos creados por el mismo rol que ejecuta las migraciones.
-- Sin esto, cada tabla nueva nacería sin permisos y habría que acordarse
-- de concederlos una por una.
--
-- Ojo: esto concede permiso sobre la TABLA. Quién ve qué FILAS lo decide
-- la RLS, que se habilita tabla por tabla.
-- ---------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES IN SCHEMA crm
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA crm
  GRANT ALL ON TABLES TO service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA crm
  GRANT USAGE, SELECT ON SEQUENCES TO authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA crm
  GRANT EXECUTE ON FUNCTIONS TO authenticated, service_role;

COMMENT ON SCHEMA crm IS
  'CRM propio de Cumbres. Dueño: repo CumbresCRM. Nunca escribe en public; lo lee por vistas de solo lectura definidas aquí.';
