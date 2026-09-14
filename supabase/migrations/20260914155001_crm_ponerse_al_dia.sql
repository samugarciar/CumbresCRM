-- =====================================================================
-- "Ponerse al día" — la capa determinista.
--
-- EL PROBLEMA QUE RESUELVE
-- Cuando un asesor abre una ficha, normalmente ya hay una conversación de
-- decenas de mensajes que él no tuvo: la tuvo el bot. El timeline más
-- largo de producción tiene 95 hechos. Sin ayuda, el costo de arranque
-- —leerse todo para saber qué pasa— es el verdadero cuello de botella, y
-- una herramienta que cuesta arrancar no se usa.
--
-- POR QUÉ ESTA CAPA ES DETERMINISTA Y NO LLEVA IA
-- Son hechos contados con SQL: cuántos mensajes, qué visitas, qué
-- inmuebles, cuánto lleva esperando. Cero riesgo de alucinación y cero
-- costo por apertura.
--
-- El resumen redactado por el agente vendrá después, y cuando venga debe
-- generarse EN EL MOMENTO DE ESCALAR y guardarse inmutable — no al abrir
-- la ficha. Un resumen que cambia cada vez que lo miras destruye la
-- confianza, y además cobra latencia en cada apertura.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Hasta dónde ha leído cada persona
-- ---------------------------------------------------------------------
CREATE TABLE crm.lecturas (
  contacto_id     uuid NOT NULL REFERENCES crm.contactos(id) ON DELETE CASCADE,
  usuario_id      uuid NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
  inmobiliaria_id uuid NOT NULL REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,
  visto_hasta     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (contacto_id, usuario_id)
);

CREATE INDEX lecturas_usuario ON crm.lecturas (usuario_id, contacto_id);

ALTER TABLE crm.lecturas ENABLE ROW LEVEL SECURITY;

-- Cada quien ve y escribe SOLO sus propias marcas de lectura. Que un
-- asesor viera las de otro no aportaría nada y sería un dato de más.
CREATE POLICY lecturas_propias ON crm.lecturas
  FOR ALL TO authenticated
  USING (usuario_id = (SELECT auth.uid()))
  WITH CHECK (
    usuario_id = (SELECT auth.uid())
    AND inmobiliaria_id = public.get_my_inmobiliaria()
  );

COMMENT ON TABLE crm.lecturas IS
  'Hasta dónde ha leído cada usuario el historial de cada contacto. Alimenta el "nuevo desde tu última visita".';

-- ---------------------------------------------------------------------
-- 2. Marcar como leído
--
-- Se llama al abrir una ficha. Es un upsert, así que llamarlo muchas
-- veces no hace daño.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.marcar_leido(p_contacto_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $marcar$
DECLARE
  v_org uuid;
BEGIN
  -- Se toma del contacto, no de un parámetro: así no hay forma de marcar
  -- como leído algo de otra inmobiliaria.
  SELECT c.inmobiliaria_id INTO v_org
    FROM crm.contactos c WHERE c.id = p_contacto_id;

  IF v_org IS NULL THEN
    RETURN;   -- no existe, o la RLS no lo deja ver. En ambos casos, nada que hacer.
  END IF;

  INSERT INTO crm.lecturas (contacto_id, usuario_id, inmobiliaria_id, visto_hasta)
  VALUES (p_contacto_id, (SELECT auth.uid()), v_org, now())
  ON CONFLICT (contacto_id, usuario_id)
  DO UPDATE SET visto_hasta = now();
END $marcar$;

GRANT EXECUTE ON FUNCTION crm.marcar_leido(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 3. Los hechos duros de un contacto
--
-- Lo que un asesor necesita saber en cuatro segundos, antes de decidir
-- si se lee la conversación entera.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.resumen_contacto(p_contacto_id uuid)
RETURNS TABLE (
  mensajes_cliente      bigint,
  mensajes_bot          bigint,
  ultimo_del_cliente_at timestamptz,
  -- Segundos que lleva esperando: desde su último mensaje, si NADIE del
  -- equipo ha escrito después. NULL si ya le respondió una persona.
  --
  -- Es el sustituto honesto de "tiempo desde la escalada": el
  -- escalamiento no deja rastro en nuestra base —vive en n8n y Kommo—
  -- pero "escribió y nadie humano ha contestado" es la misma pregunta
  -- respondida con datos que sí tenemos.
  esperando_segundos    bigint,
  visitas_agendadas     bigint,
  visitas_realizadas    bigint,
  visitas_canceladas    bigint,
  solicitudes_horario   bigint,
  inmuebles             text[],
  actividades_total     bigint,
  sin_leer              bigint,
  -- Hasta dónde había leído esta persona ANTES de abrir la ficha. Es lo
  -- que permite dibujar el separador "nuevo desde tu última visita" en el
  -- sitio exacto del historial.
  visto_hasta           timestamptz
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $resumen$
  WITH act AS (
    SELECT a.* FROM crm.actividades a WHERE a.contacto_id = p_contacto_id
  ),
  ultimo_entrante AS (
    SELECT max(ocurrido_at) t FROM act WHERE tipo = 'mensaje_entrante'
  ),
  respuesta_humana AS (
    -- Una persona del equipo respondió si hay actividad de origen humano
    -- posterior al último mensaje del cliente. Los mensajes salientes son
    -- del bot (origen = 'agente_ia'), así que no cuentan.
    SELECT EXISTS (
      SELECT 1 FROM act
       WHERE origen = 'humano'
         AND ocurrido_at > COALESCE((SELECT t FROM ultimo_entrante), '-infinity'::timestamptz)
    ) AS hubo
  ),
  leido AS (
    SELECT l.visto_hasta FROM crm.lecturas l
     WHERE l.contacto_id = p_contacto_id
       AND l.usuario_id = (SELECT auth.uid())
  )
  SELECT
    count(*) FILTER (WHERE tipo = 'mensaje_entrante'),
    count(*) FILTER (WHERE tipo = 'mensaje_saliente'),
    (SELECT t FROM ultimo_entrante),
    CASE WHEN (SELECT hubo FROM respuesta_humana) THEN NULL
         ELSE round(extract(epoch FROM (now() - (SELECT t FROM ultimo_entrante))))::bigint
    END,
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
  'Hechos duros de un contacto, contados con SQL. Sin IA: cero alucinación y cero costo por apertura.';

GRANT EXECUTE ON FUNCTION crm.resumen_contacto(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 4. La bandeja aprende a contar lo no leído
--
-- Mismo cuerpo que en 20260911202723_crm_bandeja.sql —donde está toda la
-- documentación de los filtros, la búsqueda y el cursor— con una columna
-- nueva al final.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS crm.bandeja_contactos(text, text, boolean, timestamptz, uuid, int);

CREATE OR REPLACE FUNCTION crm.bandeja_contactos(
  p_texto        text        DEFAULT NULL,
  p_tipo         text        DEFAULT NULL,
  p_sin_telefono boolean     DEFAULT NULL,
  p_cursor_at    timestamptz DEFAULT NULL,
  p_cursor_id    uuid        DEFAULT NULL,
  p_limite       int         DEFAULT 50
)
RETURNS TABLE (
  id uuid,
  nombre text,
  telefono_e164 text,
  telefono_crudo text,
  tipo text,
  origen text,
  asesor_id uuid,
  ultima_actividad_at timestamptz,
  orden_at timestamptz,
  n_actividades bigint,
  sin_leer bigint
)
LANGUAGE sql STABLE SET search_path = ''
AS $funcion$
  SELECT
    c.id, c.nombre, c.telefono_e164, c.telefono_crudo, c.tipo, c.origen,
    c.asesor_id, c.ultima_actividad_at,
    COALESCE(c.ultima_actividad_at, c.created_at) AS orden_at,
    (SELECT count(*) FROM crm.actividades a WHERE a.contacto_id = c.id) AS n_actividades,
    (SELECT count(*) FROM crm.actividades a
      WHERE a.contacto_id = c.id
        AND a.ocurrido_at > COALESCE(l.visto_hasta, '-infinity'::timestamptz)) AS sin_leer
  FROM crm.contactos c
  LEFT JOIN crm.lecturas l
    ON l.contacto_id = c.id AND l.usuario_id = (SELECT auth.uid())
  WHERE c.deleted_at IS NULL

    AND (p_tipo IS NULL OR c.tipo = p_tipo)

    AND (p_sin_telefono IS NULL
         OR (p_sin_telefono     AND c.telefono_e164 IS NULL)
         OR (NOT p_sin_telefono AND c.telefono_e164 IS NOT NULL))

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

    AND (p_cursor_at IS NULL
         OR (COALESCE(c.ultima_actividad_at, c.created_at), c.id)
            < (p_cursor_at, p_cursor_id))

  ORDER BY COALESCE(c.ultima_actividad_at, c.created_at) DESC, c.id DESC
  LIMIT least(COALESCE(p_limite, 50), 200);
$funcion$;

GRANT EXECUTE ON FUNCTION crm.bandeja_contactos(text, text, boolean, timestamptz, uuid, int)
  TO authenticated;
