-- =====================================================================
-- crm.etapas, cerrada a escritura de usuarios.
--
-- EL PENDIENTE QUE DEJÓ LA SESIÓN DE PRIVILEGIOS (26 sep 2026)
-- crm.etapas era la única tabla de `crm` sin RLS, y `authenticated` tenía
-- INSERT, UPDATE y DELETE sobre ella por los privilegios por defecto del
-- esquema. Es un catálogo GLOBAL: una sesión de Beta renombró la etapa
-- «nuevo» y le cambió los días de pudrición para TODAS las inmobiliarias,
-- e inventó una etapa en el embudo comercial de todos (probado y
-- revertido aquel día). Con /registro-inmobiliaria abierta sin sesión,
-- "una sesión de Beta" es cualquiera que se dé de alta.
--
-- DOS CERROJOS, NO UNO
--   · Se retiran los permisos de escritura. Es lo que de verdad cierra.
--   · Se activa la RLS con una política solo de lectura, como ya tiene
--     crm.embudos. Si mañana alguien vuelve a dar un GRANT por descuido
--     —o lo da un ALTER DEFAULT PRIVILEGES—, la RLS sigue sin dejar
--     escribir a nadie.
--
-- Leer sigue igual para cualquiera con sesión: el tablero, las vistas de
-- oportunidades y mover_etapa la leen con el rol de quien llama. Las
-- etapas se cambian por migración, como hasta ahora.
-- =====================================================================

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON crm.etapas FROM PUBLIC, anon, authenticated;

ALTER TABLE crm.etapas ENABLE ROW LEVEL SECURITY;

-- Catálogo global: todos ven todas. Sin políticas de escritura.
CREATE POLICY etapas_select ON crm.etapas
  FOR SELECT TO authenticated
  USING (true);

COMMENT ON TABLE crm.etapas IS
  'Catálogo GLOBAL de peldaños de cada embudo. Solo lectura para usuarios (permisos y RLS); se cambia por migración.';
