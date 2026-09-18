-- =====================================================================
-- De quién es un lead, y a quién se le puede escribir primero.
--
-- Lo que se mide: que el dueño se RECLAME con un acto deliberado y que
-- nadie se lo quite en silencio; que «Mi día» esconda lo de otros pero
-- nunca lo huérfano —que hoy es el 100%—; y que ningún lote de marketing
-- pueda saltarse el opt_out.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(16);

DELETE FROM crm.contactos;

-- El lead se crea por el camino real: un mensaje de WhatsApp proyectado.
-- crm.resolver_contacto() empareja por crm.identidades, así que un
-- contacto insertado a pelo saldría duplicado y sin oportunidad.
INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono)
VALUES ('cc000001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', '+573001119991'),
       ('cc000003-0000-0000-0000-000000000003',
        '11111111-1111-1111-1111-111111111111', '+573001119992');

INSERT INTO public.agente_comercial_mensajes (id, conversacion_id, rol, contenido, created_at)
VALUES ('cc000002-0000-0000-0000-000000000002',
        'cc000001-0000-0000-0000-000000000001', 'usuario', 'Busco apartamento',
        now() - interval '40 days'),
       ('cc000004-0000-0000-0000-000000000004',
        'cc000003-0000-0000-0000-000000000003', 'usuario', 'Hola',
        now() - interval '5 days');

-- =====================================================================
-- El dueño se reclama, no se reparte
-- =====================================================================
SELECT is(
  (SELECT o.asesor_id FROM crm.oportunidades o
     JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573001119991'),
  NULL,
  'Un lead que entra por WhatsApp no tiene dueño: nadie ha hecho nada por él todavía'
);

SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, creado_por)
SELECT '11111111-1111-1111-1111-111111111111', 'nota', 'humano', c.id,
       'La llamé, quiere ver el sábado', 'cccccccc-cccc-cccc-cccc-cccccccccccc'
  FROM crm.contactos c WHERE c.telefono_e164 = '+573001119991';

RESET ROLE;

SELECT is(
  (SELECT o.asesor_id FROM crm.oportunidades o
     JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573001119991'),
  'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid,
  'Dejar una nota lo reclama: sentarse a escribir qué pasó es el acto deliberado por excelencia'
);

-- Que otro conteste en la ficha de un compañero es normal en este
-- negocio. Que eso le transfiera la responsabilidad en silencio no.
INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, creado_por)
SELECT '11111111-1111-1111-1111-111111111111', 'nota', 'humano', c.id,
       'Yo también hablé con ella', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  FROM crm.contactos c WHERE c.telefono_e164 = '+573001119991';

SELECT is(
  (SELECT o.asesor_id FROM crm.oportunidades o
     JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573001119991'),
  'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid,
  'Y otro asesor que anota NO se lo quita: reclamar solo actúa sobre lo que no tiene dueño'
);

-- El bot deja creado_por en NULL, así que no puede quedarse un lead.
INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo)
SELECT '11111111-1111-1111-1111-111111111111', 'sistema', 'agente_ia', c.id,
       'El bot hizo algo'
  FROM crm.contactos c WHERE c.telefono_e164 = '+573001119992';

SELECT is(
  (SELECT o.asesor_id FROM crm.oportunidades o
     JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573001119992'),
  NULL,
  'El bot no reclama nada: sin persona detrás no hay responsable'
);

-- --- Asignar a mano, incluso quitándoselo a otro ----------------------
SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT ok(
  crm.asignar_lead(
    (SELECT id FROM crm.contactos WHERE telefono_e164 = '+573001119991'),
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'A mano sí se puede cambiar de responsable'
);

SELECT ok(
  (SELECT count(*) FROM crm.actividades a
     JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE c.telefono_e164 = '+573001119991'
      AND a.tipo = 'sistema' AND a.cuerpo LIKE 'Ahora es responsabilidad%') = 1,
  'Y queda escrito en el historial: cambiar de responsable sin que conste no se explica después'
);

SELECT is(
  (SELECT r.nombre FROM crm.responsable_de(
     (SELECT id FROM crm.contactos WHERE telefono_e164 = '+573001119991')) r),
  (SELECT nombre_completo FROM public.usuarios WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'Y la ficha puede decir quién lo lleva, por nombre'
);

-- =====================================================================
-- «Mi día»: lo mío y lo de nadie, nunca lo de otro
-- =====================================================================
-- Se le pone una tarea vencida a cada uno para que tengan algo que ver.
INSERT INTO crm.tareas (inmobiliaria_id, contacto_id, titulo, vence_at, creado_por)
SELECT '11111111-1111-1111-1111-111111111111', c.id,
       'Llamar', now() - interval '2 days', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  FROM crm.contactos c WHERE c.telefono_e164 = '+573001119991';

INSERT INTO crm.tareas (inmobiliaria_id, contacto_id, titulo, vence_at, creado_por)
SELECT '11111111-1111-1111-1111-111111111111', c.id,
       'Revisar el huérfano', now() - interval '2 days', NULL
  FROM crm.contactos c WHERE c.telefono_e164 = '+573001119992';

SELECT ok(
  (SELECT count(*) FROM crm.mi_dia(200, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE telefono_e164 = '+573001119991') > 0,
  'El dueño ve lo suyo'
);

SELECT is(
  (SELECT count(*)::int FROM crm.mi_dia(200, 'cccccccc-cccc-cccc-cccc-cccccccccccc')
    WHERE telefono_e164 = '+573001119991'),
  0,
  'Y el otro asesor NO lo ve: eso es lo único que hacía falta para que dos no le escriban a la misma persona'
);

SELECT ok(
  (SELECT count(*) FROM crm.mi_dia(200, 'cccccccc-cccc-cccc-cccc-cccccccccccc')
    WHERE telefono_e164 = '+573001119992') > 0,
  'Pero lo huérfano lo siguen viendo los dos: hoy es el 100% del tablero, y filtrarlo dejaría el día vacío'
);

SELECT ok(
  (SELECT count(*) FROM crm.mi_dia(200)
    WHERE telefono_e164 = '+573001119991') > 0,
  'Sin asesor, «Mi día» sigue enseñándolo todo: la firma vieja no cambia de significado'
);

RESET ROLE;

-- =====================================================================
-- Consentimiento y opt-out
-- =====================================================================
SELECT ok(
  (SELECT consentimiento FROM crm.contactos WHERE telefono_e164 = '+573001119991'),
  'Quien nos escribió queda como consentido: es la interpretación que Samuel firmó'
);

SELECT ok(
  (SELECT consentimiento_at FROM crm.contactos WHERE telefono_e164 = '+573001119991')
    < now() - interval '39 days',
  'Y con la fecha de SU primer mensaje, no la de hoy: 1.043 personas consintiendo el mismo segundo no se defiende'
);

INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164)
VALUES ('cc000010-0000-0000-0000-000000000010',
        '11111111-1111-1111-1111-111111111111', 'Nunca escribió', '+573001119993');

SELECT ok(
  NOT (SELECT consentimiento FROM crm.contactos
        WHERE id = 'cc000010-0000-0000-0000-000000000010'),
  'Quien nunca escribió no consintió nada: el backfill no reparte, deduce de un hecho'
);

-- --- El opt-out gana siempre -----------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT ok(
  crm.marcar_opt_out(
    (SELECT id FROM crm.contactos WHERE telefono_e164 = '+573001119991'),
    'Lo pidió por WhatsApp'),
  'Se puede registrar que alguien pidió no recibir más'
);

SELECT is(
  (SELECT count(*)::int FROM crm.publico_marketing(14, 500)
    WHERE telefono_e164 = '+573001119991'),
  0,
  'Y desaparece del lote aunque siga consintiendo: el opt-out es más fuerte'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
