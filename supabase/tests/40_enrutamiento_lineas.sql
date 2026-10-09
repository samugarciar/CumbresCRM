-- =====================================================================
-- Tarea 1: Enrutamiento por línea, captación sin línea propia,
-- casos a mano, tablero por embudo, aislamiento comercial
-- y deduplicación de historial.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(33);

-- Limpieza
DELETE FROM crm.lineas;
DELETE FROM crm.contactos;
DELETE FROM crm.eventos;

-- ---------------------------------------------------------------------
-- 1. Captación sin línea propia: usa la línea de administrativa
-- ---------------------------------------------------------------------
SELECT is(
  (SELECT usa_linea_de FROM crm.embudos WHERE codigo = 'captacion'),
  'administrativa',
  'Captación está modelada para usar la línea de WhatsApp de administrativa'
);

-- Configurar líneas de prueba
INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre) VALUES
  ('11111111-1111-1111-1111-111111111111', 'comercial',      '324000000000001', 'Línea Comercial 324'),
  ('11111111-1111-1111-1111-111111111111', 'administrativa', '320000000000001', 'Línea Administrativa 320');

-- Simular columna wa_phone_number_id y wa_message_id en public si no existen
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'agente_comercial_mensajes' AND column_name = 'wa_phone_number_id'
  ) THEN
    ALTER TABLE public.agente_comercial_mensajes ADD COLUMN wa_phone_number_id text;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'agente_comercial_mensajes' AND column_name = 'wa_message_id'
  ) THEN
    ALTER TABLE public.agente_comercial_mensajes ADD COLUMN wa_message_id text;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 2. Enrutamiento por línea: Mensaje entrante por el 320
-- ---------------------------------------------------------------------
INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono, cliente_nombre)
VALUES ('f4000001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '+573004001111', 'Inquilino Pérez');

INSERT INTO public.agente_comercial_mensajes
  (id, conversacion_id, rol, contenido, created_at, wa_phone_number_id, wa_message_id)
VALUES
  ('f4000010-0000-0000-0000-000000000010', 'f4000001-0000-0000-0000-000000000001',
   'usuario', 'Hola, necesito el paz y salvo de mi contrato', now() - interval '1 hour',
   '320000000000001', 'wamid.admin.1');

CREATE TEMP TABLE c_admin AS
  SELECT id FROM crm.contactos WHERE telefono_e164 = '+573004001111';

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades WHERE contacto_id = (SELECT id FROM c_admin) AND embudo = 'administrativa'),
  1,
  'Mensaje por el 320 abre un caso administrativo'
);

SELECT is(
  (SELECT etapa FROM crm.oportunidades WHERE contacto_id = (SELECT id FROM c_admin) AND embudo = 'administrativa'),
  'al_dia',
  'El caso administrativo nace en al_dia'
);

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades WHERE contacto_id = (SELECT id FROM c_admin) AND embudo = 'comercial'),
  0,
  'Mensaje por el 320 NUNCA abre una oportunidad comercial'
);

-- Segundo mensaje por el 320 no duplica el caso abierto
INSERT INTO public.agente_comercial_mensajes
  (id, conversacion_id, rol, contenido, created_at, wa_phone_number_id, wa_message_id)
VALUES
  ('f4000011-0000-0000-0000-000000000011', 'f4000001-0000-0000-0000-000000000001',
   'usuario', '¿Ya me lo enviaron?', now() - interval '30 minutes',
   '320000000000001', 'wamid.admin.2');

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades WHERE contacto_id = (SELECT id FROM c_admin) AND embudo = 'administrativa'),
  1,
  'Segundo mensaje no duplica el caso administrativo abierto'
);

-- ---------------------------------------------------------------------
-- 3. Enrutamiento por línea: Mensaje entrante por el 324 (comercial) o sin línea
-- ---------------------------------------------------------------------
INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono, cliente_nombre)
VALUES ('f4000002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', '+573004002222', 'Comprador Gomez');

INSERT INTO public.agente_comercial_mensajes
  (id, conversacion_id, rol, contenido, created_at, wa_phone_number_id, wa_message_id)
VALUES
  ('f4000020-0000-0000-0000-000000000020', 'f4000002-0000-0000-0000-000000000002',
   'usuario', 'Buenas, busco apartamento en Poblado', now() - interval '2 hours',
   '324000000000001', 'wamid.com.1');

CREATE TEMP TABLE c_comercial AS
  SELECT id FROM crm.contactos WHERE telefono_e164 = '+573004002222';

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades WHERE contacto_id = (SELECT id FROM c_comercial) AND embudo = 'comercial'),
  1,
  'Mensaje por el 324 abre una oportunidad comercial'
);

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades WHERE contacto_id = (SELECT id FROM c_comercial) AND embudo = 'administrativa'),
  0,
  'Mensaje por el 324 no abre caso administrativo'
);

-- ---------------------------------------------------------------------
-- 4. Número no configurado en crm.lineas
-- ---------------------------------------------------------------------
INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono, cliente_nombre)
VALUES ('f4000003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', '+573004003333', 'Desconocido');

INSERT INTO public.agente_comercial_mensajes
  (id, conversacion_id, rol, contenido, created_at, wa_phone_number_id, wa_message_id)
VALUES
  ('f4000030-0000-0000-0000-000000000030', 'f4000003-0000-0000-0000-000000000003',
   'usuario', 'Hola', now(), '999999999999999', 'wamid.err.1');

CREATE TEMP TABLE c_desconocido AS
  SELECT id FROM crm.contactos WHERE telefono_e164 = '+573004003333';

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades WHERE contacto_id = (SELECT id FROM c_desconocido)),
  0,
  'Número no configurado en crm.lineas no abre ninguna oportunidad'
);

SELECT is(
  (SELECT count(*)::int FROM crm.eventos WHERE tipo = 'linea_no_configurada' AND fila_origen_id = (
    SELECT id::text FROM crm.actividades WHERE contacto_id = (SELECT id FROM c_desconocido) LIMIT 1
  )),
  1,
  'Número no configurado deja rastro en crm.eventos como linea_no_configurada'
);

-- ---------------------------------------------------------------------
-- 5. Segunda red contra duplicados del historial
-- ---------------------------------------------------------------------
-- Mensaje previo (de Kommo/n8n) sin wamid en crm.actividades
INSERT INTO crm.actividades (
  inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, metadata
) VALUES (
  '11111111-1111-1111-1111-111111111111', 'mensaje_saliente', 'humano',
  (SELECT id FROM c_comercial), 'Hola, ¿cómo estás?', now() - interval '10 minutes',
  jsonb_build_object('origen', 'kommo_historico')
);

-- Llega por proyección un mensaje del asesor con wamid, mismo texto, a +30s
INSERT INTO public.agente_comercial_mensajes
  (id, conversacion_id, rol, contenido, created_at, wa_phone_number_id, wa_message_id)
VALUES
  ('f4000040-0000-0000-0000-000000000040', 'f4000002-0000-0000-0000-000000000002',
   'asesor', 'Hola, ¿cómo estás?', now() - interval '10 minutes' + interval '30 seconds',
   '324000000000001', 'wamid.dup.1');

SELECT is(
  (SELECT count(*)::int FROM crm.actividades WHERE cuerpo = 'Hola, ¿cómo estás?' AND contacto_id = (SELECT id FROM c_comercial)),
  1,
  'Mensaje con wamid coincidente dentro de 2 min no se duplica en crm.actividades'
);

SELECT is(
  (SELECT count(*)::int FROM crm.eventos WHERE tipo = 'duplicado_historial' AND fila_origen_id = 'f4000040-0000-0000-0000-000000000040'),
  1,
  'Deduplicación deja rastro en crm.eventos como duplicado_historial'
);

-- ---------------------------------------------------------------------
-- 6. Botón «Es una captación» (crm.convertir_a_captacion)
-- ---------------------------------------------------------------------
GRANT SELECT ON c_admin, c_comercial, c_desconocido TO authenticated;

SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

-- Contacto Pérez solo tiene caso administrativo
SELECT is(
  (SELECT tipo FROM crm.contactos WHERE id = (SELECT id FROM c_admin)),
  'cliente',
  'Antes de la conversión, el tipo del contacto es cliente'
);

SELECT ok(
  crm.convertir_a_captacion((SELECT id FROM c_admin)) IS NOT NULL,
  'crm.convertir_a_captacion ejecuta con éxito para caso administrativo abierto'
);

SELECT is(
  (SELECT estado FROM crm.oportunidades WHERE contacto_id = (SELECT id FROM c_admin) AND embudo = 'administrativa'),
  'perdida',
  'El caso administrativo quedó cerrado como perdida'
);

SELECT is(
  (SELECT motivo_perdida FROM crm.oportunidades WHERE contacto_id = (SELECT id FROM c_admin) AND embudo = 'administrativa'),
  'es_captacion',
  'El motivo de pérdida del caso administrativo es es_captacion'
);

SELECT is(
  (SELECT etapa FROM crm.oportunidades WHERE contacto_id = (SELECT id FROM c_admin) AND embudo = 'captacion' AND estado = 'abierta'),
  'prospecto',
  'Se abrió el prospecto de captación en la primera etapa (prospecto)'
);

SELECT is(
  (SELECT tipo FROM crm.contactos WHERE id = (SELECT id FROM c_admin)),
  'propietario',
  'Al no tener oportunidad comercial, el tipo de contacto pasó a propietario'
);

SELECT is(
  (SELECT count(*)::int FROM crm.actividades WHERE contacto_id = (SELECT id FROM c_admin) AND tipo = 'sistema'
    AND metadata ? 'caso_administrativo_cerrado_id'),
  1,
  'Se dejó rastro en el historial del contacto con el ID del caso administrativo cerrado'
);

-- Convertir cuando ya tenía comercial: pasa a 'ambos'
RESET ROLE;
-- Crear contacto con caso administrativo y oportunidad comercial
INSERT INTO public.agente_comercial_conversaciones (id, inmobiliaria_id, telefono, cliente_nombre)
VALUES ('f4000005-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', '+573004005555', 'Doble Rol');

INSERT INTO public.agente_comercial_mensajes
  (id, conversacion_id, rol, contenido, created_at, wa_phone_number_id, wa_message_id)
VALUES
  ('f4000050-0000-0000-0000-000000000050', 'f4000005-0000-0000-0000-000000000005',
   'usuario', 'Hola busco apto', now() - interval '3 hours', '324000000000001', 'wamid.doble.1'),
  ('f4000051-0000-0000-0000-000000000051', 'f4000005-0000-0000-0000-000000000005',
   'usuario', 'Y quiero arrendar mi casa', now() - interval '2 hours', '320000000000001', 'wamid.doble.2');

CREATE TEMP TABLE c_doble AS
  SELECT id FROM crm.contactos WHERE telefono_e164 = '+573004005555';
GRANT SELECT ON c_doble TO authenticated;

SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT ok(
  crm.convertir_a_captacion((SELECT id FROM c_doble)) IS NOT NULL,
  'Convierte contacto con comercial a captación'
);

SELECT is(
  (SELECT tipo FROM crm.contactos WHERE id = (SELECT id FROM c_doble)),
  'ambos',
  'Al tener oportunidad comercial, el tipo de contacto pasa a ambos'
);

-- Si no tiene caso administrativo abierto, debe fallar
SELECT throws_ok(
  $$SELECT crm.convertir_a_captacion((SELECT id FROM c_doble))$$,
  'P0001',
  'El contacto no tiene un caso administrativo abierto',
  'Reclasificar falla si no hay caso administrativo abierto'
);

-- ---------------------------------------------------------------------
-- 7. Abrir caso administrativo a mano
-- ---------------------------------------------------------------------
SELECT ok(
  crm.abrir_caso_administrativo((SELECT id FROM c_comercial)) IS NOT NULL,
  'Se puede abrir un caso administrativo manualmente para cualquier contacto'
);

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades WHERE contacto_id = (SELECT id FROM c_comercial) AND embudo = 'administrativa' AND estado = 'abierta'),
  1,
  'El caso administrativo quedó abierto'
);

SELECT is(
  (SELECT count(*)::int FROM crm.actividades WHERE contacto_id = (SELECT id FROM c_comercial) AND cuerpo = 'Caso administrativo abierto manualmente'),
  1,
  'Se dejó rastro de la apertura manual en actividades'
);

-- ---------------------------------------------------------------------
-- 8. Tablero por embudo
-- ---------------------------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM crm.tablero(p_embudo => 'comercial')),
  2,
  'Tablero comercial solo lista oportunidades del embudo comercial'
);

SELECT is(
  (SELECT count(*)::int FROM crm.tablero(p_embudo => 'administrativa')),
  1,
  'Tablero administrativo solo lista casos del embudo administrativo'
);

SELECT is(
  (SELECT count(*)::int FROM crm.tablero(p_embudo => 'captacion')),
  2,
  'Tablero de captación solo lista prospectos del embudo captación'
);

-- ---------------------------------------------------------------------
-- 9. Aislamiento de lo comercial (crm.mi_dia, publico_marketing, inmuebles_para, cerrar_fantasmas)
-- ---------------------------------------------------------------------
-- El contacto Pérez (c_admin) solo tiene captación (no comercial).
SELECT is(
  (SELECT count(*)::int FROM crm.mi_dia() WHERE contacto_id = (SELECT id FROM c_admin)),
  0,
  'Un contacto sin oportunidad comercial nunca entra a Mi Día'
);

SELECT is(
  (SELECT count(*)::int FROM crm.publico_marketing(0, 100) WHERE contacto_id = (SELECT id FROM c_admin)),
  0,
  'Un contacto propietario/captación nunca entra a publico_marketing ni reactivables'
);

SELECT is(
  (SELECT count(*)::int FROM crm.inmuebles_para((SELECT id FROM c_admin))),
  0,
  'A un contacto sin oportunidad comercial nunca se le ofrecen inmuebles_para'
);

RESET ROLE;

SELECT ok(
  crm.cerrar_fantasmas(0) >= 0,
  'crm.cerrar_fantasmas ejecuta sin error'
);

SELECT is(
  (SELECT count(*)::int FROM crm.oportunidades WHERE embudo != 'comercial' AND estado = 'cerrada_fantasma'),
  0,
  'crm.cerrar_fantasmas nunca cierra casos administrativos ni de captación'
);

-- ---------------------------------------------------------------------
-- 10. Rendimiento: Lote de 5.000 actividades
-- ---------------------------------------------------------------------
DO $$
DECLARE
  t0 timestamptz;
  t1 timestamptz;
  v_duracion interval;
BEGIN
  t0 := clock_timestamp();

  INSERT INTO crm.actividades (
    inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, wa_phone_number_id
  )
  SELECT
    '11111111-1111-1111-1111-111111111111',
    'mensaje_entrante',
    'humano',
    (SELECT id FROM c_admin),
    'Mensaje masivo lote ' || i,
    now() - (i || ' seconds')::interval,
    '320000000000001'
  FROM generate_series(1, 5000) AS i;

  t1 := clock_timestamp();
  v_duracion := t1 - t0;

  IF v_duracion > interval '10 seconds' THEN
    RAISE EXCEPTION 'El lote de 5.000 actividades tardó demasiado: %', v_duracion;
  END IF;
END $$;

SELECT ok(
  (SELECT count(*) FROM crm.actividades WHERE contacto_id = (SELECT id FROM c_admin)) >= 5000,
  'El lote de 5.000 actividades se procesó eficientemente'
);

SELECT * FROM finish();
ROLLBACK;
