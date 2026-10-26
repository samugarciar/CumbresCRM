-- =====================================================================
-- Las vistas del CRM son de solo lectura (26 oct 2026)
--
-- LO QUE PASABA (S-08)
-- crm.v_citas, v_inmuebles, v_asesores, v_timeline y v_oportunidades son
-- vistas simples sobre una tabla: Postgres las hace actualizables solas, y
-- authenticated conservaba INSERT, UPDATE y DELETE sobre ellas (el
-- privilegio por defecto del esquema). Son SECURITY INVOKER, así que la RLS
-- de la tabla de abajo seguía mandando, pero la regla del repo es que el
-- CRM lee public por vistas de SOLO LECTURA y nunca escribe ahí: v_citas,
-- v_inmuebles y v_asesores apuntan a tablas de la plataforma.
--
-- Revisado con grep el 26 oct: la app solo hace select sobre estas vistas.
-- v_bot_callado ya era solo SELECT.
--
-- Idempotente.
-- =====================================================================

REVOKE INSERT, UPDATE, DELETE ON crm.v_citas, crm.v_inmuebles, crm.v_asesores,
                                 crm.v_timeline, crm.v_oportunidades
  FROM authenticated;
