-- =====================================================================
-- Una sola regla para «Esperando respuesta» (26 oct 2026)
--
-- LO QUE PASABA
-- La bandeja, sus contadores y la ficha contestaban la misma pregunta
-- —¿esta persona está esperando que le respondamos?— con dos reglas:
--   · crm.bandeja_contactos y crm.conteo_bandeja tomaban CUALQUIER
--     mensaje saliente como respuesta, también el del bot. A quien el bot
--     le contestó y después lo calló un asesor o un escalamiento, la
--     bandeja lo daba por «Al día» aunque nadie le fuera a escribir.
--   · crm.resumen_contacto (la ficha) solo contaba a una persona del
--     equipo, pero contaba CUALQUIER actividad humana, también el aviso de
--     sistema que deja cambiar_bot. Encender o apagar el bot «respondía».
-- Resultado: el 🔥 de la bandeja no listaba a quien la ficha daba por
-- esperando (Laura en local; el lead de prueba c98ef1d4 en producción).
--
-- LA REGLA (vive en crm.esperando_desde y en ningún otro sitio)
--   ult_cliente = su último mensaje entrante.
--   ult_equipo  = la última vez que alguien del equipo le respondió:
--                 mensaje saliente, nota o llamada de origen 'humano'.
--                 Los avisos de tipo 'sistema' (cambiar_bot, relevo,
--                 escalamiento) NO cuentan: no le dicen nada a la persona.
--   ult_bot     = el último mensaje saliente del bot ('agente_ia').
--   Espera si escribió después del equipo Y, además, o el bot está
--   callado o escribió después del bot. Con el bot activo, que el bot
--   haya contestado basta; con el bot callado (relevo, escalamiento o a
--   mano) solo cuenta una persona.
--
-- Las tres funciones de pantalla la llaman, así que el número 🔥 de cada
-- pestaña, las filas del filtro y la ficha no pueden volver a discrepar.
-- Para cambiar la regla se cambia crm.esperando_desde y nada más.
--
-- DE PASO
-- linea_nombre ya no inventa «Línea Comercial 324» ni «Línea
-- Administrativa 320» cuando el contacto no tiene actividad por una línea:
-- la comercial ya es la 312 y el nombre solo puede salir de crm.lineas.
-- Sin línea, NULL.
--
-- Mismas firmas que antes; idempotente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. La regla
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.esperando_desde(p_contacto_id uuid)
RETURNS timestamptz
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $funcion$
  -- Una sola pasada por las actividades del contacto (índice
  -- actividades_timeline), con FILTER para cada «último».
  SELECT CASE
           WHEN m.ult_cliente > COALESCE(m.ult_equipo, '-infinity'::timestamptz)
            AND (NOT c.bot_activo
                 OR m.ult_cliente > COALESCE(m.ult_bot, '-infinity'::timestamptz))
           THEN m.ult_cliente
         END
    FROM crm.contactos c
    CROSS JOIN LATERAL (
      SELECT
        max(a.ocurrido_at) FILTER (WHERE a.tipo = 'mensaje_entrante')
          AS ult_cliente,
        max(a.ocurrido_at) FILTER (WHERE a.origen = 'humano'
                                     AND a.tipo IN ('mensaje_saliente', 'nota', 'llamada'))
          AS ult_equipo,
        max(a.ocurrido_at) FILTER (WHERE a.origen = 'agente_ia'
                                     AND a.tipo = 'mensaje_saliente')
          AS ult_bot
        FROM crm.actividades a
       WHERE a.contacto_id = c.id
    ) m
   WHERE c.id = p_contacto_id;
$funcion$;

COMMENT ON FUNCTION crm.esperando_desde(uuid) IS
  'Desde cuándo espera esta persona que le respondamos (su último mensaje), o NULL si no espera. '
  'LA regla del 🔥: espera si escribió después de la última respuesta del equipo (mensaje saliente, '
  'nota o llamada de origen humano; los avisos de sistema como cambiar_bot no cuentan) y, si el bot '
  'está activo, también después del último mensaje del bot. Con el bot callado solo cuenta una persona. '
  'La usan bandeja_contactos, conteo_bandeja y resumen_contacto: para cambiar la regla, cámbiala aquí.';

REVOKE ALL ON FUNCTION crm.esperando_desde(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm.esperando_desde(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 2. La bandeja
-- ---------------------------------------------------------------------
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
    SELECT cc.*
    FROM contactos_canal cc
    -- La regla del 🔥 solo se evalúa sobre todos los candidatos cuando
    -- se pide el filtro; sin él, solo sobre las filas de la página.
    WHERE (
      p_solo_esperando IS NULL
      OR (p_solo_esperando     AND crm.esperando_desde(cc.id) IS NOT NULL)
      OR (NOT p_solo_esperando AND crm.esperando_desde(cc.id) IS NULL)
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
    cnt.n_actividades,
    cnt.sin_leer,
    crm.esperando_desde(cp.id) IS NOT NULL AS esperando_respuesta,
    um.cuerpo AS ultimo_mensaje,
    um.ocurrido_at AS ultimo_mensaje_at,
    um.tipo AS ultimo_mensaje_tipo,
    cp.canal,
    -- Solo el nombre que tenga la línea en crm.lineas; sin línea, NULL.
    (
      SELECT ln.nombre
        FROM crm.actividades a
        JOIN crm.lineas ln ON ln.wa_phone_number_id = a.wa_phone_number_id
       WHERE a.contacto_id = cp.id
       ORDER BY a.ocurrido_at DESC, a.id DESC
       LIMIT 1
    ) AS linea_nombre,
    ARRAY(
      SELECT DISTINCT o.embudo
        FROM crm.oportunidades o
       WHERE o.contacto_id = cp.id AND o.estado = 'abierta'
       ORDER BY o.embudo
    ) AS embudos_activos
  FROM contactos_paginados cp
  LEFT JOIN crm.lecturas l
    ON l.contacto_id = cp.id AND l.usuario_id = (SELECT auth.uid())
  -- Los dos contadores en una sola pasada.
  CROSS JOIN LATERAL (
    SELECT count(*) AS n_actividades,
           count(*) FILTER (
             WHERE a.ocurrido_at > COALESCE(l.visto_hasta, '-infinity'::timestamptz)
           ) AS sin_leer
      FROM crm.actividades a
     WHERE a.contacto_id = cp.id
  ) cnt
  LEFT JOIN LATERAL (
    SELECT a.cuerpo, a.ocurrido_at, a.tipo
      FROM crm.actividades a
     WHERE a.contacto_id = cp.id
       AND a.tipo IN ('mensaje_entrante', 'mensaje_saliente', 'nota', 'llamada')
     ORDER BY a.ocurrido_at DESC, a.id DESC
     LIMIT 1
  ) um ON true
  ORDER BY cp.orden_at DESC, cp.id DESC;
$funcion$;

COMMENT ON FUNCTION crm.bandeja_contactos(text, text, boolean, timestamptz, uuid, int, boolean, text) IS
  'Bandeja de entrada: contactos por canal con el 🔥 de crm.esperando_desde, último mensaje y no leídos. '
  'linea_nombre sale solo de crm.lineas (NULL si no tiene).';

GRANT EXECUTE ON FUNCTION crm.bandeja_contactos(text, text, boolean, timestamptz, uuid, int, boolean, text)
  TO authenticated;

-- ---------------------------------------------------------------------
-- 3. Los contadores de las pestañas
-- ---------------------------------------------------------------------
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
AS $funcion$
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
      -- La misma regla que las filas del filtro y que la ficha.
      crm.esperando_desde(c.id) IS NOT NULL AS esperando
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
$funcion$;

COMMENT ON FUNCTION crm.conteo_bandeja() IS
  'Contadores de la bandeja por canal; «esperando» es crm.esperando_desde, la misma regla del filtro y de la ficha.';

GRANT EXECUTE ON FUNCTION crm.conteo_bandeja() TO authenticated;

-- ---------------------------------------------------------------------
-- 4. La ficha
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.resumen_contacto(p_contacto_id uuid)
RETURNS TABLE (
  mensajes_cliente      bigint,
  mensajes_bot          bigint,
  ultimo_del_cliente_at timestamptz,
  -- Segundos que lleva esperando según crm.esperando_desde (la regla del
  -- 🔥 de la bandeja). NULL si no espera.
  esperando_segundos    bigint,
  visitas_agendadas     bigint,
  visitas_realizadas    bigint,
  visitas_canceladas    bigint,
  solicitudes_horario   bigint,
  inmuebles             text[],
  actividades_total     bigint,
  sin_leer              bigint,
  visto_hasta           timestamptz
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $resumen$
  WITH act AS (
    SELECT a.* FROM crm.actividades a WHERE a.contacto_id = p_contacto_id
  ),
  leido AS (
    SELECT l.visto_hasta FROM crm.lecturas l
     WHERE l.contacto_id = p_contacto_id
       AND l.usuario_id = (SELECT auth.uid())
  )
  SELECT
    count(*) FILTER (WHERE tipo = 'mensaje_entrante'),
    count(*) FILTER (WHERE tipo = 'mensaje_saliente'),
    max(ocurrido_at) FILTER (WHERE tipo = 'mensaje_entrante'),
    round(extract(epoch FROM (now() - crm.esperando_desde(p_contacto_id))))::bigint,
    count(*) FILTER (WHERE tipo = 'visita_agendada'),
    count(*) FILTER (WHERE tipo = 'visita_realizada'),
    count(*) FILTER (WHERE tipo = 'visita_cancelada'),
    count(*) FILTER (WHERE tipo = 'solicitud_apertura'),
    (SELECT COALESCE(array_agg(DISTINCT i.titulo), ARRAY[]::text[])
       FROM act a2 JOIN public.inmuebles i ON i.id = a2.inmueble_id),
    count(*),
    count(*) FILTER (
      WHERE ocurrido_at > COALESCE((SELECT visto_hasta FROM leido), '-infinity'::timestamptz)
    ),
    (SELECT visto_hasta FROM leido)
  FROM act;
$resumen$;

COMMENT ON FUNCTION crm.resumen_contacto(uuid) IS
  'Hechos duros de un contacto, contados con SQL. esperando_segundos sale de crm.esperando_desde.';

GRANT EXECUTE ON FUNCTION crm.resumen_contacto(uuid) TO authenticated;
