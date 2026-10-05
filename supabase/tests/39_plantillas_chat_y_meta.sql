-- =====================================================================
-- Prueba 39: Plantillas de Chat vs. WhatsApp Meta (Decisiones 29 y 30)
--
-- Verifica:
-- 1. Que existan las columnas tipo, idioma y motivo_rechazo_meta.
-- 2. Que tipo solo acepte 'chat' o 'whatsapp'.
-- 3. Que una plantilla de chat se guarde aprobada sin exigir nombre_meta.
-- 4. Que una plantilla de whatsapp aprobada siga exigiendo nombre_meta.
-- 5. Que una plantilla de chat acepte categorías adicionales como 'general'.
-- 6. Que una plantilla de whatsapp solo acepte 'utilidad' o 'marketing'.
-- 7. Que crm.render_plantilla funcione transparentemente con tipo 'chat'.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(8);

-- 1. Columnas existen
SELECT has_column('crm', 'plantillas', 'tipo', 'crm.plantillas tiene columna tipo');
SELECT has_column('crm', 'plantillas', 'idioma', 'crm.plantillas tiene columna idioma');
SELECT has_column('crm', 'plantillas', 'motivo_rechazo_meta', 'crm.plantillas tiene columna motivo_rechazo_meta');

-- 2. Tipo inválido revienta
SELECT throws_ok(
  $$INSERT INTO crm.plantillas (inmobiliaria_id, nombre, cuerpo, tipo)
    VALUES ('11111111-1111-1111-1111-111111111111', 'Tipo inválido',
            'Hola {{nombre}}', 'sms')$$,
  '23514',
  NULL,
  'Un tipo distinto a chat o whatsapp no se guarda'
);

-- 3. Chat aprobado sin nombre_meta SE GUARDA
SELECT lives_ok(
  $$INSERT INTO crm.plantillas (inmobiliaria_id, nombre, cuerpo, tipo, estado_meta, categoria)
    VALUES ('11111111-1111-1111-1111-111111111111', 'Respuesta rápida de chat',
            'Hola {{nombre}}, nuestro horario es de 8 a 5.', 'chat', 'aprobada', 'general')$$,
  'Una plantilla de chat aprobada no exige nombre_meta de Meta'
);

-- 4. WhatsApp aprobado sin nombre_meta REVIENTA
SELECT throws_ok(
  $$INSERT INTO crm.plantillas (inmobiliaria_id, nombre, cuerpo, tipo, estado_meta, categoria)
    VALUES ('11111111-1111-1111-1111-111111111111', 'WhatsApp incompleto',
            'Hola {{nombre}}', 'whatsapp', 'aprobada', 'utilidad')$$,
  '23514',
  NULL,
  'Una plantilla de whatsapp aprobada sigue exigiendo el nombre_meta'
);

-- 5. WhatsApp con categoría no permitida por Meta REVIENTA
SELECT throws_ok(
  $$INSERT INTO crm.plantillas (inmobiliaria_id, nombre, cuerpo, tipo, categoria)
    VALUES ('11111111-1111-1111-1111-111111111111', 'WhatsApp categoría libre',
            'Hola {{nombre}}', 'whatsapp', 'general')$$,
  '23514',
  NULL,
  'Una plantilla de WhatsApp no puede usar categorías ajenas a Meta como general'
);

-- 6. Renderizado de plantilla de chat funciona
INSERT INTO crm.plantillas (id, inmobiliaria_id, nombre, cuerpo, tipo, categoria)
VALUES ('88880001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'Chat Horarios',
        'Hola {{nombre}}, le atiende {{asesor}}. Abrimos de lunes a viernes.',
        'chat',
        'general');

INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164)
VALUES ('ee00bb01-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'Carlos Morales', '+573009990001');

SELECT is(
  crm.render_plantilla('88880001-0000-0000-0000-000000000001',
                       'ee00bb01-0000-0000-0000-000000000001',
                       NULL,
                       'Alejandro'),
  'Hola Carlos Morales, le atiende Alejandro. Abrimos de lunes a viernes.',
  'crm.render_plantilla funciona de forma transparente con plantillas de chat'
);

SELECT * FROM finish();
ROLLBACK;
