-- Migración: crm_bandeja_por_canal
-- Permite segmentar la bandeja de entrada por canal y línea:
--   - Comercial (Línea 324, embudo comercial, leads y clientes de compra/arriendo)
--   - Administrativo y Captaciones (Línea 320, embudos administrativa y captación, inquilinos y propietarios)
--   - Todo (visión completa)
-- Retorna el canal, la línea activa y los embudos abiertos de cada contacto.

-- 1. Eliminar firma anterior para evitar sobrecarga (prueba 23)
DROP FUNCTION IF EXISTS crm.bandeja_contactos(text, text, boolean, timestamptz, uuid, int, boolean);

-- 2. Función conteo_bandeja: contadores globales y por canal para pestañas de la bandeja
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
        ) OR c.tipo = 'propietario' THEN 'captacion'
        WHEN EXISTS (
          SELECT 1 FROM crm.oportunidades o 
           WHERE o.contacto_id = c.id AND o.embudo = 'administrativa' AND o.estado = 'abierta'
        ) THEN 'administrativa'
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

COMMENT ON FUNCTION crm.conteo_bandeja() IS
  'Contadores de conversaciones totales y en espera, desglosados por canal y línea para la bandeja de entrada.';

GRANT EXECUTE ON FUNCTION crm.conteo_bandeja() TO authenticated;

-- 3. Función bandeja_contactos actualizada con filtro de canal y metadatos de línea/embudo
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
  ),
  canales_contacto AS (
    SELECT
      c.id AS contacto_id,
      CASE
        WHEN EXISTS (
          SELECT 1 FROM crm.oportunidades o 
           WHERE o.contacto_id = c.id AND o.embudo = 'captacion' AND o.estado = 'abierta'
        ) OR c.tipo = 'propietario' THEN 'captacion'
        WHEN EXISTS (
          SELECT 1 FROM crm.oportunidades o 
           WHERE o.contacto_id = c.id AND o.embudo = 'administrativa' AND o.estado = 'abierta'
        ) THEN 'administrativa'
        WHEN EXISTS (
          SELECT 1 FROM crm.actividades a
            JOIN crm.lineas l ON l.wa_phone_number_id = a.wa_phone_number_id
           WHERE a.contacto_id = c.id AND l.embudo = 'administrativa'
        ) THEN 'administrativa'
        ELSE 'comercial'
      END AS canal,
      COALESCE(
        (
          SELECT l.nombre
            FROM crm.actividades a
            JOIN crm.lineas l ON l.wa_phone_number_id = a.wa_phone_number_id
           WHERE a.contacto_id = c.id
           ORDER BY a.ocurrido_at DESC, a.id DESC
           LIMIT 1
        ),
        CASE
          WHEN EXISTS (
            SELECT 1 FROM crm.oportunidades o
             WHERE o.contacto_id = c.id AND o.embudo IN ('administrativa', 'captacion') AND o.estado = 'abierta'
          ) OR c.tipo = 'propietario' THEN 'Línea Administrativa 320'
          ELSE 'Línea Comercial 324'
        END
      ) AS linea_nombre,
      ARRAY(
        SELECT DISTINCT o.embudo
          FROM crm.oportunidades o
         WHERE o.contacto_id = c.id AND o.estado = 'abierta'
         ORDER BY o.embudo
      ) AS embudos_activos
    FROM crm.contactos c
    WHERE c.deleted_at IS NULL
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
    um.tipo_act AS ultimo_mensaje_tipo,
    cc.canal,
    cc.linea_nombre,
    cc.embudos_activos
  FROM crm.contactos c
  JOIN turnos t ON t.contacto_id = c.id
  JOIN canales_contacto cc ON cc.contacto_id = c.id
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
      p_canal IS NULL OR p_canal = 'todos'
      OR (p_canal = 'comercial' AND (
        EXISTS (
          SELECT 1 FROM crm.oportunidades o 
           WHERE o.contacto_id = c.id AND o.embudo = 'comercial' AND o.estado = 'abierta'
        )
        OR (
          NOT EXISTS (
            SELECT 1 FROM crm.oportunidades o 
             WHERE o.contacto_id = c.id AND o.embudo IN ('administrativa', 'captacion') AND o.estado = 'abierta'
          )
          AND c.tipo <> 'propietario'
          AND NOT EXISTS (
            SELECT 1 FROM crm.actividades a
              JOIN crm.lineas l2 ON l2.wa_phone_number_id = a.wa_phone_number_id
             WHERE a.contacto_id = c.id AND l2.embudo = 'administrativa'
          )
        )
      ))
      OR (p_canal IN ('administrativa_captacion', 'administrativa', 'captacion') AND (
        CASE 
          WHEN p_canal = 'administrativa' THEN
            EXISTS (
              SELECT 1 FROM crm.oportunidades o 
               WHERE o.contacto_id = c.id AND o.embudo = 'administrativa' AND o.estado = 'abierta'
            )
          WHEN p_canal = 'captacion' THEN
            EXISTS (
              SELECT 1 FROM crm.oportunidades o 
               WHERE o.contacto_id = c.id AND o.embudo = 'captacion' AND o.estado = 'abierta'
            ) OR c.tipo = 'propietario'
          ELSE -- 'administrativa_captacion'
            EXISTS (
              SELECT 1 FROM crm.oportunidades o 
               WHERE o.contacto_id = c.id AND o.embudo IN ('administrativa', 'captacion') AND o.estado = 'abierta'
            )
            OR c.tipo = 'propietario'
            OR EXISTS (
              SELECT 1 FROM crm.actividades a
                JOIN crm.lineas l3 ON l3.wa_phone_number_id = a.wa_phone_number_id
               WHERE a.contacto_id = c.id AND l3.embudo = 'administrativa'
            )
        END
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

COMMENT ON FUNCTION crm.bandeja_contactos(text, text, boolean, timestamptz, uuid, int, boolean, text) IS
  'Bandeja de entrada: lista de contactos con filtro de canal/línea, estado de espera, último mensaje y lecturas.';

GRANT EXECUTE ON FUNCTION crm.bandeja_contactos(text, text, boolean, timestamptz, uuid, int, boolean, text)
  TO authenticated;
