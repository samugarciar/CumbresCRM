-- =====================================================================
-- PRUEBA 56: Lo que un envío masivo no entrega se gestiona a mano
-- (20261026150001)
--
-- Un envío de cartera con una fila por cada caso: quién entra en la
-- gestión manual y quién no, marcar y desmarcar, el cerrojo, que otra
-- inmobiliaria no puede marcar, el renglón de Mi día de QUIEN LANZÓ (y
-- de nadie más), y la purga que borra la nota.
--
-- Lo que pasó con cada mensaje se escribe a mano en crm.envios, como lo
-- dejarían el despachador y los acuses de Meta: la red no se toca.
-- =====================================================================
BEGIN;
SELECT plan(30);

-- ---------------------------------------------------------------------
-- Fixtures (como postgres)
-- ---------------------------------------------------------------------
INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre) VALUES
  ('11111111-1111-1111-1111-111111111111', 'administrativa', '320000000000056', 'Línea Administrativa 320');

INSERT INTO crm.plantillas
  (id, inmobiliaria_id, nombre, cuerpo, categoria, estado_meta, nombre_meta, wa_phone_number_id)
VALUES
  ('fa560001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Mora de cartera', 'Hola {{nombre}}, tienes un saldo en mora de {{monto}}.',
   'utilidad', 'aprobada', 'mora_cartera', '320000000000056');

-- Bernardo pidió no recibir más mensajes. Fabiola recibió otro envío
-- masivo hace dos días.
INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, opt_out, opt_out_at) VALUES
  ('aaaa0056-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Bernardo Baja', true, now()),
  ('aaaa0056-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Fabiola Frecuente', false, NULL);

INSERT INTO crm.identidades (inmobiliaria_id, contacto_id, tipo, valor, origen) VALUES
  ('11111111-1111-1111-1111-111111111111', 'aaaa0056-0000-0000-0000-000000000001', 'telefono_e164', '+573005600007', 'prueba'),
  ('11111111-1111-1111-1111-111111111111', 'aaaa0056-0000-0000-0000-000000000002', 'telefono_e164', '+573005600008', 'prueba');

SELECT set_config('crm.envios_masivos', 'si', true);
INSERT INTO crm.envios_masivos
  (id, inmobiliaria_id, nombre, columnas, columna_telefono, plantilla_id, wa_phone_number_id,
   estado, lanzado_at, terminado_at)
VALUES ('eeee0056-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'Cartera de septiembre', ARRAY['Numero_WhatsApp'], 'Numero_WhatsApp',
        'fa560001-0000-0000-0000-000000000001', '320000000000056',
        'terminado', now() - interval '2 days', now() - interval '2 days');
INSERT INTO crm.envios
  (inmobiliaria_id, contacto_id, plantilla_id, cuerpo, canal, estado, wa_phone_number_id,
   envio_masivo_id, created_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'aaaa0056-0000-0000-0000-000000000002',
        'fa560001-0000-0000-0000-000000000001', 'Hola Fabiola…', 'meta', 'entregado',
        '320000000000056', 'eeee0056-0000-0000-0000-000000000001', now() - interval '2 days');
SELECT set_config('crm.envios_masivos', '', true);

-- La hoja «Envios WhatsApp» de cartera, con nombres y números inventados.
CREATE TEMP TABLE archivo AS SELECT $json$[
  {"Nombre Inquilino": "Ana Entregada",     "Numero_WhatsApp": "+573005600002", "Total_En_Mora": "1250000", "Facturas_Vencidas": "2"},
  {"Nombre Inquilino": "Sergio Sin Número", "Numero_WhatsApp": "",              "Total_En_Mora": "900000",  "Facturas_Vencidas": "1"},
  {"Nombre Inquilino": "Iván Inválido",     "Numero_WhatsApp": "12345",         "Total_En_Mora": "700000",  "Facturas_Vencidas": "3"},
  {"Nombre Inquilino": "Ana Repetida",      "Numero_WhatsApp": "300 560 0002",  "Total_En_Mora": "1",       "Facturas_Vencidas": "1"},
  {"Nombre Inquilino": "Diana Sin Datos",   "Numero_WhatsApp": "+573005600006", "Total_En_Mora": "",        "Facturas_Vencidas": "1"},
  {"Nombre Inquilino": "Bernardo Baja",     "Numero_WhatsApp": "+573005600007", "Total_En_Mora": "500000",  "Facturas_Vencidas": "1"},
  {"Nombre Inquilino": "Fabiola Frecuente", "Numero_WhatsApp": "+573005600008", "Total_En_Mora": "400000",  "Facturas_Vencidas": "1"},
  {"Nombre Inquilino": "Fernando Falló",    "Numero_WhatsApp": "+573005600009", "Total_En_Mora": "300000",  "Facturas_Vencidas": "2"},
  {"Nombre Inquilino": "Carlos Callado",    "Numero_WhatsApp": "+573005600010", "Total_En_Mora": "200000",  "Facturas_Vencidas": "1"},
  {"Nombre Inquilino": "Elena Enviando",    "Numero_WhatsApp": "+573005600011", "Total_En_Mora": "100000",  "Facturas_Vencidas": "1"},
  {"Nombre Inquilino": "Rocío Sin Llegar",  "Numero_WhatsApp": "+573005600012", "Total_En_Mora": "150000",  "Facturas_Vencidas": "4"},
  {"Nombre Inquilino": "Tomás Reciente",    "Numero_WhatsApp": "+573005600013", "Total_En_Mora": "250000",  "Facturas_Vencidas": "1"},
  {"Nombre Inquilino": "Lina Leyó",         "Numero_WhatsApp": "+573005600014", "Total_En_Mora": "350000",  "Facturas_Vencidas": "1"}
]$json$::jsonb AS filas;
GRANT SELECT ON archivo TO authenticated;

CREATE TEMP TABLE ids (clave text PRIMARY KEY, id uuid);
GRANT SELECT, INSERT ON ids TO authenticated;

-- Como el asesor de Alfa: prepara y lanza.
SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;

INSERT INTO ids
SELECT 'envio', crm.crear_envio_masivo(
  'Cartera de octubre', 'cartera_octubre.xlsx',
  ARRAY['Nombre Inquilino', 'Numero_WhatsApp', 'Total_En_Mora', 'Facturas_Vencidas'],
  (SELECT filas FROM archivo),
  'Numero_WhatsApp', 'Nombre Inquilino',
  'fa560001-0000-0000-0000-000000000001',
  '{"nombre": "Nombre Inquilino", "monto": "Total_En_Mora"}',
  false);

-- El id de cada fila, a mano para lo que sigue (también para Beta, que
-- no las ve).
INSERT INTO ids
SELECT 'fila' || d.fila, d.id
  FROM crm.envios_masivos_destinatarios d
 WHERE d.envio_masivo_id = (SELECT id FROM ids WHERE clave = 'envio');

-- =====================================================================
-- 1 · En borrador ya se sabe quién irá a gestión manual
-- =====================================================================
SELECT is(
  (SELECT string_agg(fila || ':' || motivo, ' ' ORDER BY fila)
     FROM crm.pendientes_gestion_envio((SELECT id FROM ids WHERE clave = 'envio'))),
  '3:sin_telefono 4:telefono_invalido 6:faltan_datos',
  'En el borrador, los que no se pueden enviar: sin número, número inválido y sin datos'
);

SELECT throws_ok(
  $$SELECT crm.marcar_gestion_manual(
      (SELECT id FROM ids WHERE clave = 'fila3'), NULL)$$,
  '22023',
  'Ese envío todavía no se ha lanzado',
  'Pero en borrador no se marca nada: todavía no es trabajo de nadie'
);

SELECT is(
  crm.lanzar_envio_masivo((SELECT id FROM ids WHERE clave = 'envio'), 7),
  7,
  'Se lanza a los siete que sí pueden recibirlo'
);

-- =====================================================================
-- 2 · Lo que pasó con cada mensaje (como postgres, con la marca)
-- =====================================================================
RESET ROLE;
SELECT set_config('crm.envios_masivos', 'si', true);

DO $sembrar$
DECLARE
  d       record;
  v_envio uuid;
BEGIN
  FOR d IN
    SELECT x.id, x.fila, x.contacto_id, x.cuerpo
      FROM crm.envios_masivos_destinatarios x
     WHERE x.envio_masivo_id = (SELECT id FROM ids WHERE clave = 'envio')
       AND x.estado = 'listo'
  LOOP
    INSERT INTO crm.envios
      (inmobiliaria_id, contacto_id, plantilla_id, cuerpo, canal, wa_phone_number_id,
       envio_masivo_id, estado, tomado_at, enviado_at, entregado_at, leido_at,
       fallido_at, error, error_codigo, created_at)
    SELECT '11111111-1111-1111-1111-111111111111', d.contacto_id,
           'fa560001-0000-0000-0000-000000000001', d.cuerpo, 'meta', '320000000000056',
           (SELECT id FROM ids WHERE clave = 'envio'),
           s.estado, now() - s.hace, s.enviado, s.entregado, s.leido,
           s.fallido, s.error, s.codigo, now() - s.hace
      FROM (VALUES
        -- fila, estado, desde cuándo, enviado, entregado, leído, fallido, error, código
        (2,  'entregado', interval '1 hour',     now() - interval '1 hour',     now() - interval '50 minutes', NULL::timestamptz, NULL::timestamptz, NULL, NULL::int),
        (9,  'fallido',   interval '30 minutes', NULL,                          NULL,                          NULL,              now() - interval '29 minutes',
                          'Ese número no recibe mensajes de WhatsApp.', 131026),
        (10, 'pendiente', interval '11 minutes', NULL,                          NULL,                          NULL,              NULL, NULL, NULL),
        (11, 'pendiente', interval '2 minutes',  NULL,                          NULL,                          NULL,              NULL, NULL, NULL),
        (12, 'enviado',   interval '25 hours',   now() - interval '25 hours',   NULL,                          NULL,              NULL, NULL, NULL),
        (13, 'enviado',   interval '2 hours',    now() - interval '2 hours',    NULL,                          NULL,              NULL, NULL, NULL),
        (14, 'leido',     interval '3 hours',    now() - interval '3 hours',    now() - interval '3 hours',    now() - interval '2 hours', NULL, NULL, NULL)
      ) AS s(fila, estado, hace, enviado, entregado, leido, fallido, error, codigo)
     WHERE s.fila = d.fila
    RETURNING id INTO v_envio;

    UPDATE crm.envios_masivos_destinatarios SET estado = 'encolado', envio_id = v_envio WHERE id = d.id;
  END LOOP;
END $sembrar$;

SELECT set_config('crm.envios_masivos', '', true);
SET LOCAL ROLE authenticated;

-- =====================================================================
-- 3 · Quién entra y quién no
-- =====================================================================
SELECT is(
  (SELECT string_agg(fila || ':' || motivo, ' ' ORDER BY fila)
     FROM crm.pendientes_gestion_envio((SELECT id FROM ids WHERE clave = 'envio'))),
  '3:sin_telefono 4:telefono_invalido 6:faltan_datos 9:fallido 10:sin_confirmar 12:sin_entregar',
  'Entran: sin número, número inválido, sin datos, falló, sin confirmar (10 min) y enviado sin llegar en 24 h'
);

SELECT is_empty(
  $$SELECT fila FROM crm.pendientes_gestion_envio((SELECT id FROM ids WHERE clave = 'envio'))
     WHERE fila IN (5, 7, 8)$$,
  'No entran el repetido (la otra fila sí sale), la baja ni quien recibió otro envío esta semana'
);

SELECT is_empty(
  $$SELECT fila FROM crm.pendientes_gestion_envio((SELECT id FROM ids WHERE clave = 'envio'))
     WHERE fila IN (2, 11, 13, 14)$$,
  'Ni lo que llegó, ni lo que sigue saliendo, ni lo enviado hace menos de 24 horas'
);

SELECT is(
  (SELECT motivo_legible || '|' || detalle
     FROM crm.pendientes_gestion_envio((SELECT id FROM ids WHERE clave = 'envio')) WHERE fila = 9),
  'WhatsApp no lo entregó|Ese número no recibe mensajes de WhatsApp. (131026)',
  'El fallido dice por qué, con lo que contestó Meta'
);

SELECT is(
  (SELECT motivo_legible || '|' || detalle
     FROM crm.pendientes_gestion_envio((SELECT id FROM ids WHERE clave = 'envio')) WHERE fila = 6),
  'Le faltan datos para la plantilla|Sin monto',
  'Al que le faltan datos se le dice cuáles'
);

SELECT is(
  (SELECT nombre || '|' || COALESCE(telefono_crudo, '-') || '|' || COALESCE(telefono_e164, '-')
          || '|' || (datos ->> 'Total_En_Mora') || '|' || (datos ->> 'Facturas_Vencidas')
     FROM crm.pendientes_gestion_envio((SELECT id FROM ids WHERE clave = 'envio')) WHERE fila = 4),
  'Iván Inválido|12345|-|700000|3',
  'Trae el nombre, el teléfono como venía y la fila original para llamarlo con la deuda a mano'
);

SELECT is(
  (SELECT count(*)::int FROM crm.pendientes_gestion_envio((SELECT id FROM ids WHERE clave = 'envio'))
    WHERE gestionado),
  0,
  'Al comienzo nadie está gestionado'
);

-- =====================================================================
-- 4 · Mi día de quien lo lanzó
-- =====================================================================
SELECT is(
  (SELECT prioridad || '|' || titulo || '|' || cita_id::text
     FROM crm.mi_dia(60, 'cccccccc-cccc-cccc-cccc-cccccccccccc')
    WHERE tipo = 'gestion_envio_masivo'),
  '5|Envío "Cartera de octubre": 6 personas para gestionar a mano|' || (SELECT id FROM ids WHERE clave = 'envio'),
  'Quien lo lanzó tiene en su día el renglón, con el id del envío para el enlace'
);

SELECT is(
  (SELECT detalle FROM crm.mi_dia(60, 'cccccccc-cccc-cccc-cccc-cccccccccccc')
    WHERE tipo = 'gestion_envio_masivo'),
  '2 sin número válido · 1 con datos incompletos · 1 con error de WhatsApp · 2 sin confirmación de entrega',
  'Y el detalle dice de qué se trata'
);

SELECT is_empty(
  $$SELECT 1 FROM crm.mi_dia(60, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') WHERE tipo = 'gestion_envio_masivo'$$,
  'En el día de otro usuario de la misma inmobiliaria no aparece: es de quien lo lanzó'
);

-- =====================================================================
-- 5 · Marcar gestionado
-- =====================================================================
SELECT isnt(
  crm.marcar_gestion_manual(
    (SELECT id FROM ids WHERE clave = 'fila3'),
    '  Lo llamé al fijo: paga el viernes  '),
  NULL,
  'Se marca con una nota'
);

SELECT is(
  (SELECT gestionado || '|' || gestionado_por_nombre || '|' || gestion_nota
     FROM crm.pendientes_gestion_envio((SELECT id FROM ids WHERE clave = 'envio')) WHERE fila = 3),
  'true|Asesor Alfa|Lo llamé al fijo: paga el viernes',
  'Queda gestionado, con quién y la nota sin espacios de sobra'
);

SELECT is(
  (SELECT titulo FROM crm.mi_dia(60, 'cccccccc-cccc-cccc-cccc-cccccccccccc')
    WHERE tipo = 'gestion_envio_masivo'),
  'Envío "Cartera de octubre": 5 personas para gestionar a mano',
  'Y en Mi día queda uno menos'
);

SELECT throws_ok(
  $$SELECT crm.marcar_gestion_manual(
      (SELECT id FROM ids WHERE clave = 'fila2'), NULL)$$,
  '22023',
  'Esa persona no está en la gestión manual: el mensaje le llegó o sigue en camino',
  'A quien le llegó el mensaje no se le marca nada'
);

SELECT throws_ok(
  $$SELECT crm.marcar_gestion_manual(
      (SELECT id FROM ids WHERE clave = 'fila5'), NULL)$$,
  '22023',
  NULL,
  'Ni a la fila repetida'
);

SELECT throws_ok(
  format($$SELECT crm.marcar_gestion_manual(
      (SELECT id FROM ids WHERE clave = 'fila4'), %L)$$,
    repeat('x', 501)),
  '22023',
  NULL,
  'Una nota de más de 500 caracteres no entra'
);

-- Las funciones dejaron encendida la marca en esta transacción; en la
-- app cada llamada es su propia transacción. Se apaga para ver el cerrojo.
SELECT set_config('crm.envios_masivos', '', true);

SELECT throws_ok(
  $$UPDATE crm.envios_masivos_destinatarios SET gestionado_at = now()
     WHERE envio_masivo_id = (SELECT id FROM ids WHERE clave = 'envio') AND fila = 4$$,
  '42501',
  NULL,
  'Marcar a mano desde el navegador, sin la función, se rechaza'
);

-- =====================================================================
-- 6 · Otra inmobiliaria no ve ni marca
-- =====================================================================
RESET ROLE;
SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;

SELECT is_empty(
  $$SELECT 1 FROM crm.pendientes_gestion_envio((SELECT id FROM ids WHERE clave = 'envio'))$$,
  'Beta no ve a quién hay que gestionar en un envío de Alfa'
);

SELECT throws_ok(
  $$SELECT crm.marcar_gestion_manual(
      (SELECT id FROM ids WHERE clave = 'fila4'), 'desde Beta')$$,
  '22023',
  'Esa fila no existe',
  'Ni la puede marcar: para Beta esa fila no existe'
);

RESET ROLE;
SELECT is(
  (SELECT gestionado_at IS NULL AND gestion_nota IS NULL
     FROM crm.envios_masivos_destinatarios
    WHERE envio_masivo_id = (SELECT id FROM ids WHERE clave = 'envio') AND fila = 4),
  true,
  'Y la fila de Alfa sigue sin gestionar'
);

-- Beta tampoco puede desmarcar lo de Alfa, aunque tenga el id de la fila.
SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$SELECT crm.desmarcar_gestion_manual((SELECT id FROM ids WHERE clave = 'fila3'))$$,
  '22023',
  'Esa fila no existe',
  'Ni deshacer lo que marcó Alfa'
);

-- =====================================================================
-- 7 · Desmarcar, terminar la lista y la purga
-- =====================================================================
RESET ROLE;
SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$SELECT crm.desmarcar_gestion_manual(
      (SELECT id FROM ids WHERE clave = 'fila3'))$$,
  'La admin deshace un «gestionado» puesto por error'
);

SELECT is(
  (SELECT gestionado::text || '|' || COALESCE(gestion_nota, 'sin nota')
     FROM crm.pendientes_gestion_envio((SELECT id FROM ids WHERE clave = 'envio')) WHERE fila = 3),
  'false|sin nota',
  'Vuelve a pendiente y sin la nota'
);

-- Cualquiera del equipo puede gestionar: la admin marca a los seis.
SELECT is(
  (SELECT count(crm.marcar_gestion_manual(p.destinatario_id, 'Gestionado por la admin'))::int
     FROM crm.pendientes_gestion_envio((SELECT id FROM ids WHERE clave = 'envio')) p),
  6,
  'La admin, que no lo lanzó, también puede marcar'
);

SELECT is_empty(
  $$SELECT 1 FROM crm.mi_dia(60, 'cccccccc-cccc-cccc-cccc-cccccccccccc') WHERE tipo = 'gestion_envio_masivo'$$,
  'Con todos gestionados, el renglón se va del día de quien lo lanzó'
);

RESET ROLE;
SELECT set_config('crm.envios_masivos', 'si', true);
UPDATE crm.envios_masivos SET estado = 'terminado', terminado_at = now() - interval '91 days'
 WHERE id = (SELECT id FROM ids WHERE clave = 'envio');
SELECT set_config('crm.envios_masivos', '', true);
SELECT crm.purgar_envios_masivos();

SELECT is(
  (SELECT count(*)::int FROM crm.envios_masivos_destinatarios
    WHERE envio_masivo_id = (SELECT id FROM ids WHERE clave = 'envio')
      AND (gestion_nota IS NOT NULL OR datos IS NOT NULL)),
  0,
  'A los 90 días la purga borra también las notas: hablan de la deuda de una persona'
);

SELECT ok(
  NOT has_function_privilege('anon', 'crm.pendientes_gestion_envio(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'crm.marcar_gestion_manual(uuid, text)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'crm.desmarcar_gestion_manual(uuid)', 'EXECUTE')
  AND has_function_privilege('authenticated', 'crm.marcar_gestion_manual(uuid, text)', 'EXECUTE'),
  'Un anónimo no ve ni marca nada; un usuario con sesión, sí'
);

SELECT * FROM finish();
ROLLBACK;
