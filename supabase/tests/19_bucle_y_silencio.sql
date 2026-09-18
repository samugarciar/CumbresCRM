-- =====================================================================
-- El bucle de las nueve, y las citas que se perdían calladas.
--
-- Las dos correcciones urgentes de la auditoría del 18 sep 2026.
--
-- El bucle: `cerrar_fantasmas` (0 9 * * *) y `recalcular_pipeline` (*/5)
-- caían en el mismo minuto. La pasada encontraba cerrada la oportunidad
-- que el cierre acababa de cerrar y abría otra en el acto — un contacto
-- llegó a acumular cinco, una por día, cerradas y reabiertas a las 09:00
-- exactas. Lo que se fija aquí es la regla que lo hace imposible:
-- **una pasada de mantenimiento no abre nada**.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(10);

DELETE FROM crm.contactos;

-- El lead entra por el camino real: un mensaje proyectado desde public.
INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono)
VALUES ('dd000001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', '+573001118881');

INSERT INTO public.agente_comercial_mensajes (id, conversacion_id, rol, contenido)
VALUES ('dd000002-0000-0000-0000-000000000002',
        'dd000001-0000-0000-0000-000000000001', 'usuario', 'Hola, busco apartamento');

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades o
     JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573001118881' AND o.estado = 'abierta'),
  1,
  'Un mensaje real abre una oportunidad: eso es lo que NO hay que romper'
);

-- Se cierra como lo haría el cierre por silencio.
UPDATE crm.oportunidades o
   SET estado = 'perdida', motivo_perdida = 'no_responde',
       cerrada_at = now(), cerrada_por = NULL
  FROM crm.contactos c
 WHERE c.id = o.contacto_id AND c.telefono_e164 = '+573001118881';

-- --- La regla que mata el bucle --------------------------------------
SELECT ok(
  NOT crm.recalcular_oportunidad(
        (SELECT id FROM crm.contactos WHERE telefono_e164 = '+573001118881'),
        false),
  'La pasada de mantenimiento NO abre una oportunidad donde no la hay'
);

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades o
     JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573001118881' AND o.estado = 'abierta'),
  0,
  'Y el contacto se queda cerrado, que es lo que el cierre decidió'
);

SELECT lives_ok(
  $$SELECT crm.recalcular_pipeline()$$,
  'La pasada completa corre sin abrir nada'
);

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades o
     JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573001118881'),
  1,
  'Tras la pasada sigue habiendo UNA oportunidad, no dos: aquí se reproducía el bucle'
);

-- --- Pero un hecho NUEVO sí la reabre --------------------------------
-- Abrir es responder a algo que pasó de verdad. Si esto dejara de
-- funcionar, el arreglo habría roto el producto para tapar el bug.
INSERT INTO public.agente_comercial_mensajes (id, conversacion_id, rol, contenido)
VALUES ('dd000003-0000-0000-0000-000000000003',
        'dd000001-0000-0000-0000-000000000001', 'usuario', 'Sigo interesada');

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades o
     JOIN crm.contactos c ON c.id = o.contacto_id
    WHERE c.telefono_e164 = '+573001118881' AND o.estado = 'abierta'),
  1,
  'Un mensaje nuevo del cliente SÍ vuelve a abrir: el cliente volvió de verdad'
);

-- --- Los dos crones dejan de compartir minuto ------------------------
SELECT is(
  (SELECT schedule FROM cron.job WHERE jobname = 'crm_cerrar_fantasmas'),
  '7 9 * * *',
  'Y como segunda línea, el cierre ya no cae en el minuto de la pasada'
);

-- =====================================================================
-- Una cita que no se puede resolver deja rastro
-- =====================================================================
-- El teléfono es literal de producción: una de las cinco citas perdidas
-- traía guardado el texto del propio prompt del bot como número.
INSERT INTO public.citas
  (id, inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono, estado)
VALUES ('dd000010-0000-0000-0000-000000000010',
        '11111111-1111-1111-1111-111111111111',
        'a3333333-3333-3333-3333-333333333333',
        'a1111111-1111-1111-1111-111111111111',
        current_date + 3, '10:00', '11:00',
        'Sin teléfono', 'NO lo tenemos — pídeselo al cliente', 'agendada');

SELECT is(
  (SELECT count(*)::int FROM crm.actividades
    WHERE cita_id = 'dd000010-0000-0000-0000-000000000010'),
  0,
  'Una cita sin identidad utilizable no se puede proyectar — eso no cambia'
);

SELECT is(
  (SELECT estado FROM crm.eventos
    WHERE tabla_origen = 'citas'
      AND fila_origen_id = 'dd000010-0000-0000-0000-000000000010'),
  'fallido',
  'Pero AHORA deja un fallo registrado: antes salía con RETURN NULL y crm.eventos marcaba cero'
);

SELECT ok(
  (SELECT payload->>'cliente_telefono' FROM crm.eventos
    WHERE fila_origen_id = 'dd000010-0000-0000-0000-000000000010')
    LIKE '%pídeselo al cliente%',
  'Y guarda lo que llegó, que es lo que permite arreglarlo en el origen'
);

SELECT * FROM finish();
ROLLBACK;
