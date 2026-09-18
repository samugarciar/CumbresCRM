-- =====================================================================
-- Escribirle a alguien: la regla de las 24 horas.
--
-- Lo que se mide es UNA cosa, y es la que no puede fallar: que no se
-- pueda mandar texto libre fuera de la ventana de WhatsApp. El botón
-- apagado de la interfaz es la mitad visible; esta es la otra, la que un
-- formulario no puede saltarse.
--
-- Por qué importa tanto: fuera de la ventana Meta devuelve 131047, el
-- mensaje NO se entrega y nadie avisa. El cliente no recibe nada mientras
-- el asesor cree que sí.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(11);

DELETE FROM crm.contactos;
DELETE FROM crm.envios;

INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164)
VALUES ('fa000001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', 'Escribió hace poco', '+573001131111'),
       ('fa000002-0000-0000-0000-000000000002',
        '11111111-1111-1111-1111-111111111111', 'Escribió hace un mes', '+573001131112'),
       ('fa000003-0000-0000-0000-000000000003',
        '11111111-1111-1111-1111-111111111111', 'Nunca escribió', '+573001131113');

INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
        'fa000001-0000-0000-0000-000000000001', 'Hola', now() - interval '2 hours'),
       ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
        'fa000002-0000-0000-0000-000000000002', 'Hola', now() - interval '30 days');

-- --- Quién tiene la ventana abierta ----------------------------------
SELECT ok(
  crm.puede_escribir_libre('fa000001-0000-0000-0000-000000000001'),
  'Escribió hace 2 horas: la ventana está abierta'
);

SELECT ok(
  NOT crm.puede_escribir_libre('fa000002-0000-0000-0000-000000000002'),
  'Escribió hace un mes: cerrada'
);

SELECT ok(
  NOT crm.puede_escribir_libre('fa000003-0000-0000-0000-000000000003'),
  'Y quien nunca escribió no tiene ventana que abrir: sin su mensaje no hay nada que reabrir'
);

-- --- La regla, donde no se puede saltar ------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$SELECT crm.encolar_envio('fa000001-0000-0000-0000-000000000001',
                             'Claro, te mando el link ahora mismo')$$,
  'Dentro de la ventana, el texto libre pasa'
);

SELECT is(
  (SELECT estado FROM crm.envios
    WHERE contacto_id = 'fa000001-0000-0000-0000-000000000001'),
  'pendiente',
  'Y queda PENDIENTE, que es lo que es: aceptado por el CRM, todavía no entregado a Meta'
);

SELECT is(
  (SELECT enviado_por FROM crm.envios
    WHERE contacto_id = 'fa000001-0000-0000-0000-000000000001'),
  'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid,
  'Con quién lo escribió: un mensaje que no sabe de quién es no sirve de memoria'
);

-- LA PRUEBA QUE JUSTIFICA TODO EL FICHERO
SELECT throws_ok(
  $$SELECT crm.encolar_envio('fa000002-0000-0000-0000-000000000002',
                             'Hola, ¿sigues buscando?')$$,
  '23514',
  NULL,
  'FUERA de la ventana, el texto libre REVIENTA: es lo que un botón apagado no puede garantizar'
);

SELECT throws_ok(
  $$SELECT crm.encolar_envio('fa000003-0000-0000-0000-000000000003', 'Hola')$$,
  '23514',
  NULL,
  'Tampoco a quien nunca escribió'
);

SELECT throws_ok(
  $$SELECT crm.encolar_envio('fa000001-0000-0000-0000-000000000001', '   ')$$,
  NULL, NULL,
  'Ni un mensaje vacío, aunque la ventana esté abierta'
);

-- --- La plantilla aprobada sí sale fuera de la ventana ---------------
RESET ROLE;

INSERT INTO crm.plantillas
  (id, inmobiliaria_id, nombre, cuerpo, categoria, estado_meta, nombre_meta)
VALUES ('fa000010-0000-0000-0000-000000000010',
        '11111111-1111-1111-1111-111111111111',
        'Reactivación', 'Hola {{nombre}}, ¿sigues buscando?',
        'marketing', 'aprobada', 'reactivacion_v1');

INSERT INTO crm.plantillas
  (id, inmobiliaria_id, nombre, cuerpo, categoria, estado_meta)
VALUES ('fa000011-0000-0000-0000-000000000011',
        '11111111-1111-1111-1111-111111111111',
        'Sin aprobar todavía', 'Hola {{nombre}}', 'marketing', 'borrador');

SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$SELECT crm.encolar_envio('fa000002-0000-0000-0000-000000000002',
        'Hola María, ¿sigues buscando?', 'fa000010-0000-0000-0000-000000000010')$$,
  'Con una plantilla APROBADA sí se le puede escribir fuera de la ventana'
);

SELECT throws_ok(
  $$SELECT crm.encolar_envio('fa000002-0000-0000-0000-000000000002',
        'Hola María', 'fa000011-0000-0000-0000-000000000011')$$,
  '23514',
  NULL,
  'Pero una en BORRADOR no vale: es texto libre con otro nombre'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
