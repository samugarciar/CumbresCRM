-- =====================================================================
-- SIMULACIÓN DEL BACKFILL — no deja nada escrito.
--
-- La función crm.backfill() no tiene modo "simulación" a propósito: dos
-- caminos de código se desincronizan, y acabarías simulando algo distinto
-- de lo que va a ocurrir de verdad. La simulación la hace la transacción.
--
-- CÓMO SE USA
-- Pégalo en el SQL Editor de Supabase. Devuelve exactamente lo que haría
-- el backfill —contactos creados, actividades, cuántos se quedan sin
-- teléfono— y después revierte TODO.
--
-- Cuando el resultado convenza, se corre lo mismo sin el ROLLBACK.
-- =====================================================================

BEGIN;

SELECT crm.backfill('<PON-AQUÍ-EL-inmobiliaria_id>') AS resultado;

-- Detalle de lo que habría quedado, antes de deshacerlo:
SELECT 'contactos'    AS que, count(*) FROM crm.contactos
UNION ALL SELECT 'con teléfono',  count(*) FROM crm.contactos WHERE telefono_e164 IS NOT NULL
UNION ALL SELECT 'sin teléfono',  count(*) FROM crm.contactos WHERE telefono_e164 IS NULL
UNION ALL SELECT 'identidades',   count(*) FROM crm.identidades
UNION ALL SELECT 'actividades',   count(*) FROM crm.actividades;

-- Las personas cuyo historial estaba partido entre varias fuentes:
SELECT count(*) AS personas_con_historial_unificado
FROM (
  SELECT a.contacto_id
    FROM crm.actividades a
   GROUP BY a.contacto_id
  HAVING count(DISTINCT a.metadata->>'origen_tabla') > 1
) t;

ROLLBACK;
