-- =====================================================================
-- PRUEBA 57: Lo que no salió porque se canceló el envío también se
-- gestiona a mano (20261026160001)
--
-- Un envío de cartera que se lanza, le llega a una persona y se cancela
-- con dos todavía en cola: esas dos pasan a la gestión manual de quien
-- lo lanzó, con su motivo y en el detalle de Mi día. Un borrador
-- descartado, en cambio, no le carga a nadie gente «cancelada».
-- =====================================================================
BEGIN;
SELECT plan(9);

-- ---------------------------------------------------------------------
-- Fixtures (como postgres)
-- ---------------------------------------------------------------------
INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre) VALUES
  ('11111111-1111-1111-1111-111111111111', 'administrativa', '320000000000057', 'Línea Administrativa 320');

INSERT INTO crm.plantillas
  (id, inmobiliaria_id, nombre, cuerpo, categoria, estado_meta, nombre_meta, wa_phone_number_id)
VALUES
  ('fa570001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Mora de cartera', 'Hola {{nombre}}, tienes un saldo en mora de {{monto}}.',
   'utilidad', 'aprobada', 'mora_cartera', '320000000000057');

-- La hoja «Envios WhatsApp» de cartera, con nombres y números inventados.
CREATE TEMP TABLE archivo AS SELECT $json$[
  {"Nombre Inquilino": "Ana Entregada",     "Numero_WhatsApp": "+573005700002", "Total_En_Mora": "1250000"},
  {"Nombre Inquilino": "Sergio Sin Número", "Numero_WhatsApp": "",              "Total_En_Mora": "900000"},
  {"Nombre Inquilino": "Carla Cancelada",   "Numero_WhatsApp": "+573005700004", "Total_En_Mora": "700000"},
  {"Nombre Inquilino": "Darío Cancelado",   "Numero_WhatsApp": "+573005700005", "Total_En_Mora": "500000"}
]$json$::jsonb AS filas;
GRANT SELECT ON archivo TO authenticated;

CREATE TEMP TABLE ids (clave text PRIMARY KEY, id uuid);
GRANT SELECT, INSERT ON ids TO authenticated;

-- Como el asesor de Alfa: prepara dos envíos y lanza uno.
SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;

INSERT INTO ids
SELECT 'envio', crm.crear_envio_masivo(
  'Cartera de octubre', 'cartera_octubre.xlsx',
  ARRAY['Nombre Inquilino', 'Numero_WhatsApp', 'Total_En_Mora'],
  (SELECT filas FROM archivo),
  'Numero_WhatsApp', 'Nombre Inquilino',
  'fa570001-0000-0000-0000-000000000001',
  '{"nombre": "Nombre Inquilino", "monto": "Total_En_Mora"}',
  false);

INSERT INTO ids
SELECT 'borrador', crm.crear_envio_masivo(
  'Archivo equivocado', 'cartera_vieja.xlsx',
  ARRAY['Nombre Inquilino', 'Numero_WhatsApp', 'Total_En_Mora'],
  (SELECT filas FROM archivo),
  'Numero_WhatsApp', 'Nombre Inquilino',
  'fa570001-0000-0000-0000-000000000001',
  '{"nombre": "Nombre Inquilino", "monto": "Total_En_Mora"}',
  false);

INSERT INTO ids
SELECT 'fila' || d.fila, d.id
  FROM crm.envios_masivos_destinatarios d
 WHERE d.envio_masivo_id = (SELECT id FROM ids WHERE clave = 'envio');

SELECT is(
  crm.lanzar_envio_masivo((SELECT id FROM ids WHERE clave = 'envio'), 3),
  3,
  'Se lanza a los tres que tienen número'
);

-- A Ana le llega (como postgres, con la marca, como lo dejaría el
-- despachador). Carla y Darío siguen en cola.
RESET ROLE;
SELECT set_config('crm.envios_masivos', 'si', true);
WITH d AS (
  SELECT x.id, x.contacto_id, x.cuerpo
    FROM crm.envios_masivos_destinatarios x
   WHERE x.envio_masivo_id = (SELECT id FROM ids WHERE clave = 'envio') AND x.fila = 2
), e AS (
  INSERT INTO crm.envios
    (inmobiliaria_id, contacto_id, plantilla_id, cuerpo, canal, wa_phone_number_id,
     envio_masivo_id, estado, tomado_at, enviado_at, entregado_at, created_at)
  SELECT '11111111-1111-1111-1111-111111111111', d.contacto_id,
         'fa570001-0000-0000-0000-000000000001', d.cuerpo, 'meta', '320000000000057',
         (SELECT id FROM ids WHERE clave = 'envio'), 'entregado',
         now() - interval '1 hour', now() - interval '1 hour', now() - interval '50 minutes',
         now() - interval '1 hour'
    FROM d
  RETURNING id
)
UPDATE crm.envios_masivos_destinatarios
   SET estado = 'encolado', envio_id = (SELECT id FROM e)
 WHERE id = (SELECT id FROM d);
SELECT set_config('crm.envios_masivos', '', true);
SET LOCAL ROLE authenticated;

-- Se cancela el lanzado y se descarta el borrador.
SELECT crm.cambiar_estado_envio_masivo((SELECT id FROM ids WHERE clave = 'envio'), 'cancelar');
SELECT crm.cambiar_estado_envio_masivo((SELECT id FROM ids WHERE clave = 'borrador'), 'cancelar');

-- =====================================================================
-- 1 · Quién entra
-- =====================================================================
SELECT is(
  (SELECT string_agg(fila || ':' || motivo, ' ' ORDER BY fila)
     FROM crm.pendientes_gestion_envio((SELECT id FROM ids WHERE clave = 'envio'))),
  '3:sin_telefono 4:cancelado 5:cancelado',
  'Del envío cancelado entran el que no tenía número y los dos que no alcanzaron a salir'
);

SELECT is(
  (SELECT motivo_legible FROM crm.pendientes_gestion_envio((SELECT id FROM ids WHERE clave = 'envio'))
    WHERE fila = 4),
  'Se canceló el envío antes de mandarle el mensaje',
  'Y se dice por qué'
);

SELECT is_empty(
  $$SELECT 1 FROM crm.pendientes_gestion_envio((SELECT id FROM ids WHERE clave = 'envio')) WHERE fila = 2$$,
  'A quien sí le llegó antes de cancelar no se le gestiona nada'
);

SELECT is_empty(
  $$SELECT 1 FROM crm.pendientes_gestion_envio((SELECT id FROM ids WHERE clave = 'borrador'))
     WHERE motivo = 'cancelado'$$,
  'Un borrador descartado no deja gente «cancelada»: nunca se le iba a mandar a nadie'
);

-- =====================================================================
-- 2 · Mi día de quien lo lanzó
-- =====================================================================
SELECT is(
  (SELECT titulo || '|' || detalle FROM crm.mi_dia(60, 'cccccccc-cccc-cccc-cccc-cccccccccccc')
    WHERE tipo = 'gestion_envio_masivo'),
  'Envío "Cartera de octubre": 3 personas para gestionar a mano|1 sin número válido · 2 sin enviar (se canceló el envío)',
  'El renglón cuenta a los cancelados y lo dice en el detalle'
);

SELECT is(
  (SELECT count(*)::int FROM crm.mi_dia(60, 'cccccccc-cccc-cccc-cccc-cccccccccccc')
    WHERE tipo = 'gestion_envio_masivo'),
  1,
  'El borrador descartado no pone renglón en Mi día'
);

-- =====================================================================
-- 3 · Se marcan como los demás
-- =====================================================================
SELECT isnt(
  crm.marcar_gestion_manual((SELECT id FROM ids WHERE clave = 'fila4'), 'La llamé: paga mañana'),
  NULL,
  'A la cancelada se la marca como gestionada'
);

SELECT is(
  (SELECT titulo FROM crm.mi_dia(60, 'cccccccc-cccc-cccc-cccc-cccccccccccc')
    WHERE tipo = 'gestion_envio_masivo'),
  'Envío "Cartera de octubre": 2 personas para gestionar a mano',
  'Y en Mi día queda una menos'
);

SELECT * FROM finish();
ROLLBACK;
