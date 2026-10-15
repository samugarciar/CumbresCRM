-- =====================================================================
-- PRUEBA 44: Envíos masivos desde un archivo de cartera
--
-- Recorre la vida entera de un envío: el borrador con sus exclusiones,
-- los cerrojos, el lanzamiento con su confirmación, el despachador con
-- su horario y su tope, lo que contesta la plataforma, la pausa, la
-- cancelación, los resultados para cartera y la purga a los 90 días.
--
-- La red no se toca: crm.pedir_envio_a_plataforma se cambia, dentro de
-- esta transacción, por uno que anota la petición en una tabla temporal.
-- =====================================================================
BEGIN;
SELECT plan(60);

-- ---------------------------------------------------------------------
-- Fixtures (como postgres)
-- ---------------------------------------------------------------------
INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre) VALUES
  ('11111111-1111-1111-1111-111111111111', 'administrativa', '320000000000044', 'Línea Administrativa 320'),
  ('11111111-1111-1111-1111-111111111111', 'comercial',      '324000000000044', 'Línea Comercial 324'),
  ('22222222-2222-2222-2222-222222222222', 'administrativa', '320000000000144', 'Línea de Beta');

INSERT INTO crm.plantillas
  (id, inmobiliaria_id, nombre, cuerpo, categoria, estado_meta, nombre_meta, wa_phone_number_id)
VALUES
  ('fa440001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Recordatorio de pago',
   'Hola {{nombre}}, tu saldo de {{monto}} vence el {{fecha_limite}}.',
   'utilidad', 'aprobada', 'recordatorio_pago', '320000000000044'),
  ('fa440002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'Recordatorio en revisión', 'Hola {{nombre}}, tu saldo es {{monto}}.',
   'utilidad', 'enviada', 'recordatorio_v2', '320000000000044'),
  ('fa440003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
   'Reactivación', 'Hola {{nombre}}, ¿sigues buscando?',
   'marketing', 'aprobada', 'reactivacion', '324000000000044');

-- María: ya es contacto, con su caso administrativo al día.
-- Pedro: pidió no recibir más mensajes. Lucía: recibió otro envío hace 2 días.
INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, opt_out, opt_out_at) VALUES
  ('aaaa0044-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'María', false, NULL),
  ('aaaa0044-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Pedro Gómez', true, now()),
  ('aaaa0044-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Lucía Arango', false, NULL);

INSERT INTO crm.identidades (inmobiliaria_id, contacto_id, tipo, valor, origen) VALUES
  ('11111111-1111-1111-1111-111111111111', 'aaaa0044-0000-0000-0000-000000000001', 'telefono_e164', '+573004400001', 'prueba'),
  ('11111111-1111-1111-1111-111111111111', 'aaaa0044-0000-0000-0000-000000000002', 'telefono_e164', '+573004400002', 'prueba'),
  ('11111111-1111-1111-1111-111111111111', 'aaaa0044-0000-0000-0000-000000000003', 'telefono_e164', '+573004400003', 'prueba');

INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa)
VALUES ('11111111-1111-1111-1111-111111111111', 'aaaa0044-0000-0000-0000-000000000001',
        'administrativa', 'al_dia');

-- El envío anterior de Lucía (con la marca de las funciones, como lo haría el despachador).
SELECT set_config('crm.envios_masivos', 'si', true);
INSERT INTO crm.envios_masivos
  (id, inmobiliaria_id, nombre, columnas, columna_telefono, plantilla_id, wa_phone_number_id,
   estado, lanzado_at, terminado_at)
VALUES ('eeee0044-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'Reactivación de septiembre', ARRAY['Celular'], 'Celular',
        'fa440003-0000-0000-0000-000000000003', '324000000000044',
        'terminado', now() - interval '2 days', now() - interval '2 days');
INSERT INTO crm.envios
  (inmobiliaria_id, contacto_id, plantilla_id, cuerpo, canal, estado, wa_phone_number_id,
   envio_masivo_id, created_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'aaaa0044-0000-0000-0000-000000000003',
        'fa440003-0000-0000-0000-000000000003', 'Hola Lucía…', 'meta', 'entregado',
        '324000000000044', 'eeee0044-0000-0000-0000-000000000001', now() - interval '2 days');
SELECT set_config('crm.envios_masivos', '', true);

-- El archivo de cartera, tal como lo dejaría el navegador: encabezado → valor.
CREATE TEMP TABLE archivo AS SELECT $json$[
  {"Inquilino": "María Restrepo",  "Celular": "300 440 0001",     "Saldo": "$1.250.000", "Vence": "5 de noviembre"},
  {"Inquilino": "Pedro Gómez",     "Celular": "3004400002",       "Saldo": "$900.000",   "Vence": "5 de noviembre"},
  {"Inquilino": "Lucía Arango",    "Celular": "3004400003",       "Saldo": "$700.000",   "Vence": "6 de noviembre"},
  {"Inquilino": "Nuevo Inquilino", "Celular": "3004400004",       "Saldo": "$500.000",   "Vence": "7 de noviembre"},
  {"Inquilino": "Repetida",        "Celular": "+57 300 440 0001", "Saldo": "$1",         "Vence": "x"},
  {"Inquilino": "Sin saldo",       "Celular": "3004400006",       "Saldo": "",           "Vence": "8 de noviembre"},
  {"Inquilino": "Sin celular",     "Celular": "",                 "Saldo": "$1",         "Vence": "x"},
  {"Inquilino": "Celular malo",    "Celular": "12345",            "Saldo": "$1",         "Vence": "x"},
  {"Inquilino": "Otro Nuevo",      "Celular": "3004400009",       "Saldo": "$300.000",   "Vence": "9 de noviembre"}
]$json$::jsonb AS filas;
GRANT SELECT ON archivo TO authenticated;

CREATE TEMP TABLE ids (clave text PRIMARY KEY, id uuid);
GRANT SELECT, INSERT, UPDATE ON ids TO authenticated;

-- Como asesor de Alfa.
SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;

-- =====================================================================
-- 1 · El borrador
-- =====================================================================
INSERT INTO ids
SELECT 'cartera', crm.crear_envio_masivo(
  'Cartera de octubre', 'cartera_octubre.xlsx',
  ARRAY['Inquilino', 'Celular', 'Saldo', 'Vence'],
  (SELECT filas FROM archivo),
  'Celular', 'Inquilino',
  'fa440001-0000-0000-0000-000000000001',
  '{"nombre": "Inquilino", "monto": "Saldo", "fecha_limite": "Vence"}',
  true);

SELECT is(
  (SELECT string_agg(fila || ':' || estado || COALESCE(':' || motivo, ''), ' ' ORDER BY fila)
     FROM crm.envios_masivos_destinatarios
    WHERE envio_masivo_id = (SELECT id FROM ids WHERE clave = 'cartera')),
  '2:listo 3:excluido:baja 4:excluido:frecuencia 5:listo 6:excluido:repetido '
  '7:excluido:faltan_datos 8:excluido:sin_telefono 9:excluido:telefono_invalido 10:listo',
  'Cada fila queda lista o excluida con su motivo; la fila cuenta el encabezado como la 1'
);

SELECT is(
  (SELECT detalle FROM crm.envios_masivos_destinatarios
    WHERE envio_masivo_id = (SELECT id FROM ids WHERE clave = 'cartera') AND fila = 6),
  'Mismo teléfono que la fila 2',
  'Un teléfono repetido dice con qué fila choca, aunque venga escrito distinto'
);

SELECT is(
  (SELECT detalle FROM crm.envios_masivos_destinatarios
    WHERE envio_masivo_id = (SELECT id FROM ids WHERE clave = 'cartera') AND fila = 7),
  'Sin monto',
  'A la fila sin saldo le falta el monto: no sale con un hueco'
);

SELECT is(
  (SELECT cuerpo FROM crm.envios_masivos_destinatarios
    WHERE envio_masivo_id = (SELECT id FROM ids WHERE clave = 'cartera') AND fila = 2),
  'Hola María Restrepo, tu saldo de $1.250.000 vence el 5 de noviembre.',
  'El mensaje de cada fila sale de sus propias columnas'
);

SELECT is(
  (SELECT valores FROM crm.envios_masivos_destinatarios
    WHERE envio_masivo_id = (SELECT id FROM ids WHERE clave = 'cartera') AND fila = 2),
  '{"nombre": "María Restrepo", "monto": "$1.250.000", "fecha_limite": "5 de noviembre"}'::jsonb,
  'Y los valores con nombre son los que recibirá Meta'
);

SELECT is(
  (SELECT telefono_e164 || '|' || COALESCE(contacto_id::text, 'nuevo')
     FROM crm.envios_masivos_destinatarios
    WHERE envio_masivo_id = (SELECT id FROM ids WHERE clave = 'cartera') AND fila = 2),
  '+573004400001|aaaa0044-0000-0000-0000-000000000001',
  'El teléfono se normaliza y reconoce al contacto que ya existía'
);

SELECT is(
  (SELECT count(*)::int FROM crm.contactos WHERE origen = 'cartera'),
  0,
  'Un borrador no crea contactos: si se descarta, no deja gente nueva en el CRM'
);

SELECT is(
  (SELECT estado || '|' || abrir_caso FROM crm.envios_masivos
    WHERE id = (SELECT id FROM ids WHERE clave = 'cartera')),
  'borrador|true',
  'Queda en borrador, y abrirá el caso porque la línea es la administrativa'
);

SELECT throws_ok(
  $$SELECT crm.crear_envio_masivo('Sin fecha', NULL, ARRAY['Inquilino', 'Celular', 'Saldo'],
      (SELECT filas FROM archivo), 'Celular', 'Inquilino',
      'fa440001-0000-0000-0000-000000000001', '{"nombre": "Inquilino", "monto": "Saldo"}', true)$$,
  '22023',
  'Falta decir de qué columna sale: fecha_limite',
  'Cada variable de la plantilla tiene que salir de una columna'
);

SELECT throws_ok(
  $$SELECT crm.crear_envio_masivo('Sin teléfono', NULL, ARRAY['Inquilino'],
      (SELECT filas FROM archivo), 'Celular', 'Inquilino',
      'fa440001-0000-0000-0000-000000000001',
      '{"nombre": "Inquilino", "monto": "Saldo", "fecha_limite": "Vence"}', true)$$,
  '22023',
  NULL,
  'La columna del teléfono tiene que estar en el archivo'
);

SELECT throws_ok(
  $$SELECT crm.crear_envio_masivo('Demasiado', NULL, ARRAY['Celular'],
      (SELECT jsonb_agg(jsonb_build_object('Celular', '300' || lpad(g::text, 7, '0')))
         FROM generate_series(1, 5001) g),
      'Celular', NULL, 'fa440003-0000-0000-0000-000000000003', '{"nombre": "Celular"}', false)$$,
  '22023',
  NULL,
  'Más de 5.000 filas no entran en un envío'
);

INSERT INTO ids
SELECT 'comercial', crm.crear_envio_masivo(
  'Reactivación', NULL, ARRAY['Inquilino', 'Celular'], (SELECT filas FROM archivo),
  'Celular', 'Inquilino', 'fa440003-0000-0000-0000-000000000003',
  '{"nombre": "Inquilino"}', true);

SELECT is(
  (SELECT abrir_caso FROM crm.envios_masivos WHERE id = (SELECT id FROM ids WHERE clave = 'comercial')),
  false,
  'Por la línea comercial no se abre caso administrativo aunque se pida'
);

-- =====================================================================
-- 2 · Los cerrojos: solo con sus funciones
-- =====================================================================
SELECT set_config('crm.envios_masivos', '', true);

SELECT throws_ok(
  $$UPDATE crm.envios_masivos SET estado = 'en_curso', lanzado_at = now()
     WHERE id = (SELECT id FROM ids WHERE clave = 'cartera')$$,
  '42501',
  NULL,
  'Pasar un borrador a «en curso» a mano, sin la confirmación, se rechaza'
);

SELECT throws_ok(
  $$UPDATE crm.envios_masivos_destinatarios SET estado = 'listo', motivo = NULL
     WHERE envio_masivo_id = (SELECT id FROM ids WHERE clave = 'cartera') AND fila = 3$$,
  '42501',
  NULL,
  'Rescatar a mano a quien pidió la baja se rechaza'
);

SELECT throws_ok(
  $$INSERT INTO crm.envios (inmobiliaria_id, contacto_id, cuerpo, envio_masivo_id)
    VALUES ('11111111-1111-1111-1111-111111111111', 'aaaa0044-0000-0000-0000-000000000002',
            'Hola', (SELECT id FROM ids WHERE clave = 'cartera'))$$,
  '42501',
  NULL,
  'Colar un envío en la cola de un envío masivo se rechaza'
);

-- =====================================================================
-- 3 · Lanzar
-- =====================================================================
SELECT throws_ok(
  $$SELECT crm.lanzar_envio_masivo((SELECT id FROM ids WHERE clave = 'cartera'), 2)$$,
  '22023',
  'La confirmación no coincide: son 3 destinatarios',
  'La confirmación es el número exacto de destinatarios, no un «sí»'
);

SELECT is(
  (SELECT count(*)::int FROM crm.contactos WHERE origen = 'cartera'),
  0,
  'Y una confirmación equivocada no deja nada hecho'
);

SELECT is(
  crm.lanzar_envio_masivo((SELECT id FROM ids WHERE clave = 'cartera'), 3),
  3,
  'Con el número exacto se lanza'
);

SELECT is(
  (SELECT count(*)::int FROM crm.contactos c
     JOIN crm.identidades i ON i.contacto_id = c.id AND i.tipo = 'telefono_e164'
    WHERE c.origen = 'cartera' AND i.valor IN ('+573004400004', '+573004400009')),
  2,
  'Los dos que no existían entran al CRM con su teléfono como identidad'
);

SELECT is(
  (SELECT count(*)::int FROM crm.identidades WHERE valor = '+573004400001'),
  1,
  'Y quien ya existía no se duplica'
);

SELECT is(
  (SELECT nombre FROM crm.contactos WHERE id = 'aaaa0044-0000-0000-0000-000000000001'),
  'María Restrepo',
  'El nombre completo del archivo mejora el que había'
);

SELECT is(
  (SELECT etapa FROM crm.oportunidades
    WHERE contacto_id = 'aaaa0044-0000-0000-0000-000000000001'
      AND embudo = 'administrativa' AND estado = 'abierta'),
  'en_mora',
  'El caso que estaba al día pasa a «En mora»'
);

SELECT is(
  (SELECT count(*)::int FROM crm.transiciones t
     JOIN crm.oportunidades o ON o.id = t.oportunidad_id
    WHERE o.contacto_id = 'aaaa0044-0000-0000-0000-000000000001'
      AND t.etapa_desde = 'al_dia' AND t.etapa_hasta = 'en_mora'),
  1,
  'Y queda el movimiento en su historia'
);

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades o
     JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.origen = 'cartera' AND o.embudo = 'administrativa'
      AND o.estado = 'abierta' AND o.etapa = 'en_mora'),
  2,
  'Los nuevos quedan con su caso abierto en «En mora»'
);

SELECT is(
  (SELECT estado || '|' || lanzado_por::text FROM crm.envios_masivos
    WHERE id = (SELECT id FROM ids WHERE clave = 'cartera')),
  'en_curso|cccccccc-cccc-cccc-cccc-cccccccccccc',
  'Queda en curso, con quien lo lanzó'
);

SELECT throws_ok(
  $$SELECT crm.lanzar_envio_masivo((SELECT id FROM ids WHERE clave = 'cartera'), 3)$$,
  '22023',
  NULL,
  'Un envío no se lanza dos veces'
);

INSERT INTO ids
SELECT 'en_revision', crm.crear_envio_masivo(
  'Con plantilla en revisión', NULL, ARRAY['Inquilino', 'Celular', 'Saldo'],
  (SELECT filas FROM archivo), 'Celular', 'Inquilino', 'fa440002-0000-0000-0000-000000000002',
  '{"nombre": "Inquilino", "monto": "Saldo"}', false);

SELECT throws_ok(
  $$SELECT crm.lanzar_envio_masivo((SELECT id FROM ids WHERE clave = 'en_revision'), 2)$$,
  '22023',
  'La plantilla todavía no está aprobada por Meta',
  'Con una plantilla que Meta no ha aprobado no se lanza'
);

SELECT throws_ok(
  $$SELECT crm.ajustar_envio_masivo((SELECT id FROM ids WHERE clave = 'cartera'), 100, 30, 250, 7,
      '{"zona": "America/Bogota", "franjas": {"1": ["08:00", "18:00"]}}')$$,
  '22023',
  NULL,
  'Un envío en curso no se ajusta: primero se pausa'
);

SELECT throws_ok(
  $$SELECT crm.ajustar_envio_masivo((SELECT id FROM ids WHERE clave = 'en_revision'), 100, 30, 250, 7,
      '{"zona": "America/Bogota", "franjas": {"1": ["18:00", "08:00"]}}')$$,
  '22023',
  'Ese horario no es válido',
  'Un horario al revés no se acepta'
);

-- Beta no ve ni mueve lo de Alfa.
RESET ROLE;
SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM crm.envios_masivos WHERE inmobiliaria_id = '11111111-1111-1111-1111-111111111111'),
  0,
  'Otra inmobiliaria no ve los envíos de Alfa'
);

SELECT throws_ok(
  $$SELECT crm.cambiar_estado_envio_masivo((SELECT id FROM ids WHERE clave = 'cartera'), 'cancelar')$$,
  '22023',
  'Ese envío no existe',
  'Ni los puede cancelar'
);

-- =====================================================================
-- 4 · El horario
-- =====================================================================
RESET ROLE;

SELECT ok(
  crm.en_horario_envio((SELECT horario FROM crm.envios_masivos WHERE id = (SELECT id FROM ids WHERE clave = 'cartera')),
                       '2026-10-15 15:00:00+00')
  AND crm.en_horario_envio((SELECT horario FROM crm.envios_masivos WHERE id = (SELECT id FROM ids WHERE clave = 'cartera')),
                       '2026-10-17 17:00:00+00'),
  'Un jueves a las 10 y un sábado a las 12, hora de Bogotá, sí'
);

SELECT ok(
  NOT crm.en_horario_envio((SELECT horario FROM crm.envios_masivos WHERE id = (SELECT id FROM ids WHERE clave = 'cartera')),
                           '2026-10-15 12:59:00+00')
  AND NOT crm.en_horario_envio((SELECT horario FROM crm.envios_masivos WHERE id = (SELECT id FROM ids WHERE clave = 'cartera')),
                           '2026-10-15 23:00:00+00')
  AND NOT crm.en_horario_envio((SELECT horario FROM crm.envios_masivos WHERE id = (SELECT id FROM ids WHERE clave = 'cartera')),
                           '2026-10-17 19:00:00+00'),
  'Antes de las 8, después de las 18, y un sábado después de las 13, no'
);

SELECT ok(
  NOT crm.en_horario_envio((SELECT horario FROM crm.envios_masivos WHERE id = (SELECT id FROM ids WHERE clave = 'cartera')),
                           '2026-10-18 15:00:00+00')
  AND NOT crm.en_horario_envio((SELECT horario FROM crm.envios_masivos WHERE id = (SELECT id FROM ids WHERE clave = 'cartera')),
                           '2026-11-02 15:00:00+00'),
  'Ni un domingo ni un festivo (Todos los Santos), aunque sea a las 10'
);

-- =====================================================================
-- 5 · El despachador
--
-- Corre con un reloj fijo (p_ahora). El lanzamiento dejó el próximo lote
-- en la hora real; se pone a las 14:00 del jueves 15 de octubre para que
-- la prueba no dependa de cuándo se corra.
-- =====================================================================
SELECT set_config('crm.envios_masivos', 'si', true);
UPDATE crm.envios_masivos
   SET proximo_lote_at = '2026-10-15 14:00:00+00', tamano_lote = 1
 WHERE id = (SELECT id FROM ids WHERE clave = 'cartera');
SELECT set_config('crm.envios_masivos', '', true);

-- La red, de mentira: se anota la petición y se devuelve un id.
CREATE TEMP TABLE peticiones (n serial, url text, token text, cuerpo jsonb);
CREATE OR REPLACE FUNCTION crm.pedir_envio_a_plataforma(p_url text, p_token text, p_cuerpo jsonb)
RETURNS bigint
LANGUAGE sql VOLATILE SET search_path = ''
AS $f$
  INSERT INTO pg_temp.peticiones (url, token, cuerpo)
  VALUES (p_url, p_token, p_cuerpo)
  RETURNING 900000 + n;
$f$;

-- Sin el canal en Vault, nada sale y el envío lo dice.
SELECT is(
  crm.despachar_envios_masivos('2026-10-15 15:00:00+00'),
  0,
  'Sin la URL y el token en Vault no sale nada'
);

SELECT matches(
  (SELECT ultimo_aviso FROM crm.envios_masivos WHERE id = (SELECT id FROM ids WHERE clave = 'cartera')),
  'falta configurar el canal',
  'Y el envío avisa por qué está esperando'
);

SELECT vault.create_secret('https://plataforma.prueba/', 'crm_plataforma_url');
SELECT vault.create_secret('token-de-prueba', 'crm_envio_token');

SELECT is(
  crm.despachar_envios_masivos('2026-10-18 15:00:00+00'),
  0,
  'Un domingo no sale nada'
);

SELECT is(
  crm.despachar_envios_masivos('2026-10-15 15:00:00+00'),
  1,
  'Un jueves a las 10 sale el primer lote (de uno)'
);

SELECT is(
  (SELECT cuerpo FROM peticiones WHERE n = 1),
  jsonb_build_object(
    'inmobiliaria_id', '11111111-1111-1111-1111-111111111111',
    'telefono', '+573004400001',
    'texto', 'Hola María Restrepo, tu saldo de $1.250.000 vence el 5 de noviembre.',
    'envio_id', (SELECT envio_id FROM crm.envios_masivos_destinatarios
                  WHERE envio_masivo_id = (SELECT id FROM ids WHERE clave = 'cartera') AND fila = 2),
    'desde', jsonb_build_object('wa_phone_number_id', '320000000000044', 'embudo', 'administrativa'),
    'plantilla', jsonb_build_object(
      'nombre_meta', 'recordatorio_pago', 'idioma', 'es',
      'variables', '{"nombre": "María Restrepo", "monto": "$1.250.000", "fecha_limite": "5 de noviembre"}'::jsonb)),
  'A la plataforma le llega lo mismo que manda un envío suelto (contrato C1), con las variables'
);

SELECT is(
  (SELECT url || '|' || token FROM peticiones WHERE n = 1),
  'https://plataforma.prueba/|token-de-prueba',
  'Con la URL y el token de Vault'
);

SELECT is(
  (SELECT e.estado || '|' || (e.tomado_at = '2026-10-15 15:00:00+00') || '|' || e.solicitud_http
     FROM crm.envios e
    WHERE e.id = (SELECT envio_id FROM crm.envios_masivos_destinatarios
                   WHERE envio_masivo_id = (SELECT id FROM ids WHERE clave = 'cartera') AND fila = 2)),
  'pendiente|true|900001',
  'El envío queda pendiente, tomado, y con su petición: tomado no se vuelve a mandar'
);

SELECT is(
  crm.despachar_envios_masivos('2026-10-15 15:10:00+00'),
  0,
  'El lote siguiente espera los minutos entre lotes'
);

-- Tope de 2 personas por día en la línea, para ver el freno.
SELECT set_config('crm.envios_masivos', 'si', true);
UPDATE crm.envios_masivos SET tope_diario = 2
 WHERE id = (SELECT id FROM ids WHERE clave = 'cartera');
SELECT set_config('crm.envios_masivos', '', true);

SELECT is(
  crm.despachar_envios_masivos('2026-10-15 15:31:00+00'),
  1,
  'Pasados los 30 minutos sale otro, hasta llenar el tope diario de la línea'
);

SELECT is(
  crm.despachar_envios_masivos('2026-10-15 16:02:00+00'),
  0,
  'Con el tope lleno, el lote siguiente no sale'
);

SELECT matches(
  (SELECT ultimo_aviso FROM crm.envios_masivos WHERE id = (SELECT id FROM ids WHERE clave = 'cartera')),
  'su tope',
  'Y el envío dice que está esperando por el tope'
);

-- =====================================================================
-- 6 · Lo que contesta la plataforma
-- =====================================================================
INSERT INTO net._http_response (id, status_code, content) VALUES
  (900001, 200, '{"ok": true, "wa_message_id": "wamid.prueba1"}'),
  (900002, 409, '{"ok": false, "error": "La línea no tiene credencial"}');

SELECT is(crm.anotar_respuestas_plataforma(), 2,
  'Se leen las dos respuestas');

SELECT is(
  (SELECT e.estado || '|' || e.wa_message_id FROM crm.envios e WHERE e.solicitud_http = 900001),
  'enviado|wamid.prueba1',
  'Un 200 con su wa_message_id queda enviado, aunque la plataforma no lo hubiera anotado'
);

SELECT is(
  (SELECT count(*)::int FROM crm.envios WHERE solicitud_http = 900002),
  0,
  'Un 409 es el canal, no el mensaje: no salió nada, así que ese envío se deshace'
);

SELECT is(
  (SELECT d.estado || '|' || m.estado
     FROM crm.envios_masivos_destinatarios d
     JOIN crm.envios_masivos m ON m.id = d.envio_masivo_id
    WHERE d.envio_masivo_id = (SELECT id FROM ids WHERE clave = 'cartera') AND d.fila = 5),
  'listo|pausado',
  'La persona vuelve a la cola y el envío se pausa para que alguien mire'
);

-- =====================================================================
-- 7 · Pausa, plantilla caída y cancelación
-- =====================================================================
SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;

SELECT is(
  crm.cambiar_estado_envio_masivo((SELECT id FROM ids WHERE clave = 'cartera'), 'reanudar'),
  'en_curso',
  'Se reanuda'
);

RESET ROLE;
UPDATE crm.plantillas SET estado_meta = 'rechazada', motivo_rechazo_meta = 'Pausada por Meta por baja calidad'
 WHERE id = 'fa440001-0000-0000-0000-000000000001';

SELECT is(
  crm.despachar_envios_masivos('2099-06-01 15:00:00+00'),
  0,
  'Si la plantilla dejó de estar aprobada, no sale nada…'
);

SELECT is(
  (SELECT estado || '|' || ultimo_aviso FROM crm.envios_masivos
    WHERE id = (SELECT id FROM ids WHERE clave = 'cartera')),
  'pausado|Se pausó: la plantilla ya no está aprobada por Meta.',
  '…y el envío se pausa diciendo por qué'
);

SET LOCAL ROLE authenticated;
SELECT is(
  crm.cambiar_estado_envio_masivo((SELECT id FROM ids WHERE clave = 'cartera'), 'cancelar'),
  'cancelado',
  'Se cancela'
);

SELECT is(
  (SELECT string_agg(fila || ':' || estado, ' ' ORDER BY fila)
     FROM crm.envios_masivos_destinatarios
    WHERE envio_masivo_id = (SELECT id FROM ids WHERE clave = 'cartera')
      AND estado IN ('cancelado', 'encolado')),
  '2:encolado 5:cancelado 10:cancelado',
  'Lo que no había salido queda cancelado; lo que salió, salió'
);

-- =====================================================================
-- 8 · Lo que se le devuelve a cartera
-- =====================================================================
RESET ROLE;
INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, wa_phone_number_id)
VALUES ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
        'aaaa0044-0000-0000-0000-000000000001', 'Ya pagué, te mando el comprobante',
        now() + interval '1 hour', '320000000000044');
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT resultado || '|' || (respondio_at IS NOT NULL) || '|' || (datos ->> 'Saldo')
     FROM crm.resultados_envio_masivo((SELECT id FROM ids WHERE clave = 'cartera'))
    WHERE fila = 2),
  'enviado|true|$1.250.000',
  'La fila de María vuelve con su estado, que respondió, y sus columnas originales'
);

SELECT is(
  crm.resumen_envio_masivo((SELECT id FROM ids WHERE clave = 'cartera'))
    - 'por_motivo' - 'en_cola' - 'enviando' - 'entregados' - 'leidos' - 'bajas',
  '{"total": 9, "excluidos": 6, "cancelados": 2, "sin_confirmar": 0, "enviados": 1,
    "fallidos": 0, "respondieron": 1}'::jsonb,
  'El resumen cuadra con las filas'
);

-- =====================================================================
-- 9 · La purga y quién puede llamar qué
-- =====================================================================
RESET ROLE;
SELECT set_config('crm.envios_masivos', 'si', true);
UPDATE crm.envios_masivos SET terminado_at = now() - interval '91 days'
 WHERE id = (SELECT id FROM ids WHERE clave = 'cartera');

SELECT is(crm.purgar_envios_masivos(), 9,
  'A los 90 días se borran las filas originales del archivo');

SELECT is(
  (SELECT count(*)::int FROM crm.envios_masivos_destinatarios
    WHERE envio_masivo_id = (SELECT id FROM ids WHERE clave = 'cartera')
      AND (datos IS NOT NULL OR cuerpo IS NOT NULL OR valores <> '{}'::jsonb)),
  0,
  'No queda ni la fila, ni el texto, ni los valores: traían deudas de personas'
);

SELECT ok(
  NOT has_function_privilege('authenticated', 'crm.despachar_envios_masivos(timestamptz)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'crm.purgar_envios_masivos(timestamptz, int)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'crm.anotar_respuestas_plataforma()', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'crm.pedir_envio_a_plataforma(text, text, jsonb)', 'EXECUTE'),
  'El despachador, la purga y la salida a la red no se llaman desde el navegador'
);

SELECT ok(
  NOT has_function_privilege('anon', 'crm.crear_envio_masivo(text, text, text[], jsonb, text, text, uuid, jsonb, boolean)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'crm.lanzar_envio_masivo(uuid, int)', 'EXECUTE'),
  'Un anónimo no prepara ni lanza nada'
);

SELECT * FROM finish();
ROLLBACK;
