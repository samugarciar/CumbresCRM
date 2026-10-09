-- =====================================================================
-- BANDEJA DE ENTRADA: Turno de respuesta, último mensaje y marcar atendido
-- =====================================================================

-- 1. Eliminar firma anterior de bandeja_contactos para no dejar sobrecargas
DROP FUNCTION IF EXISTS crm.bandeja_contactos(text, text, boolean, timestamptz, uuid, int);

-- 2. Nueva versión de bandeja_contactos con turno de respuesta y último mensaje
CREATE OR REPLACE FUNCTION crm.bandeja_contactos(
  p_texto          text        DEFAULT NULL,
  p_tipo           text        DEFAULT NULL,
  p_sin_telefono   boolean     DEFAULT NULL,
  p_cursor_at      timestamptz DEFAULT NULL,
  p_cursor_id      uuid        DEFAULT NULL,
  p_limite         int         DEFAULT 50,
  p_solo_esperando boolean     DEFAULT NULL
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
  ultimo_mensaje_tipo text
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $funcion$
  WITH turnos AS (
    SELECT
      c.id AS contacto_id,
      (
        SELECT max(a.ocurrido_at)
          FROM crm.actividades a
         WHERE a.contacto_id = c.id
           AND a.tipo = 'mensaje_entrante'
      ) AS ult_entrante_at,
      (
        SELECT max(a.ocurrido_at)
          FROM crm.actividades a
         WHERE a.contacto_id = c.id
           AND a.tipo IN ('mensaje_saliente', 'nota', 'llamada')
      ) AS ult_respuesta_at
    FROM crm.contactos c
    WHERE c.deleted_at IS NULL
  ),
  ultimos_mensajes AS (
    SELECT DISTINCT ON (a.contacto_id)
      a.contacto_id,
      a.cuerpo AS texto,
      a.ocurrido_at AS ocurrido,
      a.tipo AS tipo_act
    FROM crm.actividades a
    WHERE a.tipo IN ('mensaje_entrante', 'mensaje_saliente', 'nota', 'llamada')
    ORDER BY a.contacto_id, a.ocurrido_at DESC, a.id DESC
  )
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
    (SELECT count(*) FROM crm.actividades a WHERE a.contacto_id = c.id) AS n_actividades,
    (SELECT count(*) FROM crm.actividades a
      WHERE a.contacto_id = c.id
        AND a.ocurrido_at > COALESCE(l.visto_hasta, '-infinity'::timestamptz)) AS sin_leer,
    CASE
      WHEN t.ult_entrante_at IS NULL THEN false
      WHEN t.ult_respuesta_at IS NULL THEN true
      WHEN t.ult_entrante_at > t.ult_respuesta_at THEN true
      ELSE false
    END AS esperando_respuesta,
    um.texto AS ultimo_mensaje,
    um.ocurrido AS ultimo_mensaje_at,
    um.tipo_act AS ultimo_mensaje_tipo
  FROM crm.contactos c
  JOIN turnos t ON t.contacto_id = c.id
  LEFT JOIN ultimos_mensajes um ON um.contacto_id = c.id
  LEFT JOIN crm.lecturas l
    ON l.contacto_id = c.id AND l.usuario_id = (SELECT auth.uid())
  WHERE c.deleted_at IS NULL
    AND (p_tipo IS NULL OR c.tipo = p_tipo)
    AND (
      p_sin_telefono IS NULL
      OR (p_sin_telefono     AND c.telefono_e164 IS NULL)
      OR (NOT p_sin_telefono AND c.telefono_e164 IS NOT NULL)
    )
    AND (
      p_solo_esperando IS NULL
      OR (p_solo_esperando AND (
        t.ult_entrante_at IS NOT NULL AND (
          t.ult_respuesta_at IS NULL OR t.ult_entrante_at > t.ult_respuesta_at
        )
      ))
      OR (NOT p_solo_esperando AND (
        t.ult_entrante_at IS NULL OR (
          t.ult_respuesta_at IS NOT NULL AND t.ult_respuesta_at >= t.ult_entrante_at
        )
      ))
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
  ORDER BY COALESCE(c.ultima_actividad_at, c.created_at) DESC, c.id DESC
  LIMIT least(COALESCE(p_limite, 50), 200);
$funcion$;

COMMENT ON FUNCTION crm.bandeja_contactos(text, text, boolean, timestamptz, uuid, int, boolean) IS
  'Bandeja de entrada: lista de contactos con estado de espera de respuesta, último mensaje y lecturas.';

GRANT EXECUTE ON FUNCTION crm.bandeja_contactos(text, text, boolean, timestamptz, uuid, int, boolean)
  TO authenticated;

-- 3. Función marcar_atendido: permite dar por respondida una conversación sin enviar WhatsApp
CREATE OR REPLACE FUNCTION crm.marcar_atendido(
  p_contacto_id uuid,
  p_nota        text DEFAULT 'Conversación marcada como atendida'
)
RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $marcar$
DECLARE
  v_org uuid;
BEGIN
  SELECT c.inmobiliaria_id INTO v_org
    FROM crm.contactos c WHERE c.id = p_contacto_id;

  IF v_org IS NULL THEN
    RETURN;
  END IF;

  -- Actualiza visto_hasta para limpiar el contador de no leídos
  INSERT INTO crm.lecturas (contacto_id, usuario_id, inmobiliaria_id, visto_hasta)
  VALUES (p_contacto_id, (SELECT auth.uid()), v_org, now())
  ON CONFLICT (contacto_id, usuario_id)
  DO UPDATE SET visto_hasta = now();

  -- Inserta nota humana para nivelar el turno de respuesta
  INSERT INTO crm.actividades (
    inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, creado_por
  ) VALUES (
    v_org, 'nota', 'humano', p_contacto_id,
    COALESCE(NULLIF(btrim(p_nota), ''), 'Conversación marcada como atendida'),
    now(),
    (SELECT auth.uid())
  );
END $marcar$;

COMMENT ON FUNCTION crm.marcar_atendido(uuid, text) IS
  'Marca una conversación como leída y atendida por el equipo mediante una nota humana.';

GRANT EXECUTE ON FUNCTION crm.marcar_atendido(uuid, text) TO authenticated;
