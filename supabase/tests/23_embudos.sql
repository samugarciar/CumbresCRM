-- =====================================================================
-- Tres embudos en paralelo, y las líneas de WhatsApp que los alimentan.
--
-- Lo que se mide: que la misma persona pueda estar en dos embudos a la
-- vez —el caso real que lo motivó: un inquilino con contrato vigente que
-- pregunta por otro apartamento— y que NO se puedan mezclar los peldaños
-- de uno con las oportunidades de otro.
--
-- Y una guarda general que no va de embudos: que ninguna función de `crm`
-- esté sobrecargada. Dos fallos de esta sesión fueron exactamente eso.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(13);

DELETE FROM crm.contactos;

-- --- El catálogo -----------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM crm.embudos WHERE activo), 3,
  'Hay tres embudos: comercial, administrativa y captación'
);

SELECT is(
  (SELECT count(*)::int FROM crm.embudos WHERE bot_atiende), 1,
  'Y el bot solo atiende uno: decisión de Samuel, lo administrativo y la captación son de humanos'
);

SELECT is(
  (SELECT count(*)::int FROM crm.etapas WHERE embudo = 'comercial'), 6,
  'Los seis peldaños que ya existían quedaron en comercial, sin tocar una fila'
);

SELECT is(
  (SELECT codigo FROM crm.etapas WHERE embudo = 'captacion' ORDER BY orden LIMIT 1),
  'prospecto',
  'Captación tiene su propio recorrido, que empieza en Prospecto'
);

-- El orden era único en TODA la tabla: ese era uno de los tres bloqueos.
SELECT is(
  (SELECT count(*)::int FROM crm.etapas WHERE orden = 1), 2,
  'Dos embudos pueden tener cada uno su peldaño número 1'
);

-- --- La misma persona en dos embudos ---------------------------------
INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164)
VALUES ('eb000001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', 'Inquilina y compradora', '+573001141111');

SELECT ok(
  crm.abrir_oportunidad('eb000001-0000-0000-0000-000000000001') IS NOT NULL,
  'Se le abre la comercial'
);

SELECT ok(
  crm.abrir_oportunidad('eb000001-0000-0000-0000-000000000001', 'captacion') IS NOT NULL,
  'Y ADEMÁS una de captación: antes había que cerrar una para abrir la otra'
);

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades
    WHERE contacto_id = 'eb000001-0000-0000-0000-000000000001' AND estado = 'abierta'),
  2,
  'Dos abiertas a la vez, una por embudo'
);

SELECT is(
  (SELECT etapa FROM crm.oportunidades
    WHERE contacto_id = 'eb000001-0000-0000-0000-000000000001' AND embudo = 'captacion'),
  'prospecto',
  'Cada una nace en el primer peldaño de SU embudo, no en una constante'
);

-- Pero dos en el mismo embudo siguen sin caber: esa regla no cambió.
SELECT throws_ok(
  $$INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa)
    VALUES ('11111111-1111-1111-1111-111111111111',
            'eb000001-0000-0000-0000-000000000001', 'comercial', 'nuevo')$$,
  '23505',
  NULL,
  'Dos abiertas en el MISMO embudo siguen sin caber'
);

-- --- La foránea compuesta, que es la que evita el absurdo ------------
SELECT throws_ok(
  $$INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa)
    VALUES ('11111111-1111-1111-1111-111111111111',
            'eb000001-0000-0000-0000-000000000001', 'administrativa', 'visita_realizada')$$,
  '23503',
  NULL,
  'Una etapa comercial en una oportunidad administrativa no se puede ni escribir'
);

-- --- Las líneas de WhatsApp ------------------------------------------
INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre)
VALUES ('11111111-1111-1111-1111-111111111111', 'comercial', '111222333', 'Comercial');

SELECT is(
  (SELECT l.embudo FROM crm.linea_por_numero('111222333') l),
  'comercial',
  'El webhook resuelve un phone_number_id a su embudo en una sola llamada'
);

-- =====================================================================
-- La guarda que no va de embudos
--
-- Dos fallos de esta sesión fueron firmas: reactivar_bots declarada con
-- `smallint` y llamada con un integer —cuatro días de cron muerto—, y
-- abrir_oportunidad, donde añadir un parámetro con DEFAULT creó una
-- SOBRECARGA en vez de reemplazar, y toda llamada se volvió ambigua.
--
-- En este esquema una función con dos firmas es siempre un accidente.
-- =====================================================================
SELECT is(
  (SELECT COALESCE(string_agg(proname, ', '), 'ninguna')
     FROM (SELECT p.proname
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'crm'
            GROUP BY p.proname HAVING count(*) > 1) x),
  'ninguna',
  'Ninguna función de crm quedó sobrecargada: dos firmas del mismo nombre siempre son un descuido aquí'
);

SELECT * FROM finish();
ROLLBACK;
