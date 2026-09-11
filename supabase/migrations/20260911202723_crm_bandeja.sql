-- =====================================================================
-- crm.bandeja_contactos — la consulta que sirve la pantalla principal.
--
-- Toda la lógica de la lista vive aquí y no en la aplicación: filtros,
-- búsqueda y paginación. Así se puede probar con pgTAP, y la interfaz se
-- limita a pasar parámetros y pintar.
--
-- SEGURIDAD: es SECURITY INVOKER (el modo por defecto), así que la RLS de
-- crm.contactos se aplica con el token de quien consulta. Una función de
-- búsqueda con SECURITY DEFINER sería una fuga de datos con formulario.
-- =====================================================================

-- El orden de la bandeja. El coalesce es deliberado: sin él, los
-- contactos sin actividad caen al fondo con NULL y la paginación por
-- cursor se llena de casos especiales. Con él el orden es total.
CREATE INDEX contactos_bandeja
  ON crm.contactos ((COALESCE(ultima_actividad_at, created_at)) DESC, id DESC)
  WHERE deleted_at IS NULL;

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
  n_actividades bigint
)
LANGUAGE sql STABLE SET search_path = ''
AS $funcion$
  SELECT
    c.id, c.nombre, c.telefono_e164, c.telefono_crudo, c.tipo, c.origen,
    c.asesor_id, c.ultima_actividad_at,
    COALESCE(c.ultima_actividad_at, c.created_at) AS orden_at,
    (SELECT count(*) FROM crm.actividades a WHERE a.contacto_id = c.id) AS n_actividades
  FROM crm.contactos c
  WHERE c.deleted_at IS NULL

    AND (p_tipo IS NULL OR c.tipo = p_tipo)

    -- La bandeja de los que no se pueden llamar: hoy son 226 personas
    -- reales sin teléfono utilizable. Merecen un filtro propio.
    AND (p_sin_telefono IS NULL
         OR (p_sin_telefono     AND c.telefono_e164 IS NULL)
         OR (NOT p_sin_telefono AND c.telefono_e164 IS NOT NULL))

    -- Buscar un nombre y buscar un teléfono son dos problemas distintos.
    --
    -- POR NOMBRE: subcadena SIN ACENTOS. Es el fallo real y frecuente
    -- aquí — "Gomez" tiene que encontrar a "Gómez", "Velez" a "Vélez"—, y
    -- unaccent lo resuelve de forma determinista, sin umbrales.
    -- Se añade strict_word_similarity con umbral 0.3 para erratas leves.
    --
    -- El umbral está MEDIDO, no elegido a ojo: con 0.3 entran los seis
    -- aciertos de prueba y quedan fuera los falsos positivos. Lo que NO
    -- se puede es tolerar transposiciones ("Jhon" por "John"): puntúan
    -- 0.111, por debajo de ruido como "Ana"→"Pedro Arango" (0.100). No
    -- hay umbral que separe eso, y en un CRM mostrar a la persona
    -- equivocada es peor que no encontrarla: se prefiere precisión.
    --
    -- Nota de rendimiento: envolver el nombre en unaccent() impide usar
    -- el índice de trigramas. Con mil contactos da igual; cuando sean
    -- cien mil, la solución es una columna generada ya sin acentos con su
    -- propio índice.
    --
    -- POR TELÉFONO: comparando solo dígitos, porque nadie lo escribe con
    -- el mismo formato con que quedó guardado.
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

    -- Paginación por CURSOR, no por desplazamiento. Con offset las
    -- páginas lejanas se vuelven lentas y los registros "saltan" si
    -- alguien inserta mientras navegas. La comparación va por tupla
    -- (fecha, id) para que dos contactos con la misma fecha no se pisen.
    AND (p_cursor_at IS NULL
         OR (COALESCE(c.ultima_actividad_at, c.created_at), c.id)
            < (p_cursor_at, p_cursor_id))

  ORDER BY COALESCE(c.ultima_actividad_at, c.created_at) DESC, c.id DESC
  LIMIT least(COALESCE(p_limite, 50), 200);
$funcion$;

COMMENT ON FUNCTION crm.bandeja_contactos(text, text, boolean, timestamptz, uuid, int) IS
  'Lista de contactos con filtros, busqueda y paginacion por cursor. SECURITY INVOKER: la RLS aplica con el token de quien consulta.';

GRANT EXECUTE ON FUNCTION crm.bandeja_contactos(text, text, boolean, timestamptz, uuid, int)
  TO authenticated;

-- ---------------------------------------------------------------------
-- El timeline de una ficha, con el inmueble resuelto cuando lo hay.
-- ---------------------------------------------------------------------
CREATE VIEW crm.v_timeline WITH (security_invoker = true) AS
  SELECT
    a.id,
    a.inmobiliaria_id,
    a.contacto_id,
    a.tipo,
    a.origen,
    a.cuerpo,
    a.ocurrido_at,
    a.metadata,
    a.inmueble_id,
    i.titulo AS inmueble_titulo,
    i.barrio AS inmueble_barrio
  FROM crm.actividades a
  LEFT JOIN public.inmuebles i ON i.id = a.inmueble_id;

GRANT SELECT ON crm.v_timeline TO authenticated;
