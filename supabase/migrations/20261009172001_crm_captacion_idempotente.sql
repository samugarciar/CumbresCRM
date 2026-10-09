-- Migración: crm_captacion_idempotente
-- Hace que crm.convertir_a_captacion sea idempotente y nunca falle si ya existe
-- una oportunidad de captación abierta para el contacto.

CREATE OR REPLACE FUNCTION crm.convertir_a_captacion(p_contacto_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $capt$
DECLARE
  v_op_admin        crm.oportunidades%ROWTYPE;
  v_captacion_id    uuid;
  v_org             uuid;
  v_tiene_comercial boolean;
  v_nuevo_tipo      text;
BEGIN
  SELECT c.inmobiliaria_id INTO v_org
    FROM crm.contactos c
   WHERE c.id = p_contacto_id AND c.deleted_at IS NULL;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Contacto no encontrado o no autorizado';
  END IF;

  -- 1 · Buscar caso administrativo abierto
  SELECT * INTO v_op_admin
    FROM crm.oportunidades o
   WHERE o.contacto_id = p_contacto_id
     AND o.estado = 'abierta'
     AND o.embudo = 'administrativa';

  IF v_op_admin.id IS NULL THEN
    RAISE EXCEPTION 'El contacto no tiene un caso administrativo abierto';
  END IF;

  -- 2 · Cerrar el caso administrativo sin que cuente como pérdida comercial
  UPDATE crm.oportunidades
     SET estado         = 'perdida',
         motivo_perdida = 'es_captacion',
         cerrada_at     = now(),
         cerrada_por    = (SELECT auth.uid()),
         updated_at     = now()
   WHERE id = v_op_admin.id;

  INSERT INTO crm.transiciones
    (inmobiliaria_id, oportunidad_id, etapa_desde, etapa_hasta,
     estado_hasta, origen, motivo, usuario_id)
  VALUES (v_org, v_op_admin.id, v_op_admin.etapa, NULL,
          'perdida', 'humano', 'Reclasificado como captación', (SELECT auth.uid()));

  -- 3 · Abrir el prospecto de captación en 'prospecto' (o reutilizar el existente si ya estaba abierto)
  SELECT id INTO v_captacion_id
    FROM crm.oportunidades
   WHERE contacto_id = p_contacto_id
     AND embudo = 'captacion'
     AND estado = 'abierta';

  IF v_captacion_id IS NULL THEN
    INSERT INTO crm.oportunidades (
      inmobiliaria_id, contacto_id, embudo, etapa, asesor_id
    ) VALUES (
      v_org, p_contacto_id, 'captacion', 'prospecto', (SELECT c.asesor_id FROM crm.contactos c WHERE c.id = p_contacto_id)
    )
    RETURNING id INTO v_captacion_id;

    INSERT INTO crm.transiciones (
      inmobiliaria_id, oportunidad_id, etapa_hasta, estado_hasta, origen, motivo, usuario_id
    ) VALUES (
      v_org, v_captacion_id, 'prospecto', 'abierta', 'humano', 'Reclasificado como captación', (SELECT auth.uid())
    );
  END IF;

  -- 4 · Cambiar el tipo de contacto a 'propietario', o a 'ambos' si ya tenía una oportunidad comercial
  SELECT EXISTS (
    SELECT 1 FROM crm.oportunidades o
     WHERE o.contacto_id = p_contacto_id AND o.embudo = 'comercial'
  ) INTO v_tiene_comercial;

  IF v_tiene_comercial THEN
    v_nuevo_tipo := 'ambos';
  ELSE
    v_nuevo_tipo := 'propietario';
  END IF;

  UPDATE crm.contactos
     SET tipo = v_nuevo_tipo, updated_at = now()
   WHERE id = p_contacto_id;

  -- 5 · Dejar rastro en el historial del contacto
  INSERT INTO crm.actividades (
    inmobiliaria_id, tipo, origen, contacto_id,
    cuerpo, metadata, creado_por, ocurrido_at
  ) VALUES (
    v_org, 'sistema', 'humano', p_contacto_id,
    'Caso administrativo reclasificado como prospecto de captación',
    jsonb_build_object(
      'oportunidad_id', v_captacion_id,
      'caso_administrativo_cerrado_id', v_op_admin.id
    ),
    (SELECT auth.uid()),
    now()
  );

  RETURN v_captacion_id;
END;
$capt$;

COMMENT ON FUNCTION crm.convertir_a_captacion(uuid) IS
  'Cierra un caso administrativo como es_captacion, abre o enlaza un prospecto de captación de forma idempotente y actualiza el tipo del contacto a propietario o ambos.';

GRANT EXECUTE ON FUNCTION crm.convertir_a_captacion(uuid) TO authenticated;
