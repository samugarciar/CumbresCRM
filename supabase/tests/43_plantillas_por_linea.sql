-- =====================================================================
-- PRUEBA 43: Plantillas por línea, sus valores y la sincronización con Meta
--
-- Lo que vigila:
--  · una plantilla de WhatsApp sale solo por la línea de su WABA;
--  · las respuestas rápidas de chat no son de ninguna línea ni abren la
--    puerta fuera de la ventana;
--  · el texto que ve el asesor y los parámetros que recibe Meta salen de
--    los mismos valores, y lo que falta se ve;
--  · la sincronización solo la hace un admin, sobre una línea suya, y no
--    trae lo que no se podría mandar bien.
-- =====================================================================
BEGIN;
SELECT plan(30);

-- ---------------------------------------------------------------------
-- Fixtures (como postgres)
-- ---------------------------------------------------------------------
INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre) VALUES
  ('11111111-1111-1111-1111-111111111111', 'comercial',      '324000000000043', 'Línea Comercial 324'),
  ('11111111-1111-1111-1111-111111111111', 'administrativa', '320000000000043', 'Línea Administrativa 320'),
  ('22222222-2222-2222-2222-222222222222', 'administrativa', '320000000000143', 'Línea de Beta');

-- Nunca escribió: para el CRM, la ventana está cerrada.
INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164)
VALUES ('aaaa0043-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'María Restrepo', '+573004300001');

-- =====================================================================
-- 1 · La línea de una plantilla
-- =====================================================================
SELECT throws_ok(
  $$INSERT INTO crm.plantillas (inmobiliaria_id, nombre, cuerpo, tipo, categoria, wa_phone_number_id)
    VALUES ('11111111-1111-1111-1111-111111111111', 'Chat con línea', 'Hola', 'chat', 'general',
            '320000000000043')$$,
  '23514',
  NULL,
  'Una respuesta rápida de chat no puede ser de una línea: no pasa por Meta'
);

INSERT INTO crm.plantillas
  (id, inmobiliaria_id, nombre, cuerpo, categoria, estado_meta, nombre_meta, wa_phone_number_id)
VALUES
  ('fa430001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Recordatorio', 'Hola {{nombre}}, te recordamos tu cita', 'utilidad', 'aprobada',
   'recordatorio', '320000000000043');

SELECT lives_ok(
  $$INSERT INTO crm.plantillas
      (inmobiliaria_id, nombre, cuerpo, categoria, estado_meta, nombre_meta, wa_phone_number_id)
    VALUES ('11111111-1111-1111-1111-111111111111', 'Recordatorio',
            'Hola {{nombre}}', 'utilidad', 'aprobada', 'recordatorio', '324000000000043')$$,
  'El mismo nombre visible puede existir en otra línea: cada WABA tiene las suyas'
);

SELECT throws_ok(
  $$INSERT INTO crm.plantillas
      (inmobiliaria_id, nombre, cuerpo, categoria, estado_meta, nombre_meta, wa_phone_number_id)
    VALUES ('11111111-1111-1111-1111-111111111111', 'Otro título',
            'Hola {{nombre}}', 'utilidad', 'aprobada', 'recordatorio', '320000000000043')$$,
  '23505',
  NULL,
  'Pero en una misma línea no se repite el nombre en Meta con el mismo idioma'
);

-- =====================================================================
-- 2 · El relleno
-- =====================================================================
SELECT is(crm.hueco_variable('precio'), '[sin precio]',
  'El hueco de una variable conocida es el de siempre');

SELECT is(crm.hueco_variable('monto'), '[sin monto]',
  'Una variable sin hueco propio se ve igual de claro');

SELECT is(
  crm.rellenar_cuerpo('Hola {{ nombre }}, {{precio}}', '{"nombre": "{{precio}}", "precio": "$1"}'),
  'Hola {{precio}}, $1',
  'Una sola pasada: lo que se pone no se vuelve a leer como variable'
);

SELECT is(
  crm.rellenar_cuerpo('Hola {{nombre}}', jsonb_build_object('nombre', E'a\\1&b')),
  E'Hola a\\1&b',
  'Barras y «&» en un valor quedan tal cual: no es una expresión regular'
);

SELECT is(
  crm.rellenar_cuerpo('Hola {{nombre}}', '{"nombre": "   "}'),
  'Hola [sin nombre]',
  'Un valor en blanco cuenta como dato que falta'
);

INSERT INTO crm.plantillas (id, inmobiliaria_id, nombre, cuerpo, categoria)
VALUES ('fa430002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
        'Con precio', 'Hola {{nombre}}, soy {{asesor}}. Desde {{ precio }}', 'marketing');

SELECT is(
  crm.valores_plantilla('fa430002-0000-0000-0000-000000000002',
                        'aaaa0043-0000-0000-0000-000000000001', NULL, 'Ana'),
  '{"nombre": "María Restrepo", "asesor": "Ana", "precio": null}'::jsonb,
  'Los valores son solo los que usa el cuerpo, y lo que falta va en NULL: nunca se inventa'
);

SELECT is(
  crm.render_plantilla('fa430002-0000-0000-0000-000000000002',
                       'aaaa0043-0000-0000-0000-000000000001', NULL, 'Ana'),
  'Hola María Restrepo, soy Ana. Desde [sin precio]',
  'El texto que ve el asesor sale de esos mismos valores, con el hueco visible'
);

SELECT is(
  crm.valores_plantilla('fa430099-0000-0000-0000-000000000099', NULL, NULL, NULL),
  NULL,
  'Una plantilla que no existe no tiene valores'
);

-- =====================================================================
-- 3 · Sincronizar con Meta, como admin de Alfa
-- =====================================================================
-- Un borrador de antes de las líneas, con nombre en Meta: se adopta.
INSERT INTO crm.plantillas
  (id, inmobiliaria_id, nombre, cuerpo, categoria, estado_meta, nombre_meta)
VALUES ('fa430003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
        'Bienvenida', 'Hola {{nombre}}', 'utilidad', 'borrador', 'bienvenida');

SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;

SELECT is(
  crm.sincronizar_plantillas('320000000000043', $json$[
    {"name": "aviso_pago", "status": "APPROVED", "category": "UTILITY", "language": "es",
     "rejected_reason": "NONE",
     "components": [{"type": "BODY", "text": "Hola {{nombre}}, te escribimos de Cumbres"}]},
    {"name": "promo_numerada", "status": "APPROVED", "category": "MARKETING", "language": "es",
     "components": [{"type": "BODY", "text": "Hola {{1}}"}]},
    {"name": "con_desconocida", "status": "APPROVED", "category": "UTILITY", "language": "es",
     "components": [{"type": "BODY", "text": "Hola {{codigo}}"}]},
    {"name": "codigo_acceso", "status": "APPROVED", "category": "AUTHENTICATION", "language": "es",
     "components": [{"type": "BODY", "text": "Tu código"}]},
    {"name": "pausada", "status": "PAUSED", "category": "MARKETING", "language": "es",
     "rejected_reason": "NONE",
     "components": [{"type": "BODY", "text": "Hola {{nombre}}"}]},
    {"name": "bienvenida", "status": "PENDING", "category": "UTILITY", "language": "es",
     "components": [{"type": "BODY", "text": "Hola {{nombre}}, bienvenido"}]},
    {"name": "recordatorio", "status": "APPROVED", "category": "UTILITY", "language": "es",
     "components": [{"type": "BODY", "text": "Hola {{nombre}}, te recordamos tu cita"}]}
  ]$json$::jsonb) - 'omitidas',
  '{"total": 7, "agregadas": 2, "actualizadas": 2, "retiradas": 0}'::jsonb,
  'Agrega las nuevas, actualiza la existente y adopta el borrador sin línea'
);

SELECT is(
  (SELECT array_agg(o ->> 'nombre_meta' ORDER BY o ->> 'nombre_meta')
     FROM jsonb_array_elements(
       crm.sincronizar_plantillas('320000000000043', $json$[
         {"name": "promo_numerada", "status": "APPROVED", "category": "MARKETING", "language": "es",
          "components": [{"type": "BODY", "text": "Hola {{1}}"}]},
         {"name": "con_desconocida", "status": "APPROVED", "category": "UTILITY", "language": "es",
          "components": [{"type": "BODY", "text": "Hola {{codigo}}"}]},
         {"name": "codigo_acceso", "status": "APPROVED", "category": "AUTHENTICATION", "language": "es",
          "components": [{"type": "BODY", "text": "Tu código"}]}
       ]$json$::jsonb, false) -> 'omitidas') o),
  ARRAY['codigo_acceso', 'con_desconocida', 'promo_numerada'],
  'No trae lo que no se podría mandar bien: variables numeradas o desconocidas, ni autenticación'
);

SELECT is(
  (SELECT estado_meta || '|' || categoria || '|' || wa_phone_number_id
     FROM crm.plantillas WHERE nombre_meta = 'aviso_pago' AND activa),
  'aprobada|utilidad|320000000000043',
  'La nueva queda aprobada, de utilidad y de la línea que se sincronizó'
);

SELECT is(
  (SELECT estado_meta || '|' || motivo_rechazo_meta
     FROM crm.plantillas WHERE nombre_meta = 'pausada' AND activa),
  'rechazada|Pausada por Meta por baja calidad',
  'Una pausada por Meta no se puede mandar, y el motivo lo dice'
);

SELECT is(
  (SELECT estado_meta || '|' || COALESCE(wa_phone_number_id, 'sin línea')
     FROM crm.plantillas WHERE id = 'fa430003-0000-0000-0000-000000000003'),
  'enviada|320000000000043',
  'El borrador sin línea que ya estaba en Meta se adopta: queda en esta línea y en revisión'
);

SELECT is(
  crm.sincronizar_plantillas('320000000000043', $json$[
    {"name": "recordatorio", "status": "APPROVED", "category": "UTILITY", "language": "es",
     "components": [{"type": "BODY", "text": "Hola {{nombre}}, te recordamos tu cita"}]},
    {"name": "bienvenida", "status": "REJECTED", "category": "UTILITY", "language": "es",
     "rejected_reason": "INVALID_FORMAT",
     "components": [{"type": "BODY", "text": "Hola {{nombre}}, bienvenido"}]}
  ]$json$::jsonb) -> 'retiradas',
  '1'::jsonb,
  'Con la lista completa, la aprobada que ya no está en Meta se retira'
);

SELECT is(
  (SELECT estado_meta || '|' || motivo_rechazo_meta
     FROM crm.plantillas WHERE nombre_meta = 'aviso_pago' AND activa),
  'rechazada|Ya no está en Meta: se borró de la cuenta de WhatsApp de esta línea',
  'Y queda rechazada con el motivo: mandarla daría error delante del cliente'
);

SELECT is(
  (SELECT estado_meta || '|' || motivo_rechazo_meta FROM crm.plantillas
    WHERE id = 'fa430003-0000-0000-0000-000000000003'),
  'rechazada|INVALID_FORMAT',
  'El motivo de rechazo de Meta se guarda tal cual'
);

SELECT is(
  (crm.sincronizar_plantillas('320000000000043', '[]'::jsonb, false) -> 'retiradas'),
  '0'::jsonb,
  'Con una lista incompleta no se retira nada: no se sabe qué faltó'
);

SELECT throws_ok(
  $$SELECT crm.sincronizar_plantillas('320000000000143', '[]'::jsonb)$$,
  '22023',
  NULL,
  'La línea de otra inmobiliaria no existe para Alfa'
);

SELECT throws_ok(
  $$SELECT crm.sincronizar_plantillas('320000000000043', '{"no": "es lista"}'::jsonb)$$,
  '22023',
  NULL,
  'Lo que no es una lista de plantillas se rechaza'
);

-- Un asesor no sincroniza: escribir plantillas es de admin.
RESET ROLE;
SELECT set_config('request.jwt.claims', json_build_object(
  'sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$SELECT crm.sincronizar_plantillas('320000000000043', '[]'::jsonb)$$,
  '42501',
  NULL,
  'Un asesor no puede sincronizar plantillas'
);

-- =====================================================================
-- 4 · encolar_envio: la plantilla de su línea, y solo la de WhatsApp
-- =====================================================================
SELECT throws_ok(
  $$SELECT crm.encolar_envio('aaaa0043-0000-0000-0000-000000000001',
        'Hola María, te recordamos tu cita', 'fa430001-0000-0000-0000-000000000001',
        NULL, '324000000000043')$$,
  '22023',
  NULL,
  'Una plantilla del 320 no sale por el 324: en esa WABA no existe'
);

SELECT throws_ok(
  $$SELECT crm.encolar_envio('aaaa0043-0000-0000-0000-000000000001',
        'Hola María, te recordamos tu cita', 'fa430001-0000-0000-0000-000000000001')$$,
  '22023',
  NULL,
  'Ni sin línea: el número por defecto tampoco la tiene'
);

SELECT lives_ok(
  $$SELECT crm.encolar_envio('aaaa0043-0000-0000-0000-000000000001',
        'Hola María, te recordamos tu cita', 'fa430001-0000-0000-0000-000000000001',
        NULL, '320000000000043')$$,
  'Por su línea, aprobada, sí sale aunque la ventana esté cerrada'
);

RESET ROLE;
INSERT INTO crm.plantillas (id, inmobiliaria_id, nombre, cuerpo, tipo, categoria, estado_meta)
VALUES ('fa430004-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111',
        'Horario', 'Atendemos de 8 a 5', 'chat', 'general', 'aprobada');
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$SELECT crm.encolar_envio('aaaa0043-0000-0000-0000-000000000001',
        'Atendemos de 8 a 5', 'fa430004-0000-0000-0000-000000000004')$$,
  '23514',
  NULL,
  'Una respuesta rápida de chat no abre la puerta fuera de la ventana: sale como texto libre'
);

-- =====================================================================
-- 5 · Quién puede llamar
-- =====================================================================
RESET ROLE;

SELECT ok(
  has_function_privilege('authenticated', 'crm.sincronizar_plantillas(text, jsonb, boolean)', 'EXECUTE')
  AND has_function_privilege('authenticated', 'crm.valores_plantilla(uuid, uuid, uuid, text)', 'EXECUTE'),
  'La pantalla puede sincronizar y pedir valores con la sesión del usuario'
);

SELECT ok(
  NOT has_function_privilege('anon', 'crm.sincronizar_plantillas(text, jsonb, boolean)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'crm.valores_plantilla(uuid, uuid, uuid, text)', 'EXECUTE'),
  'Un anónimo no'
);

SELECT is(
  (SELECT count(*)::int FROM pg_proc
    WHERE pronamespace = 'crm'::regnamespace
      AND proname IN ('sincronizar_plantillas', 'valores_plantilla', 'rellenar_cuerpo', 'hueco_variable')
      AND prosecdef),
  0,
  'Ninguna es SECURITY DEFINER: corren con la RLS de quien llama'
);

SELECT * FROM finish();
ROLLBACK;
