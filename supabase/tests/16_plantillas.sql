-- =====================================================================
-- Plantillas de mensaje.
--
-- Lo que se mide: que una plantilla rota reviente AL GUARDARLA y no
-- delante del cliente, que el relleno use datos de verdad, que lo que
-- falta se vea en vez de colarse, y que escribirlas sea cosa de admin —
-- una plantilla mal escrita sale a cientos de personas de golpe.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(14);

DELETE FROM crm.contactos;

INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164)
VALUES ('ee00aa01-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'María Restrepo', '+573001110001'),
       ('ee00aa02-0000-0000-0000-000000000002',
        '11111111-1111-1111-1111-111111111111',
        NULL, '+573001110002');

INSERT INTO public.inmuebles
  (id, inmobiliaria_id, asesor_id, titulo, direccion, ciudad, barrio,
   habitaciones, banos, precio, tipo_transaccion, tipo_inmueble, estado)
VALUES ('11110a01-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'Apto Niquía 302', 'Cra 50', 'Bello', 'Niquia',
        3, 2, 1500000, 'arriendo', 'apartamento', 'disponible');

-- --- Las sembradas ----------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM crm.plantillas
    WHERE inmobiliaria_id = '11111111-1111-1111-1111-111111111111'),
  3,
  'Cada inmobiliaria arranca con tres plantillas: una pantalla vacía no enseña qué forma tiene una'
);

-- =====================================================================
-- LA AFIRMACIÓN QUE MÁS IMPORTA: que reviente al guardar
--
-- Una plantilla que menciona {{descuento}} —que no existe— se enviaría
-- con el hueco sin rellenar a un cliente real.
-- =====================================================================
SELECT throws_ok(
  $$INSERT INTO crm.plantillas (inmobiliaria_id, nombre, cuerpo)
    VALUES ('11111111-1111-1111-1111-111111111111', 'Rota',
            'Hola {{nombre}}, te damos {{descuento}} de rebaja')$$,
  '23514',
  NULL,
  'Una plantilla con una variable que no existe NO se guarda'
);

SELECT is(
  crm.variables_desconocidas('Hola {{nombre}}, mira {{inmueble}} por {{precio}}'),
  ARRAY[]::text[],
  'Y una que solo usa variables reales pasa limpia'
);

SELECT is(
  crm.variables_desconocidas('{{descuento}} y {{comision}}'),
  ARRAY['comision','descuento'],
  'Las desconocidas se nombran, para poder decir CUÁL está mal'
);

-- Aprobada sin nombre en Meta es una plantilla que no se puede usar.
SELECT throws_ok(
  $$INSERT INTO crm.plantillas (inmobiliaria_id, nombre, cuerpo, estado_meta)
    VALUES ('11111111-1111-1111-1111-111111111111', 'Aprobada a medias',
            'Hola {{nombre}}', 'aprobada')$$,
  '23514',
  NULL,
  'Aprobada sin el nombre exacto de Meta no se guarda: no se podría enviar'
);

-- =====================================================================
-- El relleno con datos de verdad
-- =====================================================================
INSERT INTO crm.plantillas (id, inmobiliaria_id, nombre, cuerpo, categoria)
VALUES ('99990001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'Prueba',
        'Hola {{nombre}}, te escribe {{asesor}}. Mira {{inmueble}} en {{barrio}}: {{habitaciones}} hab por {{precio}}.',
        'marketing');

SELECT is(
  crm.render_plantilla('99990001-0000-0000-0000-000000000001',
                       'ee00aa01-0000-0000-0000-000000000001',
                       '11110a01-0000-0000-0000-000000000001',
                       'Gisela'),
  'Hola María Restrepo, te escribe Gisela. Mira Apto Niquía 302 en Niquia: 3 hab por $1.500.000.',
  'La plantilla sale rellena con el nombre, el inmueble y el precio reales'
);

-- El punto de miles colombiano, no la coma del locale del servidor.
SELECT ok(
  crm.render_plantilla('99990001-0000-0000-0000-000000000001',
                       'ee00aa01-0000-0000-0000-000000000001',
                       '11110a01-0000-0000-0000-000000000001',
                       'Gisela') LIKE '%$1.500.000%',
  'Con el separador de miles colombiano, no el del locale del servidor'
);

-- LO QUE FALTA SE VE. Un hueco vacío se cuela hasta el cliente; un
-- corchete lo para el asesor antes de copiar.
SELECT ok(
  crm.render_plantilla('99990001-0000-0000-0000-000000000001',
                       'ee00aa02-0000-0000-0000-000000000002',
                       '11110a01-0000-0000-0000-000000000001',
                       'Gisela') LIKE '%[sin nombre]%',
  'Un contacto sin nombre deja "[sin nombre]" visible, no un hueco en blanco'
);

SELECT ok(
  crm.render_plantilla('99990001-0000-0000-0000-000000000001',
                       'ee00aa01-0000-0000-0000-000000000001',
                       NULL, 'Gisela') LIKE '%[sin inmueble]%',
  'Y sin inmueble, lo mismo: el asesor lo ve antes de mandarlo'
);

SELECT is(
  crm.render_plantilla('99990001-0000-0000-0000-000000000001',
                       'ee00aa01-0000-0000-0000-000000000001',
                       '11110a01-0000-0000-0000-000000000001',
                       NULL) LIKE '%{{%',
  false,
  'No queda ni una variable sin reemplazar, pase lo que pase'
);

-- =====================================================================
-- Quién puede escribirlas
-- =====================================================================
SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT ok(
  (SELECT count(*) FROM crm.plantillas) >= 3,
  'Un asesor SÍ ve las plantillas: son su herramienta'
);

-- Una plantilla mal escrita sale a cientos de clientes de golpe, y eso no
-- se deshace. Por eso escribirlas es de admin.
SELECT throws_ok(
  $$INSERT INTO crm.plantillas (inmobiliaria_id, nombre, cuerpo)
    VALUES ('11111111-1111-1111-1111-111111111111', 'De un asesor', 'Hola {{nombre}}')$$,
  '42501',
  NULL,
  'Pero NO puede crearlas: eso es de admin'
);

-- --- Aislamiento ------------------------------------------------------
RESET ROLE;
SET LOCAL "request.jwt.claims" = '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM crm.plantillas
    WHERE inmobiliaria_id = '11111111-1111-1111-1111-111111111111'),
  0,
  'Beta no ve ni una plantilla de Alfa'
);

SELECT is(
  (SELECT count(*)::int FROM crm.envios),
  0,
  'Y la tabla de envíos nace vacía: copiar no es enviar'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
