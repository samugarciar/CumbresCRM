-- =====================================================================
-- Valida el PATRÓN sobre el que se va a construir toda la fase 1.
--
-- El CRM recibe sus datos por triggers que proyectan desde `public` hacia
-- `crm`. El peligro es que un trigger que lance una excepción ABORTA la
-- transacción de quien lo disparó: si el trigger de proyección tiene un
-- bug, el agente comercial deja de poder guardar mensajes y se queda mudo
-- con clientes reales de WhatsApp.
--
-- Esta prueba demuestra las dos mitades del asunto con tablas de juguete:
--   A) sin guarda, un trigger roto SÍ tumba el INSERT
--   B) con `EXCEPTION WHEN OTHERS`, el INSERT sobrevive y el fallo queda
--      registrado para reintentarlo después
--
-- Cuando la fase 1 escriba los triggers de verdad, esta prueba es el
-- contrato que deben cumplir.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(5);

-- ---------------------------------------------------------------------
-- A) El comportamiento PELIGROSO, para tenerlo documentado y medido
-- ---------------------------------------------------------------------
CREATE TABLE pg_temp.origen_sin_guarda (id serial PRIMARY KEY, texto text);

CREATE FUNCTION pg_temp.proyectar_sin_guarda() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  -- Simula cualquier bug del CRM: una columna que ya no existe, un tipo
  -- que no convierte, un NOT NULL que se violó.
  RAISE EXCEPTION 'fallo simulado de proyeccion';
END $$;

CREATE TRIGGER t_sin_guarda AFTER INSERT ON pg_temp.origen_sin_guarda
  FOR EACH ROW EXECUTE FUNCTION pg_temp.proyectar_sin_guarda();

SELECT throws_ok(
  $$INSERT INTO pg_temp.origen_sin_guarda (texto) VALUES ('mensaje del cliente')$$,
  NULL,
  'Sin guarda: un trigger roto hace fallar el INSERT del que lo disparó'
);

SELECT is(
  (SELECT count(*) FROM pg_temp.origen_sin_guarda),
  0::bigint,
  'Sin guarda: el mensaje se PERDIÓ — esto es el agente comercial quedándose mudo'
);

-- ---------------------------------------------------------------------
-- B) El patrón que sí vamos a usar
-- ---------------------------------------------------------------------
CREATE TABLE pg_temp.origen_con_guarda (id serial PRIMARY KEY, texto text);
CREATE TABLE pg_temp.eventos_fallidos (
  id serial PRIMARY KEY,
  tabla_origen text,
  fila_id int,
  error text,
  ocurrido_en timestamptz DEFAULT now()
);

CREATE FUNCTION pg_temp.proyectar_con_guarda() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    RAISE EXCEPTION 'fallo simulado de proyeccion';
  EXCEPTION WHEN OTHERS THEN
    -- El fallo se registra en vez de propagarse. En la fase 1 esta tabla
    -- es `crm.eventos` con estado 'fallido', y un job de pg_cron reintenta.
    INSERT INTO pg_temp.eventos_fallidos (tabla_origen, fila_id, error)
    VALUES (TG_TABLE_NAME, NEW.id, SQLERRM);
  END;
  RETURN NEW;
END $$;

CREATE TRIGGER t_con_guarda AFTER INSERT ON pg_temp.origen_con_guarda
  FOR EACH ROW EXECUTE FUNCTION pg_temp.proyectar_con_guarda();

INSERT INTO pg_temp.origen_con_guarda (texto) VALUES ('mensaje del cliente');

SELECT is(
  (SELECT count(*) FROM pg_temp.origen_con_guarda),
  1::bigint,
  'Con guarda: el mensaje SÍ se guardó, aunque la proyección falló'
);

SELECT is(
  (SELECT count(*) FROM pg_temp.eventos_fallidos),
  1::bigint,
  'Con guarda: el fallo quedó registrado, no se perdió en silencio'
);

SELECT is(
  (SELECT error FROM pg_temp.eventos_fallidos LIMIT 1),
  'fallo simulado de proyeccion',
  'Con guarda: se guardó el mensaje de error real, para poder depurarlo'
);

SELECT * FROM finish();
ROLLBACK;
