-- =====================================================================
-- ARREGLO DE DATOS: escalamientos anteriores al contacto (26 oct 2026)
--
-- NO ES UNA MIGRACIÓN (y no va en supabase/snippets/, que el .gitignore
-- reserva a los borradores del Studio). Se corre a mano, una vez, en el SQL Editor,
-- DESPUÉS de 20261026100004_crm_escalamiento_mas_reciente.sql.
--
-- QUÉ ARREGLA
-- Hasta esa migración, crm.sincronizar_escalamientos copiaba a la
-- oportunidad el PRIMER escalamiento de la conversación del agente, aunque
-- fuera de la era Kommo, de antes de que el contacto naciera en el CRM. En
-- el Tablero eso se ve como «Pidió persona hace 2 meses» en una oportunidad
-- de ayer. La función nueva ya no lo hace; esto limpia lo que quedó:
-- escalado_at = NULL donde es anterior a la creación del contacto. Si la
-- persona volvió a pedir ayuda después, la siguiente pasada del cron
-- (crm_recalcular_pipeline, cada 5 min) lo anota con la fecha buena.
--
-- CUÁNTAS: en producción se espera 1 fila (la del lead de prueba).
--
-- CÓMO CORRERLO
--   1. Pegar todo y ejecutar: muestra cuáles son, las limpia, cuenta las
--      que quedan y DESHACE (ROLLBACK).
--   2. Si el conteo es el esperado, cambiar el ROLLBACK del final por
--      COMMIT y volver a ejecutar.
-- =====================================================================

BEGIN;

-- Antes: cuáles (se espera 1).
SELECT o.id AS oportunidad_id, c.id AS contacto_id, c.nombre,
       o.escalado_at, c.created_at AS contacto_creado
  FROM crm.oportunidades o
  JOIN crm.contactos c ON c.id = o.contacto_id
 WHERE o.escalado_at < c.created_at;

UPDATE crm.oportunidades o
   SET escalado_at = NULL,
       updated_at  = now()
  FROM crm.contactos c
 WHERE c.id = o.contacto_id
   AND o.escalado_at < c.created_at;

-- Después: no debe quedar ninguna.
SELECT count(*) AS quedan
  FROM crm.oportunidades o
  JOIN crm.contactos c ON c.id = o.contacto_id
 WHERE o.escalado_at < c.created_at;

-- Cambiar por COMMIT cuando el conteo de arriba sea el esperado.
ROLLBACK;
