-- =====================================================================
-- El chat de la ficha se refresca en vivo (25 oct 2026).
--
-- Hasta hoy la publicación `supabase_realtime` estaba vacía: el mensaje
-- del cliente, la respuesta del bot o el envío de otro asesor entraban a
-- crm.actividades por el trigger de proyección, pero la ficha abierta no
-- se enteraba hasta recargar.
--
-- Se publica crm.actividades y nada más. Es la tabla que lee el chat (por
-- crm.v_timeline) y la única puerta por la que entra todo lo que el chat
-- enseña. Realtime pasa cada fila por la política actividades_select con
-- el token de quien escucha: un asesor solo recibe las de su inmobiliaria,
-- igual que al leer.
--
-- REPLICA IDENTITY se queda como está (la llave primaria): la ficha solo
-- escucha INSERT, que trae la fila entera. Las actividades no se editan
-- ni se borran desde la app, así que UPDATE y DELETE no interesan; y un
-- DELETE de Realtime no pasa por la RLS, otra razón para no escucharlos.
--
-- Idempotente: se puede correr dos veces en el SQL Editor sin error.
-- =====================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime'
       AND schemaname = 'crm'
       AND tablename = 'actividades'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE crm.actividades;
  END IF;
END $$;
