-- =====================================================================
-- El pipeline comercial.
--
-- Lo que se mide: que el embudo avance solo con hechos reales, que NUNCA
-- retroceda solo, que la visita presunta se presuma con criterio y se
-- distinga de la confirmada, que cerrar exija motivo, y que nada de esto
-- se filtre entre inmobiliarias.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(28);

DELETE FROM crm.contactos;   -- arrastra oportunidades y transiciones

-- =====================================================================
-- 1. El embudo avanza solo
-- =====================================================================
INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164)
VALUES ('ee000001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', 'Persona Embudo', '+573001110001');

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades
    WHERE contacto_id = 'ee000001-0000-0000-0000-000000000001'),
  0,
  'Existir no abre oportunidad: hace falta que pase algo'
);

INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, metadata)
VALUES ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
        'ee000001-0000-0000-0000-000000000001', 'Hola, busco apartamento',
        now() - interval '2 hours', '{"origen_tabla":"t","origen_id":"p1"}');

SELECT is(
  (SELECT etapa FROM crm.oportunidades
    WHERE contacto_id = 'ee000001-0000-0000-0000-000000000001'),
  'contactado',
  'El primer mensaje abre la oportunidad y la deja en Contactado'
);

SELECT is(
  (SELECT count(*)::int FROM crm.transiciones t
     JOIN crm.oportunidades o ON o.id = t.oportunidad_id
    WHERE o.contacto_id = 'ee000001-0000-0000-0000-000000000001'),
  2,
  'Y deja rastro: el nacimiento y el ascenso a Contactado'
);

-- --- Una visita agendada la sube -------------------------------------
INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, ocurrido_at, metadata)
VALUES ('11111111-1111-1111-1111-111111111111', 'visita_agendada', 'sistema',
        'ee000001-0000-0000-0000-000000000001', now() - interval '1 hour',
        '{"origen_tabla":"t","origen_id":"p2"}');

SELECT is(
  (SELECT etapa FROM crm.oportunidades
    WHERE contacto_id = 'ee000001-0000-0000-0000-000000000001'),
  'visita_agendada',
  'Agendar una visita sube el peldaño'
);

-- =====================================================================
-- 2. LA AFIRMACIÓN QUE MÁS IMPORTA: el avance solo va hacia adelante.
--    Sin esta regla, cualquiera que ya visitó y luego escribe un "gracias"
--    volvería a Contactado y el tablero dejaría de significar nada.
-- =====================================================================
INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, metadata)
VALUES ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
        'ee000001-0000-0000-0000-000000000001', 'Gracias!',
        now(), '{"origen_tabla":"t","origen_id":"p3"}');

SELECT is(
  (SELECT etapa FROM crm.oportunidades
    WHERE contacto_id = 'ee000001-0000-0000-0000-000000000001'),
  'visita_agendada',
  'Un mensaje posterior NO devuelve la oportunidad a Contactado'
);

-- =====================================================================
-- 3. La visita presunta
--
-- En cuatro meses de producción no se ha marcado ni una sola cita como
-- completada: 527 citas, 0 completadas. Sin presunción, el peldaño más
-- importante del embudo estaría permanentemente vacío.
-- =====================================================================

-- Cita CONFIRMADA cuya fecha ya pasó, sin cancelar → se presume.
INSERT INTO public.citas
  (id, inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono, estado, confirmada_at)
VALUES ('cc000001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'a3333333-3333-3333-3333-333333333333',
        'a1111111-1111-1111-1111-111111111111',
        current_date - 3, '09:00', '09:30',
        'Persona Presunta', '+573001110002', 'agendada', now() - interval '4 days');

SELECT is(
  (SELECT o.etapa FROM crm.oportunidades o
     JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573001110002'),
  'visita_realizada',
  'Confirmada, con fecha pasada y sin cancelar: se presume realizada'
);

SELECT is(
  (SELECT v.visita_realizada_origen FROM crm.v_oportunidades v
     JOIN crm.contactos c ON c.id = v.contacto_id
    WHERE c.telefono_e164 = '+573001110002'),
  'presunta',
  'Y queda marcada como PRESUNTA: un informe de conversión no puede mentir'
);

-- Cita SIN confirmar cuya fecha pasó → NO se presume. Si nadie confirmó,
-- lo más probable es que no ocurriera.
INSERT INTO public.citas
  (id, inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono, estado)
VALUES ('cc000002-0000-0000-0000-000000000002',
        '11111111-1111-1111-1111-111111111111',
        'a3333333-3333-3333-3333-333333333333',
        'a1111111-1111-1111-1111-111111111111',
        current_date - 3, '10:00', '10:30',
        'Persona Sin Confirmar', '+573001110003', 'agendada');

SELECT is(
  (SELECT o.etapa FROM crm.oportunidades o
     JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573001110003'),
  'visita_agendada',
  'Sin confirmar no se presume nada: se queda en Visita agendada'
);

-- Cita CANCELADA cuya fecha pasó → NO se presume, obviamente.
INSERT INTO public.citas
  (id, inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono, estado, confirmada_at)
VALUES ('cc000003-0000-0000-0000-000000000003',
        '11111111-1111-1111-1111-111111111111',
        'a3333333-3333-3333-3333-333333333333',
        'a1111111-1111-1111-1111-111111111111',
        current_date - 3, '11:00', '11:30',
        'Persona Cancelada', '+573001110004', 'cancelada', now() - interval '4 days');

SELECT isnt(
  (SELECT o.etapa FROM crm.oportunidades o
     JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573001110004'),
  'visita_realizada',
  'Una cita cancelada no se presume realizada por mucho que la fecha pasara'
);

-- Cita COMPLETADA de verdad → confirmada, no presunta.
INSERT INTO public.citas
  (id, inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono, estado, completada_at)
VALUES ('cc000004-0000-0000-0000-000000000004',
        '11111111-1111-1111-1111-111111111111',
        'a3333333-3333-3333-3333-333333333333',
        'a1111111-1111-1111-1111-111111111111',
        current_date - 3, '12:00', '12:30',
        'Persona Real', '+573001110005', 'completada', now() - interval '3 days');

SELECT is(
  (SELECT v.visita_realizada_origen FROM crm.v_oportunidades v
     JOIN crm.contactos c ON c.id = v.contacto_id
    WHERE c.telefono_e164 = '+573001110005'),
  'confirmada',
  'Cuando alguien SÍ marcó la cita, el origen es confirmada, no presunta'
);

-- =====================================================================
-- 4. Una sola oportunidad abierta por persona
-- =====================================================================
SELECT throws_ok(
  $$INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id)
    VALUES ('11111111-1111-1111-1111-111111111111',
            'ee000001-0000-0000-0000-000000000001')$$,
  '23505',
  NULL,
  'No se puede abrir una segunda oportunidad viva para la misma persona'
);

-- =====================================================================
-- 5. Cerrar, desde la piel de un usuario real
-- =====================================================================
SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  format($$SELECT crm.cerrar_oportunidad(%L, 'perdida')$$,
         (SELECT id FROM crm.oportunidades
           WHERE contacto_id = 'ee000001-0000-0000-0000-000000000001')),
  NULL, NULL,
  'Perder sin motivo falla: perder sin motivo es perder el dato'
);

-- Mover a mano hacia ATRÁS sí se permite: corregir un error del sistema
-- es exactamente para lo que existe, y por eso hay historial.
SELECT lives_ok(
  format($$SELECT crm.mover_etapa(%L, 'calificado', 'me equivoqué de ficha')$$,
         (SELECT id FROM crm.oportunidades
           WHERE contacto_id = 'ee000001-0000-0000-0000-000000000001')),
  'Una persona sí puede mover la tarjeta hacia atrás'
);

SELECT is(
  (SELECT t.origen FROM crm.transiciones t
     JOIN crm.oportunidades o ON o.id = t.oportunidad_id
    WHERE o.contacto_id = 'ee000001-0000-0000-0000-000000000001'
    ORDER BY t.id DESC LIMIT 1),
  'humano',
  'Y queda registrado que lo movió una persona, no el sistema'
);

SELECT lives_ok(
  format($$SELECT crm.cerrar_oportunidad(%L, 'perdida', 'precio')$$,
         (SELECT id FROM crm.oportunidades
           WHERE contacto_id = 'ee000001-0000-0000-0000-000000000001'
             AND estado = 'abierta')),
  'Con motivo, cerrar como perdida funciona'
);

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades
    WHERE contacto_id = 'ee000001-0000-0000-0000-000000000001'
      AND estado = 'abierta'),
  0,
  'Tras cerrarla no queda ninguna abierta'
);

-- La historia no se corrige: no hay política de UPDATE ni de DELETE.
--
-- Y NO da error, que es lo que hay que entender: cuando una tabla tiene
-- RLS y ninguna política de UPDATE, Postgres no rechaza la sentencia
-- —simplemente no ve ni una fila que tocar—. El intento se va en
-- silencio con cero filas afectadas, así que lo que hay que afirmar no
-- es "lanza excepción" sino "no cambió nada".
UPDATE crm.transiciones SET motivo = 'historia reescrita';

SELECT is(
  (SELECT count(*)::int FROM crm.transiciones WHERE motivo = 'historia reescrita'),
  0,
  'Nadie puede reescribir la historia del embudo: el UPDATE no toca ni una fila'
);

RESET ROLE;

-- Cerrada una, la siguiente actividad abre otra: quien vuelve en marzo no
-- contamina las cifras de septiembre.
INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, metadata)
VALUES ('11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
        'ee000001-0000-0000-0000-000000000001', 'Volví',
        now(), '{"origen_tabla":"t","origen_id":"p9"}');

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades
    WHERE contacto_id = 'ee000001-0000-0000-0000-000000000001'),
  2,
  'Una persona que vuelve abre una oportunidad NUEVA, no revive la cerrada'
);

-- =====================================================================
-- 6. Aislamiento
-- =====================================================================
SET LOCAL "request.jwt.claims" = '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades),
  0,
  'Beta no ve ni una de las oportunidades de Alfa'
);

SELECT is(
  (SELECT count(*)::int FROM crm.transiciones),
  0,
  'Ni su historial'
);

SELECT throws_ok(
  format($$SELECT crm.mover_etapa(%L, 'en_estudio')$$,
         (SELECT id FROM crm.oportunidades WHERE true LIMIT 1)),
  NULL, NULL,
  'Y no puede mover lo que no ve'
);

RESET ROLE;

-- =====================================================================
-- 6-bis. El escalamiento
--
-- Se sincroniza de una sola pasada, FUERA del trigger: por contacto
-- cuesta 614 ms medidos en producción, porque hay que escanear entera
-- una tabla del otro repo que no tiene índice por conversacion_id.
-- Esta prueba recorre el puente completo: uso → conversación →
-- mensaje → actividad proyectada → contacto.
-- =====================================================================
-- El puente NO se finge: lo construye la proyección real. El contacto
-- NO se crea a mano a propósito — crm.resolver_contacto() empareja por
-- crm.identidades, no por contactos.telefono_e164, así que un contacto
-- insertado a pelo no se reconocería y saldrían dos.
INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono)
VALUES ('ff000001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', '+573001110009');

-- Este INSERT dispara la proyección, que crea la actividad con el
-- metadata del puente, y esa actividad dispara el trigger del pipeline.
INSERT INTO public.agente_comercial_mensajes (id, conversacion_id, rol, contenido)
VALUES ('ff000002-0000-0000-0000-000000000002',
        'ff000001-0000-0000-0000-000000000001', 'usuario', 'Necesito hablar con alguien');

SELECT is(
  (SELECT o.etapa FROM crm.oportunidades o
     JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573001110009'),
  'contactado',
  'Un mensaje de WhatsApp real recorre proyección y pipeline de una pieza'
);

SELECT is(
  (SELECT o.escalado_at FROM crm.oportunidades o
     JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573001110009'),
  NULL,
  'El trigger NO calcula el escalamiento: sería medio segundo por mensaje'
);

INSERT INTO public.agente_comercial_uso
  (inmobiliaria_id, conversacion_id, modelo, etapa, escalado, created_at)
VALUES ('11111111-1111-1111-1111-111111111111',
        'ff000001-0000-0000-0000-000000000001', 'claude-opus-5', 'CONSULTA', true,
        now() - interval '25 minutes');

SELECT ok(
  crm.sincronizar_escalamientos() >= 1,
  'La pasada conjunta sí lo encuentra'
);

SELECT ok(
  (SELECT o.escalado_at FROM crm.oportunidades o
     JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573001110009')
    BETWEEN now() - interval '26 minutes' AND now() - interval '24 minutes',
  'Y guarda CUÁNDO pidió un humano, que es lo que hace accionable la alerta'
);

-- =====================================================================
-- 7. Permisos de las funciones de mantenimiento
-- =====================================================================
SELECT ok(
  NOT has_function_privilege('authenticated', 'crm.recalcular_pipeline()', 'EXECUTE'),
  'Un asesor no puede recalcular el pipeline de toda la inmobiliaria'
);

SELECT ok(
  has_function_privilege('authenticated', 'crm.mover_etapa(uuid, text, text)', 'EXECUTE'),
  'Pero sí puede mover una tarjeta'
);

SELECT ok(
  NOT has_schema_privilege('anon', 'crm', 'USAGE'),
  'Y un anónimo sigue sin poder ni nombrar el esquema'
);

SELECT * FROM finish();
ROLLBACK;
