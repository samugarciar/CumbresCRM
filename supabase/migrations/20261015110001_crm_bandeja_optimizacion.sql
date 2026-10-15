-- Migración: crm_bandeja_optimizacion
-- Optimización de rendimiento para crm.bandeja_contactos:
-- 1. Paginación antes de subconsultas (evita DISTINCT ON y agregaciones sobre todo el historial).
-- 2. Evaluación de turnos en WHERE solo si p_solo_esperando está especificado.
-- 3. Extracción de último mensaje y contadores mediante LATERAL únicamente para los 50 contactos finales.

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

COMMENT ON FUNCTION crm.bandeja_contactos(text, text, boolean, timestamptz, uuid, int, boolean, text) IS
  'Bandeja de entrada optimizada: paginación antes de subconsultas, turnos bajo demanda y metadatos por lateral.';

GRANT EXECUTE ON FUNCTION crm.bandeja_contactos(text, text, boolean, timestamptz, uuid, int, boolean, text) TO authenticated;
