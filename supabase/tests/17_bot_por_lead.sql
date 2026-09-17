-- =====================================================================
-- El bot, apagable por lead.
--
-- Lo que se mide: que un desconocido SIEMPRE tenga respuesta, que el
-- asesor pueda callar al bot sin ser admin, que callarlo deje rastro, y
-- sobre todo —lo que más puede doler— que el apagado automático al
-- escalar NO se aplique hacia atrás: en producción hay 1.275
-- escalamientos históricos y callar al bot en todos de golpe sería un
-- incidente con clientes reales.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(27);

DELETE FROM crm.contactos;

INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164)
VALUES ('b0700001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'Sara Gómez', '+573001112221');

-- --- Lo que pasa por defecto -----------------------------------------
SELECT ok(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573009998887'),
  'A un teléfono DESCONOCIDO el bot le responde: cuando alguien escribe por primera vez su fila todavía no existe'
);

SELECT ok(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573001112221'),
  'Y a uno conocido también: el bot es opt-out'
);

-- --- El asesor lo apaga a mano ---------------------------------------
-- Con el asesor, no con el admin: el que toma la conversación es quien
-- la atiende, y exigir un admin para callar al bot lo haría inservible.
SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT ok(
  crm.cambiar_bot('b0700001-0000-0000-0000-000000000001', false),
  'Un asesor —no admin— puede callar al bot en su lead'
);

SELECT ok(
  NOT crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573001112221'),
  'Y el bot deja de responderle'
);

SELECT is(
  (SELECT bot_cambiado_por FROM crm.contactos
    WHERE id = 'b0700001-0000-0000-0000-000000000001'),
  'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid,
  'Queda escrito QUIÉN lo apagó: un bot callado que no sabe por quién no sirve de memoria'
);

SELECT is(
  (SELECT count(*)::int FROM crm.actividades
    WHERE contacto_id = 'b0700001-0000-0000-0000-000000000001'
      AND tipo = 'sistema'),
  1,
  'Y deja rastro en el historial, donde el asesor mira'
);

SELECT ok(
  crm.cambiar_bot('b0700001-0000-0000-0000-000000000001', false),
  'Pulsarlo dos veces no falla'
);

SELECT is(
  (SELECT count(*)::int FROM crm.actividades
    WHERE contacto_id = 'b0700001-0000-0000-0000-000000000001'
      AND tipo = 'sistema'),
  1,
  'Pero tampoco ensucia el historial con lo mismo otra vez'
);

SELECT ok(
  crm.cambiar_bot('b0700001-0000-0000-0000-000000000001', true),
  'Y se puede volver a encender'
);

-- En sentencia aparte a propósito: bot_puede_responder es STABLE y
-- dentro de la misma sentencia vería la instantánea de antes del cambio.
SELECT ok(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573001112221'),
  'Y el bot vuelve a responderle'
);

RESET ROLE;

-- --- La garantía va en la base, no en el formulario -------------------
SELECT throws_ok(
  $$UPDATE crm.contactos SET bot_activo = false
     WHERE id = 'b0700001-0000-0000-0000-000000000001'$$,
  '23514',
  NULL,
  'Apagar el bot sin motivo no se puede: un bot mudo sin razón es un bug esperando'
);

-- --- Aislamiento entre inquilinos ------------------------------------
-- El mismo teléfono en dos inmobiliarias es posible: el índice único es
-- (inmobiliaria_id, telefono_e164). Por eso la función pregunta por
-- inquilino, y esto es lo que lo demuestra.
INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164,
                           bot_activo, bot_motivo, bot_cambiado_at)
VALUES ('b0700002-0000-0000-0000-000000000002',
        '22222222-2222-2222-2222-222222222222',
        'Mismo número, otra inmobiliaria', '+573001112221',
        false, 'manual', now());

SELECT ok(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573001112221'),
  'Que Beta calle su bot no calla el de Alfa, aunque sea el mismo número'
);

SET LOCAL "request.jwt.claims" = '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT ok(
  NOT crm.cambiar_bot('b0700001-0000-0000-0000-000000000001', false),
  'Beta no puede tocar el interruptor de un lead de Alfa'
);

RESET ROLE;

SELECT ok(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573001112221'),
  'Y el de Alfa sigue encendido tras el intento'
);

-- =====================================================================
-- El apagado automático al escalar
--
-- El puente no se finge: lo construye la proyección real, igual que en
-- la prueba 11. crm.resolver_contacto() empareja por crm.identidades,
-- así que un contacto insertado a pelo saldría duplicado.
-- =====================================================================
INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono)
VALUES ('bb000001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', '+573001113331'),
       ('bb000003-0000-0000-0000-000000000003',
        '11111111-1111-1111-1111-111111111111', '+573001114441');

INSERT INTO public.agente_comercial_mensajes (id, conversacion_id, rol, contenido)
VALUES ('bb000002-0000-0000-0000-000000000002',
        'bb000001-0000-0000-0000-000000000001', 'usuario', 'Quiero hablar con alguien'),
       ('bb000004-0000-0000-0000-000000000004',
        'bb000003-0000-0000-0000-000000000003', 'usuario', 'Hola, pregunté hace meses');

-- Uno escala AHORA. El otro escaló hace una semana: es el caso que
-- representa a los 264 contactos con escalamientos viejos.
INSERT INTO public.agente_comercial_uso
  (inmobiliaria_id, conversacion_id, modelo, etapa, escalado, created_at)
VALUES ('11111111-1111-1111-1111-111111111111',
        'bb000001-0000-0000-0000-000000000001', 'claude-opus-5', 'CONSULTA', true,
        now() - interval '10 minutes'),
       ('11111111-1111-1111-1111-111111111111',
        'bb000003-0000-0000-0000-000000000003', 'claude-opus-5', 'CONSULTA', true,
        now() - interval '7 days');

SELECT ok(crm.sincronizar_escalamientos() >= 2, 'La pasada encuentra los dos escalamientos');

SELECT ok(
  NOT crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573001113331'),
  'Escalar AHORA calla al bot: pedir hablar con una persona es exactamente eso'
);

SELECT is(
  (SELECT bot_cambiado_por FROM crm.contactos WHERE telefono_e164 = '+573001113331'),
  NULL,
  'Sin persona detrás: NULL marca que lo hizo el sistema, como en cerrada_por'
);

SELECT is(
  (SELECT a.origen FROM crm.actividades a
     JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE c.telefono_e164 = '+573001113331' AND a.tipo = 'sistema'),
  'sistema',
  'Y el rastro dice que fue el sistema, no un humano'
);

-- La prueba que justifica toda la cautela de la función.
SELECT ok(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573001114441'),
  'Un escalamiento de HACE UNA SEMANA no calla nada: apagar el bot hacia atrás sería un incidente, no una función'
);


-- =====================================================================
-- La caducidad del silencio
--
-- Regla aprobada: el silencio MANUAL no caduca nunca; el AUTOMÁTICO
-- caduca a los 3 días si nadie del equipo hizo nada. Y "hacer algo" son
-- actos deliberados: abrir la ficha NO cuenta, porque se marca sola al
-- entrar y significa "le eché un ojo", no "lo atendí".
-- =====================================================================
INSERT INTO crm.contactos
  (id, inmobiliaria_id, nombre, telefono_e164,
   bot_activo, bot_motivo, bot_cambiado_at)
VALUES
  -- Silenciado a mano hace diez días. No debe volver jamás.
  ('b0700010-0000-0000-0000-000000000010',
   '11111111-1111-1111-1111-111111111111', 'Me encargo yo', '+573001115551',
   false, 'manual', now() - interval '10 days'),
  -- Escaló hace cinco días y nadie hizo nada. Debe volver.
  ('b0700011-0000-0000-0000-000000000011',
   '11111111-1111-1111-1111-111111111111', 'Nadie llegó', '+573001115552',
   false, 'escalamiento', now() - interval '5 days'),
  -- Escaló hace cinco días, pero alguien dejó una nota. No debe volver.
  ('b0700012-0000-0000-0000-000000000012',
   '11111111-1111-1111-1111-111111111111', 'Sí lo atendieron', '+573001115553',
   false, 'escalamiento', now() - interval '5 days'),
  -- Escaló hace cinco días y solo abrieron la ficha. Debe volver igual.
  ('b0700013-0000-0000-0000-000000000013',
   '11111111-1111-1111-1111-111111111111', 'Solo lo miraron', '+573001115554',
   false, 'escalamiento', now() - interval '5 days'),
  -- Escaló ayer. Todavía no le toca, pero ya tiene que avisar.
  ('b0700014-0000-0000-0000-000000000014',
   '11111111-1111-1111-1111-111111111111', 'Recién callado', '+573001115555',
   false, 'escalamiento', now() - interval '1 day');

INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, creado_por, ocurrido_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'nota', 'humano',
        'b0700012-0000-0000-0000-000000000012', 'Lo llamé, quedamos el viernes',
        'cccccccc-cccc-cccc-cccc-cccccccccccc', now() - interval '1 day');

INSERT INTO crm.lecturas (contacto_id, usuario_id, inmobiliaria_id, visto_hasta)
VALUES ('b0700013-0000-0000-0000-000000000013',
        'cccccccc-cccc-cccc-cccc-cccccccccccc',
        '11111111-1111-1111-1111-111111111111', now());

SELECT is(
  crm.reactivar_bots(3::smallint), 2,
  'Caducan exactamente dos: el abandonado y el que solo miraron'
);

SELECT ok(
  (SELECT NOT bot_activo FROM crm.contactos
    WHERE id = 'b0700010-0000-0000-0000-000000000010'),
  'El silencio MANUAL no caduca ni a los diez días: alguien dijo que se encargaba'
);

SELECT ok(
  (SELECT bot_activo FROM crm.contactos
    WHERE id = 'b0700011-0000-0000-0000-000000000011'),
  'El automático sí: escaló hace cinco días y nadie llegó'
);

SELECT ok(
  (SELECT NOT bot_activo FROM crm.contactos
    WHERE id = 'b0700012-0000-0000-0000-000000000012'),
  'Una nota SÍ cuenta como atender: ese sigue callado'
);

SELECT ok(
  (SELECT bot_activo FROM crm.contactos
    WHERE id = 'b0700013-0000-0000-0000-000000000013'),
  'Abrir la ficha NO cuenta: mirarlo no es atenderlo'
);

SELECT is(
  (SELECT count(*)::int FROM crm.actividades
    WHERE contacto_id = 'b0700011-0000-0000-0000-000000000011'
      AND tipo = 'sistema'),
  1,
  'Y que el bot recupere la voz queda escrito: nadie debería tener que adivinar por qué volvió'
);

-- --- Avisar desde el primer día --------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM crm.mi_dia(200)
    WHERE tipo = 'bot_callado'
      AND contacto_id = 'b0700014-0000-0000-0000-000000000014'),
  1,
  'El que lleva un día callado ya sale en «Mi día»: la reactivación es la red, no la sorpresa'
);

SELECT is(
  (SELECT count(*)::int FROM crm.mi_dia(200)
    WHERE tipo = 'bot_callado'
      AND contacto_id = 'b0700012-0000-0000-0000-000000000012'),
  0,
  'Pero el que ya atendieron no ocupa sitio en la lista'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
