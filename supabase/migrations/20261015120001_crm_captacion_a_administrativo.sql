-- Migración: crm_captacion_a_administrativo
-- 1. Eliminar la etapa 'por_aprobar' del embudo de captación.
-- 2. Permitir motivo de pérdida 'es_administrativa' en crm.oportunidades.
-- 3. Crear función crm.convertir_a_administrativo(uuid, boolean) para iniciar la relación
--    comercial/administrativa con un propietario captado o reclasificarlo.
-- 4. Ajustar precedencia de canal en crm.conteo_bandeja y crm.bandeja_contactos.

-- 1 · Ajustar el CHECK de motivo_perdida en crm.oportunidades
ALTER TABLE crm.oportunidades DROP CONSTRAINT IF EXISTS oportunidades_motivo_perdida_check;
ALTER TABLE crm.oportunidades ADD CONSTRAINT oportunidades_motivo_perdida_check
  CHECK (motivo_perdida = ANY (ARRAY[
    'precio'::text, 'zona'::text, 'disponibilidad'::text, 'requisitos'::text,
    'no_responde'::text, 'arrendo_con_otro'::text, 'duplicado'::text,
    'otro'::text, 'es_captacion'::text, 'es_administrativa'::text
  ]));

-- 2 · Eliminar etapa 'por_aprobar' de captación
UPDATE crm.oportunidades
   SET etapa = 'inmueble_verificado'
 WHERE embudo = 'captacion' AND etapa = 'por_aprobar';

UPDATE crm.transiciones
   SET etapa_desde = 'inmueble_verificado'
 WHERE etapa_desde = 'por_aprobar';

UPDATE crm.transiciones
   SET etapa_hasta = 'inmueble_verificado'
 WHERE etapa_hasta = 'por_aprobar';

DELETE FROM crm.etapas
 WHERE embudo = 'captacion' AND codigo = 'por_aprobar';

-- Reordenar etapas de captación (1: prospecto, 2: propietario_contactado, 3: visita_captacion, 4: inmueble_verificado, 5: negociando)
UPDATE crm.etapas SET orden = orden + 100 WHERE embudo = 'captacion';
UPDATE crm.etapas SET orden = 1 WHERE embudo = 'captacion' AND codigo = 'prospecto';
UPDATE crm.etapas SET orden = 2 WHERE embudo = 'captacion' AND codigo = 'propietario_contactado';
UPDATE crm.etapas SET orden = 3 WHERE embudo = 'captacion' AND codigo = 'visita_captacion';
UPDATE crm.etapas SET orden = 4 WHERE embudo = 'captacion' AND codigo = 'inmueble_verificado';
UPDATE crm.etapas SET orden = 5 WHERE embudo = 'captacion' AND codigo = 'negociando';

-- 3 · Función crm.convertir_a_administrativo
CREATE OR REPLACE FUNCTION crm.convertir_a_administrativo(
  p_contacto_id uuid,
  p_es_ganada   boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $adm$
DECLARE
  v_op_cap          crm.oportunidades%ROWTYPE;
  v_admin_id        uuid;
  v_org             uuid;
BEGIN
  SELECT c.inmobiliaria_id INTO v_org
    FROM crm.contactos c
   WHERE c.id = p_contacto_id AND c.deleted_at IS NULL;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Contacto no encontrado o no autorizado';
  END IF;

  -- 1 · Buscar caso de captación abierto
  SELECT * INTO v_op_cap
    FROM crm.oportunidades o
   WHERE o.contacto_id = p_contacto_id
     AND o.estado = 'abierta'
     AND o.embudo = 'captacion';

  -- Si no tiene captación abierta pero ya tiene caso administrativo, devolver el existente
  IF v_op_cap.id IS NULL THEN
    SELECT id INTO v_admin_id
      FROM crm.oportunidades
     WHERE contacto_id = p_contacto_id
       AND embudo = 'administrativa'
       AND estado = 'abierta';
    IF v_admin_id IS NOT NULL THEN
      RETURN v_admin_id;
    END IF;
  END IF;

  -- 2 · Si tiene captación abierta, cerrarla
  IF v_op_cap.id IS NOT NULL THEN
    IF p_es_ganada THEN
      UPDATE crm.oportunidades
         SET estado         = 'ganada',
             motivo_perdida = NULL,
             cerrada_at     = now(),
             cerrada_por    = (SELECT auth.uid()),
             updated_at     = now()
       WHERE id = v_op_cap.id;

      INSERT INTO crm.transiciones (
        inmobiliaria_id, oportunidad_id, etapa_desde, etapa_hasta,
        estado_hasta, origen, motivo, usuario_id
      ) VALUES (
        v_org, v_op_cap.id, v_op_cap.etapa, NULL,
        'ganada', 'humano', 'Captación exitosa: iniciada relación comercial en línea administrativa', (SELECT auth.uid())
      );
    ELSE
      UPDATE crm.oportunidades
         SET estado         = 'perdida',
             motivo_perdida = 'es_administrativa',
             cerrada_at     = now(),
             cerrada_por    = (SELECT auth.uid()),
             updated_at     = now()
       WHERE id = v_op_cap.id;

      INSERT INTO crm.transiciones (
        inmobiliaria_id, oportunidad_id, etapa_desde, etapa_hasta,
        estado_hasta, origen, motivo, usuario_id
      ) VALUES (
        v_org, v_op_cap.id, v_op_cap.etapa, NULL,
        'perdida', 'humano', 'Reclasificado a línea administrativa', (SELECT auth.uid())
      );
    END IF;
  END IF;

  -- 3 · Abrir o reutilizar el caso administrativo en 'al_dia'
  SELECT id INTO v_admin_id
    FROM crm.oportunidades
   WHERE contacto_id = p_contacto_id
     AND embudo = 'administrativa'
     AND estado = 'abierta';

  IF v_admin_id IS NULL THEN
    INSERT INTO crm.oportunidades (
      inmobiliaria_id, contacto_id, embudo, etapa, asesor_id
    ) VALUES (
      v_org, p_contacto_id, 'administrativa', 'al_dia', (SELECT c.asesor_id FROM crm.contactos c WHERE c.id = p_contacto_id)
    )
    RETURNING id INTO v_admin_id;

    INSERT INTO crm.transiciones (
      inmobiliaria_id, oportunidad_id, etapa_hasta, estado_hasta, origen, motivo, usuario_id
    ) VALUES (
      v_org, v_admin_id, 'al_dia', 'abierta', 'humano', 'Iniciada relación comercial en línea administrativa', (SELECT auth.uid())
    );
  END IF;

  -- 4 · Dejar rastro en actividades
  INSERT INTO crm.actividades (
    inmobiliaria_id, tipo, origen, contacto_id,
    cuerpo, metadata, creado_por, ocurrido_at
  ) VALUES (
    v_org, 'sistema', 'humano', p_contacto_id,
    CASE
      WHEN p_es_ganada THEN 'Captación exitosa: iniciada relación comercial en línea administrativa'
      ELSE 'Proceso de captación reclasificado a línea administrativa'
    END,
    jsonb_build_object(
      'caso_administrativo_id', v_admin_id,
      'captacion_cerrada_id', v_op_cap.id,
      'es_ganada', p_es_ganada
    ),
    (SELECT auth.uid()),
    now()
  );

  RETURN v_admin_id;
END;
$adm$;

COMMENT ON FUNCTION crm.convertir_a_administrativo(uuid, boolean) IS
  'Cierra un proceso de captación (como ganada o reclasificada) y abre o enlaza un caso administrativo para el propietario.';

GRANT EXECUTE ON FUNCTION crm.convertir_a_administrativo(uuid, boolean) TO authenticated;

-- 4 · Ajustar precedencia de canal en crm.conteo_bandeja y crm.bandeja_contactos
CREATE OR REPLACE FUNCTION crm.conteo_bandeja()
RETURNS TABLE (
  total                     bigint,
  total_esperando           bigint,
  comercial_total           bigint,
  comercial_esperando       bigint,
  admin_captacion_total     bigint,
  admin_captacion_esperando bigint,
  admin_total               bigint,
  admin_esperando           bigint,
  captacion_total           bigint,
  captacion_esperando       bigint
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $conteo$
  WITH clasificados AS (
    SELECT 
      c.id,
      CASE
        WHEN EXISTS (
          SELECT 1 FROM crm.oportunidades o 
           WHERE o.contacto_id = c.id AND o.embudo = 'captacion' AND o.estado = 'abierta'
        ) THEN 'captacion'
        WHEN EXISTS (
          SELECT 1 FROM crm.oportunidades o 
           WHERE o.contacto_id = c.id AND o.embudo = 'administrativa' AND o.estado = 'abierta'
        ) THEN 'administrativa'
        WHEN c.tipo = 'propietario' THEN 'captacion'
        WHEN EXISTS (
          SELECT 1 FROM crm.actividades a
            JOIN crm.lineas l ON l.wa_phone_number_id = a.wa_phone_number_id
           WHERE a.contacto_id = c.id AND l.embudo = 'administrativa'
        ) THEN 'administrativa'
        ELSE 'comercial'
      END AS canal,
      COALESCE(
        (
          SELECT max(a.ocurrido_at) FROM crm.actividades a 
           WHERE a.contacto_id = c.id AND a.tipo = 'mensaje_entrante'
        ) > COALESCE(
          (
            SELECT max(a.ocurrido_at) FROM crm.actividades a 
             WHERE a.contacto_id = c.id AND a.tipo IN ('mensaje_saliente', 'nota', 'llamada')
          ),
          '-infinity'::timestamptz
        ),
        false
      ) AS esperando
    FROM crm.contactos c
    WHERE c.deleted_at IS NULL
  )
  SELECT
    count(*) AS total,
    count(*) FILTER (WHERE esperando) AS total_esperando,
    count(*) FILTER (WHERE canal = 'comercial') AS comercial_total,
    count(*) FILTER (WHERE canal = 'comercial' AND esperando) AS comercial_esperando,
    count(*) FILTER (WHERE canal IN ('administrativa', 'captacion')) AS admin_captacion_total,
    count(*) FILTER (WHERE canal IN ('administrativa', 'captacion') AND esperando) AS admin_captacion_esperando,
    count(*) FILTER (WHERE canal = 'administrativa') AS admin_total,
    count(*) FILTER (WHERE canal = 'administrativa' AND esperando) AS admin_esperando,
    count(*) FILTER (WHERE canal = 'captacion') AS captacion_total,
    count(*) FILTER (WHERE canal = 'captacion' AND esperando) AS captacion_esperando
  FROM clasificados;
$conteo$;

CREATE OR REPLACE FUNCTION crm.bandeja_contactos(
  p_texto          text        DEFAULT NULL,
  p_tipo           text        DEFAULT NULL,
  p_sin_telefono   boolean     DEFAULT NULL,
  p_cursor_at      timestamptz DEFAULT NULL,
  p_cursor_id      uuid        DEFAULT NULL,
  p_limite         int         DEFAULT 50,
  p_solo_esperando boolean     DEFAULT NULL,
  p_canal          text        DEFAULT NULL
)
RETURNS TABLE (
  id                  uuid,
  nombre              text,
  telefono_e164       text,
  telefono_crudo      text,
  tipo                text,
  origen              text,
  asesor_id           uuid,
  ultima_actividad_at timestamptz,
  orden_at            timestamptz,
  n_actividades       bigint,
  sin_leer            bigint,
  esperando_respuesta boolean,
  ultimo_mensaje      text,
  ultimo_mensaje_at   timestamptz,
  ultimo_mensaje_tipo text,
  canal               text,
  linea_nombre        text,
  embudos_activos     text[]
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $funcion$
  WITH contactos_candidatos AS (
    SELECT
      c.id,
      c.nombre,
      c.telefono_e164,
      c.telefono_crudo,
      c.tipo,
      c.origen,
      c.asesor_id,
      c.ultima_actividad_at,
      COALESCE(c.ultima_actividad_at, c.created_at) AS orden_at,
      CASE
        WHEN EXISTS (
          SELECT 1 FROM crm.oportunidades o 
           WHERE o.contacto_id = c.id AND o.embudo = 'captacion' AND o.estado = 'abierta'
        ) THEN 'captacion'
        WHEN EXISTS (
          SELECT 1 FROM crm.oportunidades o 
           WHERE o.contacto_id = c.id AND o.embudo = 'administrativa' AND o.estado = 'abierta'
        ) THEN 'administrativa'
        WHEN c.tipo = 'propietario' THEN 'captacion'
        WHEN EXISTS (
          SELECT 1 FROM crm.actividades a
            JOIN crm.lineas l ON l.wa_phone_number_id = a.wa_phone_number_id
           WHERE a.contacto_id = c.id AND l.embudo = 'administrativa'
        ) THEN 'administrativa'
        ELSE 'comercial'
      END AS canal
    FROM crm.contactos c
    WHERE c.deleted_at IS NULL
      AND (p_tipo IS NULL OR c.tipo = p_tipo)
      AND (
        p_sin_telefono IS NULL
        OR (p_sin_telefono     AND c.telefono_e164 IS NULL)
        OR (NOT p_sin_telefono AND c.telefono_e164 IS NOT NULL)
      )
      AND (
        p_texto IS NULL OR btrim(p_texto) = ''
        OR public.unaccent(COALESCE(c.nombre, '')) ILIKE '%' || public.unaccent(p_texto) || '%'
        OR extensions.strict_word_similarity(
             public.unaccent(p_texto), public.unaccent(COALESCE(c.nombre, ''))) > 0.3
        OR (
          regexp_replace(p_texto, '[^0-9]', '', 'g') <> ''
          AND (
            c.telefono_e164 LIKE '%' || regexp_replace(p_texto, '[^0-9]', '', 'g') || '%'
            OR c.telefono_crudo LIKE '%' || regexp_replace(p_texto, '[^0-9]', '', 'g') || '%'
          )
        )
      )
      AND (
        p_cursor_at IS NULL
        OR (COALESCE(c.ultima_actividad_at, c.created_at), c.id)
           < (p_cursor_at, p_cursor_id)
      )
  ),
  contactos_canal AS (
    SELECT cc.*
    FROM contactos_candidatos cc
    WHERE (
      p_canal IS NULL OR p_canal = 'todos'
      OR (p_canal = 'comercial' AND cc.canal = 'comercial')
      OR (p_canal = 'administrativa_captacion' AND cc.canal IN ('administrativa', 'captacion'))
      OR (p_canal = 'administrativa' AND cc.canal = 'administrativa')
      OR (p_canal = 'captacion' AND cc.canal = 'captacion')
    )
  ),
  contactos_paginados AS (
    SELECT
      cc.*
    FROM contactos_canal cc
    WHERE (
      p_solo_esperando IS NULL
      OR (p_solo_esperando AND (
        (SELECT max(a.ocurrido_at) FROM crm.actividades a WHERE a.contacto_id = cc.id AND a.tipo = 'mensaje_entrante') >
        COALESCE(
          (SELECT max(a.ocurrido_at) FROM crm.actividades a WHERE a.contacto_id = cc.id AND a.tipo IN ('mensaje_saliente', 'nota', 'llamada')),
          '-infinity'::timestamptz
        )
      ))
      OR (NOT p_solo_esperando AND (
        (SELECT max(a.ocurrido_at) FROM crm.actividades a WHERE a.contacto_id = cc.id AND a.tipo = 'mensaje_entrante') IS NULL
        OR COALESCE(
          (SELECT max(a.ocurrido_at) FROM crm.actividades a WHERE a.contacto_id = cc.id AND a.tipo IN ('mensaje_saliente', 'nota', 'llamada')),
          '-infinity'::timestamptz
        ) >= (SELECT max(a.ocurrido_at) FROM crm.actividades a WHERE a.contacto_id = cc.id AND a.tipo = 'mensaje_entrante')
      ))
    )
    ORDER BY cc.orden_at DESC, cc.id DESC
    LIMIT least(COALESCE(p_limite, 50), 200)
  )
  SELECT
    cp.id,
    cp.nombre,
    cp.telefono_e164,
    cp.telefono_crudo,
    cp.tipo,
    cp.origen,
    cp.asesor_id,
    cp.ultima_actividad_at,
    cp.orden_at,
    (SELECT count(*) FROM crm.actividades a WHERE a.contacto_id = cp.id) AS n_actividades,
    (SELECT count(*) FROM crm.actividades a
      WHERE a.contacto_id = cp.id
        AND a.ocurrido_at > COALESCE(l.visto_hasta, '-infinity'::timestamptz)) AS sin_leer,
    COALESCE(
      (
        (SELECT max(a.ocurrido_at) FROM crm.actividades a WHERE a.contacto_id = cp.id AND a.tipo = 'mensaje_entrante') >
        COALESCE(
          (SELECT max(a.ocurrido_at) FROM crm.actividades a WHERE a.contacto_id = cp.id AND a.tipo IN ('mensaje_saliente', 'nota', 'llamada')),
          '-infinity'::timestamptz
        )
      ),
      false
    ) AS esperando_respuesta,
    um.cuerpo AS ultimo_mensaje,
    um.ocurrido_at AS ultimo_mensaje_at,
    um.tipo AS ultimo_mensaje_tipo,
    cp.canal,
    COALESCE(
      (
        SELECT l.nombre
          FROM crm.actividades a
          JOIN crm.lineas l ON l.wa_phone_number_id = a.wa_phone_number_id
         WHERE a.contacto_id = cp.id
         ORDER BY a.ocurrido_at DESC, a.id DESC
         LIMIT 1
      ),
      CASE
        WHEN cp.canal IN ('administrativa', 'captacion') THEN 'Línea Administrativa 320'
        ELSE 'Línea Comercial 324'
      END
    ) AS linea_nombre,
    ARRAY(
      SELECT DISTINCT o.embudo
        FROM crm.oportunidades o
       WHERE o.contacto_id = cp.id AND o.estado = 'abierta'
       ORDER BY o.embudo
    ) AS embudos_activos
  FROM contactos_paginados cp
  LEFT JOIN LATERAL (
    SELECT a.cuerpo, a.ocurrido_at, a.tipo
      FROM crm.actividades a
     WHERE a.contacto_id = cp.id
       AND a.tipo IN ('mensaje_entrante', 'mensaje_saliente', 'nota', 'llamada')
     ORDER BY a.ocurrido_at DESC, a.id DESC
     LIMIT 1
  ) um ON true
  LEFT JOIN crm.lecturas l
    ON l.contacto_id = cp.id AND l.usuario_id = (SELECT auth.uid())
  ORDER BY cp.orden_at DESC, cp.id DESC;
$funcion$;
