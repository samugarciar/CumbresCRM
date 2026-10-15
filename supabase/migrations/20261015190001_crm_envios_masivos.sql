-- =====================================================================
-- Envíos masivos por WhatsApp (15 oct 2026)
--
-- EL CASO QUE LO TRAE
-- Cartera (otro departamento) ya sabe a quién hay que recordarle un pago.
-- Exporta un archivo; alguien del equipo lo sube al CRM, lo revisa y lo
-- lanza; el CRM manda una plantilla de WhatsApp a cada fila por la línea
-- administrativa, recoge las respuestas en la bandeja del 320 y le
-- devuelve a cartera el mismo archivo con lo que pasó con cada mensaje.
--
-- LAS PIEZAS
--  · crm.envios_masivos: el lote (archivo, plantilla, línea, ritmo).
--  · crm.envios_masivos_destinatarios: una fila por fila del archivo, con
--    lo que se le va a decir y por qué se excluyó si se excluyó.
--  · crm.envios gana envio_masivo_id: cada mensaje que sale es un envío
--    normal, con sus acuses de Meta (registrar_estado_envio) como todos.
--  · Un despachador en la base (pg_cron + pg_net) que, cada minuto, toma
--    el siguiente lote de cada envío en curso, dentro de su horario y del
--    tope diario de la línea, y se lo pide a la plataforma por la misma
--    ruta que usan los envíos sueltos (contrato C1).
--
-- POR QUÉ EL DESPACHADOR VIVE EN LA BASE
-- Un envío de 300 personas dura horas (lotes de 100 cada 30 minutos). El
-- CRM está en Vercel Hobby, donde un cron corre una vez al día, y no
-- tiene la llave de servicio. La base ya agenda con pg_cron; pg_net le
-- deja hacer la petición HTTP. El token del CRM y la URL de la
-- plataforma viven en Vault (crm_envio_token, crm_plataforma_url), como
-- los tokens de las líneas.
--
-- LAS REGLAS QUE NO SE NEGOCIAN
--  · Las funciones de pantalla corren con la sesión de quien llama
--    (SECURITY INVOKER), como todo en crm: lo decide la RLS. Y como la
--    RLS no distingue «cambiar el estado» de «cambiar el nombre», las dos
--    tablas solo se tocan desde sus funciones: un disparador lo exige.
--  · Una persona que pidió no recibir más mensajes no recibe nada. Una que
--    recibió otro envío masivo hace menos de N días (7 por defecto),
--    tampoco: la Ley 2300 de 2023 limita la frecuencia de la cobranza, y
--    sus cifras exactas las confirma el abogado.
--  · Fuera del horario no sale nada: lunes a viernes de 8 a 18, sábados
--    de 8 a 13, nunca domingos ni festivos. Se puede ajustar por envío.
--  · Las filas originales del archivo se borran a los 90 días: traen
--    deudas de personas.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0 · pg_net: la base puede pedirle cosas a la plataforma por HTTP
--
-- En el esquema extensions, no en public. Sus funciones viven en `net`.
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ---------------------------------------------------------------------
-- 1 · Las variables de cartera
--
-- No salen del CRM: salen del archivo de un envío masivo. En un envío
-- suelto quedan sin dato, y la ficha no deja mandar la plantilla.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.variables_disponibles()
RETURNS text[]
LANGUAGE sql IMMUTABLE SET search_path = ''
AS $vd$
  SELECT ARRAY[
    'nombre',        -- de la persona
    'telefono',
    'asesor',        -- quien manda
    'inmueble',      -- título
    'barrio',
    'ciudad',
    'precio',
    'habitaciones',
    -- De cartera: vienen del archivo de un envío masivo
    'monto',
    'fecha_limite',
    'dias_mora',
    'referencia'
  ];
$vd$;

CREATE OR REPLACE FUNCTION crm.hueco_variable(p_variable text)
RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = ''
AS $hv$
  SELECT CASE p_variable
    WHEN 'nombre'       THEN '[sin nombre]'
    WHEN 'telefono'     THEN '[sin teléfono]'
    WHEN 'asesor'       THEN '[asesor]'
    WHEN 'inmueble'     THEN '[sin inmueble]'
    WHEN 'barrio'       THEN '[sin barrio]'
    WHEN 'ciudad'       THEN '[sin ciudad]'
    WHEN 'precio'       THEN '[sin precio]'
    WHEN 'habitaciones' THEN '[sin dato]'
    WHEN 'monto'        THEN '[sin monto]'
    WHEN 'fecha_limite' THEN '[sin fecha límite]'
    WHEN 'dias_mora'    THEN '[sin días de mora]'
    WHEN 'referencia'   THEN '[sin referencia]'
    ELSE '[sin ' || replace(p_variable, '_', ' ') || ']'
  END;
$hv$;

-- ---------------------------------------------------------------------
-- 2 · Cuándo se puede escribir
-- ---------------------------------------------------------------------
CREATE TABLE crm.festivos (
  fecha  date PRIMARY KEY,
  nombre text NOT NULL CHECK (btrim(nombre) <> '')
);

COMMENT ON TABLE crm.festivos IS
  'Festivos de Colombia (Ley Emiliani y Semana Santa). Un envío masivo no sale en festivo. Hay que añadir los de 2029 antes de que lleguen.';

ALTER TABLE crm.festivos ENABLE ROW LEVEL SECURITY;
CREATE POLICY festivos_select ON crm.festivos
  FOR SELECT TO authenticated USING (true);
REVOKE ALL ON crm.festivos FROM anon, authenticated;
GRANT SELECT ON crm.festivos TO authenticated;

INSERT INTO crm.festivos (fecha, nombre) VALUES
  ('2026-01-01', 'Año Nuevo'),
  ('2026-01-12', 'Día de los Reyes Magos'),
  ('2026-03-23', 'Día de San José'),
  ('2026-04-02', 'Jueves Santo'),
  ('2026-04-03', 'Viernes Santo'),
  ('2026-05-01', 'Día del Trabajo'),
  ('2026-05-18', 'Ascensión del Señor'),
  ('2026-06-08', 'Corpus Christi'),
  ('2026-06-15', 'Sagrado Corazón'),
  ('2026-06-29', 'San Pedro y San Pablo'),
  ('2026-07-20', 'Día de la Independencia'),
  ('2026-08-07', 'Batalla de Boyacá'),
  ('2026-08-17', 'La Asunción de la Virgen'),
  ('2026-10-12', 'Día de la Raza'),
  ('2026-11-02', 'Todos los Santos'),
  ('2026-11-16', 'Independencia de Cartagena'),
  ('2026-12-08', 'Inmaculada Concepción'),
  ('2026-12-25', 'Navidad'),
  ('2027-01-01', 'Año Nuevo'),
  ('2027-01-11', 'Día de los Reyes Magos'),
  ('2027-03-22', 'Día de San José'),
  ('2027-03-25', 'Jueves Santo'),
  ('2027-03-26', 'Viernes Santo'),
  ('2027-05-01', 'Día del Trabajo'),
  ('2027-05-10', 'Ascensión del Señor'),
  ('2027-05-31', 'Corpus Christi'),
  ('2027-06-07', 'Sagrado Corazón'),
  ('2027-07-05', 'San Pedro y San Pablo'),
  ('2027-07-20', 'Día de la Independencia'),
  ('2027-08-07', 'Batalla de Boyacá'),
  ('2027-08-16', 'La Asunción de la Virgen'),
  ('2027-10-18', 'Día de la Raza'),
  ('2027-11-01', 'Todos los Santos'),
  ('2027-11-15', 'Independencia de Cartagena'),
  ('2027-12-08', 'Inmaculada Concepción'),
  ('2027-12-25', 'Navidad'),
  ('2028-01-01', 'Año Nuevo'),
  ('2028-01-10', 'Día de los Reyes Magos'),
  ('2028-03-20', 'Día de San José'),
  ('2028-04-13', 'Jueves Santo'),
  ('2028-04-14', 'Viernes Santo'),
  ('2028-05-01', 'Día del Trabajo'),
  ('2028-05-29', 'Ascensión del Señor'),
  ('2028-06-19', 'Corpus Christi'),
  ('2028-06-26', 'Sagrado Corazón'),
  ('2028-07-03', 'San Pedro y San Pablo'),
  ('2028-07-20', 'Día de la Independencia'),
  ('2028-08-07', 'Batalla de Boyacá'),
  ('2028-08-21', 'La Asunción de la Virgen'),
  ('2028-10-16', 'Día de la Raza'),
  ('2028-11-06', 'Todos los Santos'),
  ('2028-11-13', 'Independencia de Cartagena'),
  ('2028-12-08', 'Inmaculada Concepción'),
  ('2028-12-25', 'Navidad');

-- El horario de un envío: zona horaria y, por día ISO (1 = lunes,
-- 7 = domingo), la franja [desde, hasta). Un día que no está, no se envía.
CREATE OR REPLACE FUNCTION crm.horario_valido(p_horario jsonb)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE SET search_path = ''
AS $hv$
DECLARE
  v_dia    text;
  v_franja jsonb;
BEGIN
  IF jsonb_typeof(p_horario) IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_horario -> 'zona') IS DISTINCT FROM 'string'
     OR jsonb_typeof(p_horario -> 'franjas') IS DISTINCT FROM 'object' THEN
    RETURN false;
  END IF;

  FOR v_dia, v_franja IN SELECT * FROM jsonb_each(p_horario -> 'franjas') LOOP
    IF v_dia NOT IN ('1', '2', '3', '4', '5', '6', '7')
       OR jsonb_typeof(v_franja) IS DISTINCT FROM 'array'
       OR jsonb_array_length(v_franja) <> 2
       OR NOT ((v_franja ->> 0) ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')
       OR NOT ((v_franja ->> 1) ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')
       OR (v_franja ->> 0) >= (v_franja ->> 1) THEN
      RETURN false;
    END IF;
  END LOOP;

  RETURN true;
END $hv$;

CREATE OR REPLACE FUNCTION crm.en_horario_envio(
  p_horario jsonb,
  p_momento timestamptz DEFAULT now())
RETURNS boolean
LANGUAGE plpgsql STABLE SET search_path = ''
AS $eh$
DECLARE
  v_local  timestamp;
  v_franja jsonb;
BEGIN
  IF NOT crm.horario_valido(p_horario) THEN
    RETURN false;
  END IF;

  v_local  := p_momento AT TIME ZONE (p_horario ->> 'zona');
  v_franja := p_horario -> 'franjas' -> (extract(isodow FROM v_local)::int::text);

  IF v_franja IS NULL
     OR EXISTS (SELECT 1 FROM crm.festivos f WHERE f.fecha = v_local::date) THEN
    RETURN false;
  END IF;

  RETURN v_local::time >= (v_franja ->> 0)::time
     AND v_local::time <  (v_franja ->> 1)::time;
END $eh$;

COMMENT ON FUNCTION crm.en_horario_envio(jsonb, timestamptz) IS
  '¿Se puede escribir en este momento según el horario de un envío masivo? Nunca en festivo.';

GRANT EXECUTE ON FUNCTION crm.horario_valido(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION crm.en_horario_envio(jsonb, timestamptz) TO authenticated;

-- ---------------------------------------------------------------------
-- 3 · Las tablas
-- ---------------------------------------------------------------------
CREATE TABLE crm.envios_masivos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inmobiliaria_id uuid NOT NULL
    REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,

  nombre text NOT NULL CHECK (btrim(nombre) <> '' AND length(nombre) <= 120),
  archivo_nombre text CHECK (archivo_nombre IS NULL OR length(archivo_nombre) <= 255),

  -- Cómo se lee el archivo: sus encabezados y de cuál sale cada cosa.
  columnas text[] NOT NULL CHECK (cardinality(columnas) BETWEEN 1 AND 100),
  columna_telefono text NOT NULL,
  columna_nombre text,
  -- variable de la plantilla → encabezado del archivo
  variables jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(variables) = 'object'),

  plantilla_id uuid NOT NULL REFERENCES crm.plantillas(id),
  wa_phone_number_id text NOT NULL,
  -- Abrir (o mover a «En mora») el caso administrativo de cada persona.
  abrir_caso boolean NOT NULL DEFAULT false,

  estado text NOT NULL DEFAULT 'borrador'
    CHECK (estado IN ('borrador', 'en_curso', 'pausado', 'terminado', 'cancelado')),

  -- El ritmo. Por lotes y no de golpe: la nota 7 del vault explica los
  -- tres frenos de Meta (tope diario, calidad, marketing por usuario).
  tamano_lote         int NOT NULL DEFAULT 100 CHECK (tamano_lote BETWEEN 1 AND 250),
  minutos_entre_lotes int NOT NULL DEFAULT 30  CHECK (minutos_entre_lotes BETWEEN 1 AND 1440),
  tope_diario         int NOT NULL DEFAULT 250 CHECK (tope_diario BETWEEN 1 AND 100000),
  frecuencia_dias     int NOT NULL DEFAULT 7   CHECK (frecuencia_dias BETWEEN 0 AND 90),
  horario jsonb NOT NULL DEFAULT '{
      "zona": "America/Bogota",
      "franjas": {
        "1": ["08:00", "18:00"], "2": ["08:00", "18:00"], "3": ["08:00", "18:00"],
        "4": ["08:00", "18:00"], "5": ["08:00", "18:00"], "6": ["08:00", "13:00"]
      }
    }'::jsonb
    CHECK (crm.horario_valido(horario)),

  proximo_lote_at timestamptz,
  -- Lo último que el despachador quiere que alguien sepa («se pausó porque…»).
  ultimo_aviso text,

  creado_por  uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,
  lanzado_por uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,
  lanzado_at   timestamptz,
  terminado_at timestamptz,
  datos_borrados_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT envios_masivos_lanzado_con_fecha
    CHECK (estado IN ('borrador', 'cancelado') OR lanzado_at IS NOT NULL)
);

COMMENT ON TABLE crm.envios_masivos IS
  'Un envío masivo por WhatsApp desde un archivo (hoy: recordatorios de cartera). Solo se crea y se mueve con sus funciones.';

CREATE INDEX envios_masivos_por_inmobiliaria ON crm.envios_masivos (inmobiliaria_id, created_at DESC);
CREATE INDEX envios_masivos_en_curso ON crm.envios_masivos (proximo_lote_at) WHERE estado = 'en_curso';

CREATE TABLE crm.envios_masivos_destinatarios (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  envio_masivo_id uuid NOT NULL REFERENCES crm.envios_masivos(id) ON DELETE CASCADE,
  inmobiliaria_id uuid NOT NULL REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,

  -- La fila del archivo, contando el encabezado como la 1: la misma que
  -- ve quien abre el Excel.
  fila int NOT NULL CHECK (fila >= 2),
  datos jsonb,                 -- la fila entera; se borra a los 90 días
  telefono_crudo text,
  telefono_e164 text,
  nombre text,
  valores jsonb NOT NULL DEFAULT '{}'::jsonb,   -- variable → valor, lo que recibe Meta
  cuerpo text,                                   -- lo que va a leer la persona

  contacto_id uuid REFERENCES crm.contactos(id) ON DELETE SET NULL,
  estado text NOT NULL DEFAULT 'listo'
    CHECK (estado IN ('listo', 'excluido', 'encolado', 'cancelado')),
  motivo text CHECK (motivo IN (
    'sin_telefono', 'telefono_invalido', 'repetido', 'faltan_datos',
    'baja', 'frecuencia', 'cancelado')),
  detalle text,
  envio_id uuid REFERENCES crm.envios(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (envio_masivo_id, fila),
  CONSTRAINT destinatarios_motivo_si_no_sale
    CHECK ((estado IN ('excluido', 'cancelado')) = (motivo IS NOT NULL))
);

COMMENT ON TABLE crm.envios_masivos_destinatarios IS
  'Una fila por fila del archivo de un envío masivo: qué se le dice, a qué contacto, y por qué no salió si no salió.';

CREATE INDEX destinatarios_en_cola ON crm.envios_masivos_destinatarios (envio_masivo_id, fila) WHERE estado = 'listo';
CREATE INDEX destinatarios_contacto ON crm.envios_masivos_destinatarios (contacto_id) WHERE contacto_id IS NOT NULL;
CREATE INDEX destinatarios_envio ON crm.envios_masivos_destinatarios (envio_id) WHERE envio_id IS NOT NULL;

-- Cada mensaje que sale es un envío normal, con sus acuses.
ALTER TABLE crm.envios
  ADD COLUMN envio_masivo_id uuid REFERENCES crm.envios_masivos(id) ON DELETE SET NULL,
  ADD COLUMN variables jsonb,
  ADD COLUMN tomado_at timestamptz,
  ADD COLUMN solicitud_http bigint;

COMMENT ON COLUMN crm.envios.variables IS
  'Los parámetros con nombre que se le mandaron a Meta con la plantilla.';
COMMENT ON COLUMN crm.envios.tomado_at IS
  'Cuándo lo tomó el despachador de envíos masivos. Tomado no se vuelve a mandar: el cliente lo recibiría dos veces.';
COMMENT ON COLUMN crm.envios.solicitud_http IS
  'La petición de pg_net a la plataforma (net._http_response.id), para leer qué contestó.';

CREATE INDEX envios_masivo ON crm.envios (envio_masivo_id) WHERE envio_masivo_id IS NOT NULL;
CREATE INDEX envios_solicitud_pendiente ON crm.envios (solicitud_http)
  WHERE estado = 'pendiente' AND solicitud_http IS NOT NULL;
CREATE INDEX envios_plantilla_por_linea ON crm.envios (wa_phone_number_id, created_at)
  WHERE plantilla_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- 4 · Solo con sus funciones
--
-- La RLS deja a un asesor actualizar las filas de su inmobiliaria, pero
-- no sabe qué columna toca: con ella sola, cualquiera podría pasar un
-- borrador a «en_curso» desde el navegador sin la confirmación, o colar
-- un envío en la cola del despachador. Las funciones encienden una
-- marca de la transacción; sin ella, el disparador rechaza.
--
-- pg_trigger_depth() = 1: lo que llega por un ON DELETE SET NULL (se
-- borró un contacto o un envío) pasa, porque no lo hizo nadie a mano.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.envios_masivos_solo_por_funciones()
RETURNS trigger
LANGUAGE plpgsql SET search_path = ''
AS $g$
BEGIN
  IF pg_trigger_depth() = 1
     AND current_setting('crm.envios_masivos', true) IS DISTINCT FROM 'si' THEN
    RAISE EXCEPTION 'Los envíos masivos solo se crean y se mueven con sus funciones'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $g$;

CREATE TRIGGER envios_masivos_solo_por_funciones
  BEFORE INSERT OR UPDATE ON crm.envios_masivos
  FOR EACH ROW EXECUTE FUNCTION crm.envios_masivos_solo_por_funciones();

CREATE TRIGGER destinatarios_solo_por_funciones
  BEFORE INSERT OR UPDATE ON crm.envios_masivos_destinatarios
  FOR EACH ROW EXECUTE FUNCTION crm.envios_masivos_solo_por_funciones();

CREATE TRIGGER envios_de_masivo_solo_por_funciones
  BEFORE INSERT OR UPDATE OF envio_masivo_id ON crm.envios
  FOR EACH ROW WHEN (NEW.envio_masivo_id IS NOT NULL)
  EXECUTE FUNCTION crm.envios_masivos_solo_por_funciones();

CREATE TRIGGER envios_masivos_updated_at
  BEFORE UPDATE ON crm.envios_masivos
  FOR EACH ROW EXECUTE FUNCTION crm.tocar_updated_at();

-- ---------------------------------------------------------------------
-- 5 · Quién ve y quién toca
--
-- Todos los de la inmobiliaria ven. Prepara, lanza, pausa y cancela un
-- admin o un asesor (decisión de Samuel, 15 oct). Nadie borra: lo que se
-- mandó a una persona no se deshace, y un borrador se cancela.
-- ---------------------------------------------------------------------
ALTER TABLE crm.envios_masivos ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.envios_masivos_destinatarios ENABLE ROW LEVEL SECURITY;

CREATE POLICY envios_masivos_select ON crm.envios_masivos
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());
CREATE POLICY envios_masivos_insert ON crm.envios_masivos
  FOR INSERT TO authenticated
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria()
              AND public.get_my_role() IN ('admin', 'asesor'));
CREATE POLICY envios_masivos_update ON crm.envios_masivos
  FOR UPDATE TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria()
         AND public.get_my_role() IN ('admin', 'asesor'))
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria()
              AND public.get_my_role() IN ('admin', 'asesor'));

CREATE POLICY destinatarios_select ON crm.envios_masivos_destinatarios
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());
CREATE POLICY destinatarios_insert ON crm.envios_masivos_destinatarios
  FOR INSERT TO authenticated
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria()
              AND public.get_my_role() IN ('admin', 'asesor'));
CREATE POLICY destinatarios_update ON crm.envios_masivos_destinatarios
  FOR UPDATE TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria()
         AND public.get_my_role() IN ('admin', 'asesor'))
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria()
              AND public.get_my_role() IN ('admin', 'asesor'));

REVOKE ALL ON crm.envios_masivos, crm.envios_masivos_destinatarios FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON crm.envios_masivos, crm.envios_masivos_destinatarios TO authenticated;

-- ---------------------------------------------------------------------
-- 6 · Por qué una persona no debe recibirlo
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.motivo_exclusion_contacto(
  p_contacto_id     uuid,
  p_frecuencia_dias int,
  p_envio_masivo_id uuid)
RETURNS text
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $mec$
  SELECT CASE
    WHEN c.opt_out THEN 'baja'
    WHEN p_frecuencia_dias > 0 AND (
           -- Ya le salió uno de otro envío masivo hace poco…
           EXISTS (SELECT 1 FROM crm.envios e
                    WHERE e.contacto_id = c.id
                      AND e.envio_masivo_id IS NOT NULL
                      AND e.envio_masivo_id IS DISTINCT FROM p_envio_masivo_id
                      AND e.estado <> 'fallido'
                      AND e.created_at > now() - make_interval(days => p_frecuencia_dias))
           -- …o está en la cola de otro que sigue andando.
        OR EXISTS (SELECT 1 FROM crm.envios_masivos_destinatarios d
                     JOIN crm.envios_masivos m ON m.id = d.envio_masivo_id
                    WHERE d.contacto_id = c.id
                      AND d.estado = 'listo'
                      AND m.id IS DISTINCT FROM p_envio_masivo_id
                      AND m.estado IN ('en_curso', 'pausado')))
      THEN 'frecuencia'
  END
  FROM crm.contactos c
  WHERE c.id = p_contacto_id;
$mec$;

GRANT EXECUTE ON FUNCTION crm.motivo_exclusion_contacto(uuid, int, uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 7 · Preparar: el archivo se vuelve un borrador revisable
--
-- No crea contactos todavía: un borrador que se descarta no debe dejar
-- gente nueva en el CRM. Solo reconoce a los que ya existen, para poder
-- avisar desde ya de las bajas y de la frecuencia.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.crear_envio_masivo(
  p_nombre           text,
  p_archivo_nombre   text,
  p_columnas         text[],
  p_filas            jsonb,
  p_columna_telefono text,
  p_columna_nombre   text,
  p_plantilla_id     uuid,
  p_variables        jsonb,
  p_abrir_caso       boolean)
RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = ''
AS $cem$
DECLARE
  v_org         uuid := public.get_my_inmobiliaria();
  v_max_filas   constant int := 5000;
  v_plantilla   record;
  v_linea       record;
  v_usadas      text[];
  v_sin_columna text[];
  v_frecuencia  int;
  v_id          uuid;
BEGIN
  IF v_org IS NULL OR COALESCE(public.get_my_role(), '') NOT IN ('admin', 'asesor') THEN
    RAISE EXCEPTION 'Solo un administrador o un asesor prepara envíos masivos'
      USING ERRCODE = '42501';
  END IF;

  PERFORM set_config('crm.envios_masivos', 'si', true);

  -- Sin columna de nombre llega vacía o nula: es lo mismo.
  p_columna_nombre := NULLIF(btrim(p_columna_nombre), '');

  IF btrim(COALESCE(p_nombre, '')) = '' THEN
    RAISE EXCEPTION 'El envío necesita un nombre' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_filas) IS DISTINCT FROM 'array' OR jsonb_array_length(p_filas) = 0 THEN
    RAISE EXCEPTION 'El archivo no tiene filas' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_filas) > v_max_filas THEN
    RAISE EXCEPTION 'Son % filas: el máximo por envío es %. Pártelo en varios.',
      jsonb_array_length(p_filas), v_max_filas USING ERRCODE = '22023';
  END IF;
  IF p_columna_telefono IS NULL OR NOT (p_columna_telefono = ANY (p_columnas)) THEN
    RAISE EXCEPTION 'Elige la columna del teléfono' USING ERRCODE = '22023';
  END IF;
  IF p_columna_nombre IS NOT NULL AND NOT (p_columna_nombre = ANY (p_columnas)) THEN
    RAISE EXCEPTION 'La columna del nombre no está en el archivo' USING ERRCODE = '22023';
  END IF;

  SELECT p.id, p.cuerpo, p.tipo, p.wa_phone_number_id INTO v_plantilla
    FROM crm.plantillas p WHERE p.id = p_plantilla_id AND p.activa;
  IF v_plantilla.id IS NULL OR v_plantilla.tipo <> 'whatsapp'
     OR v_plantilla.wa_phone_number_id IS NULL THEN
    RAISE EXCEPTION 'Elige una plantilla de WhatsApp de una línea conectada'
      USING ERRCODE = '22023';
  END IF;

  SELECT l.embudo, l.activa INTO v_linea
    FROM crm.lineas l WHERE l.wa_phone_number_id = v_plantilla.wa_phone_number_id;
  IF NOT COALESCE(v_linea.activa, false) THEN
    RAISE EXCEPTION 'La línea de esa plantilla no está activa' USING ERRCODE = '22023';
  END IF;

  -- Cada variable de la plantilla tiene que salir de una columna.
  v_usadas := ARRAY(
    SELECT DISTINCT (regexp_matches(v_plantilla.cuerpo, '\{\{\s*([a-z_]+)\s*\}\}', 'g'))[1]);
  v_sin_columna := ARRAY(
    SELECT u FROM unnest(v_usadas) u
     WHERE NOT (COALESCE(p_variables ->> u, '') = ANY (p_columnas)));
  IF cardinality(v_sin_columna) > 0 THEN
    RAISE EXCEPTION 'Falta decir de qué columna sale: %', array_to_string(v_sin_columna, ', ')
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO crm.envios_masivos
    (inmobiliaria_id, nombre, archivo_nombre, columnas, columna_telefono, columna_nombre,
     variables, plantilla_id, wa_phone_number_id, abrir_caso, creado_por)
  VALUES
    (v_org, btrim(p_nombre), NULLIF(btrim(p_archivo_nombre), ''), p_columnas,
     p_columna_telefono, p_columna_nombre,
     (SELECT COALESCE(jsonb_object_agg(u, p_variables ->> u), '{}'::jsonb) FROM unnest(v_usadas) u),
     v_plantilla.id, v_plantilla.wa_phone_number_id,
     -- El caso administrativo solo tiene sentido en la línea administrativa.
     COALESCE(p_abrir_caso, false) AND v_linea.embudo = 'administrativa',
     (SELECT auth.uid()))
  RETURNING id, frecuencia_dias INTO v_id, v_frecuencia;

  INSERT INTO crm.envios_masivos_destinatarios
    (envio_masivo_id, inmobiliaria_id, fila, datos, telefono_crudo, telefono_e164,
     nombre, valores, cuerpo, contacto_id, estado, motivo, detalle)
  SELECT v_id, v_org, x.fila, x.datos, x.tel_crudo, x.e164, x.nombre, x.valores,
         crm.rellenar_cuerpo(v_plantilla.cuerpo, x.valores),
         x.contacto_id,
         CASE WHEN x.motivo IS NULL THEN 'listo' ELSE 'excluido' END,
         x.motivo,
         CASE x.motivo
           WHEN 'repetido'     THEN 'Mismo teléfono que la fila ' || x.primera_fila
           WHEN 'faltan_datos' THEN 'Sin ' || array_to_string(x.faltan, ', ')
           WHEN 'frecuencia'   THEN 'En los últimos ' || v_frecuencia || ' días'
         END
    FROM (
      SELECT b.*,
             CASE
               WHEN b.tel_crudo IS NULL         THEN 'sin_telefono'
               WHEN b.e164 IS NULL              THEN 'telefono_invalido'
               WHEN b.orden_tel > 1             THEN 'repetido'
               WHEN cardinality(b.faltan) > 0   THEN 'faltan_datos'
               WHEN b.contacto_id IS NOT NULL   THEN
                 crm.motivo_exclusion_contacto(b.contacto_id, v_frecuencia, v_id)
             END AS motivo
        FROM (
          SELECT f.*,
                 row_number()  OVER (PARTITION BY f.e164 ORDER BY f.fila) AS orden_tel,
                 first_value(f.fila) OVER (PARTITION BY f.e164 ORDER BY f.fila) AS primera_fila,
                 (SELECT i.contacto_id FROM crm.identidades i
                   WHERE i.inmobiliaria_id = v_org
                     AND i.tipo = 'telefono_e164'
                     AND i.valor = f.e164
                   LIMIT 1) AS contacto_id
            FROM (
              SELECT (o.n + 1)::int AS fila,
                     o.v AS datos,
                     NULLIF(btrim(o.v ->> p_columna_telefono), '') AS tel_crudo,
                     crm.normalizar_telefono(o.v ->> p_columna_telefono) AS e164,
                     NULLIF(btrim(o.v ->> p_columna_nombre), '') AS nombre,
                     (SELECT COALESCE(jsonb_object_agg(u, NULLIF(btrim(o.v ->> (p_variables ->> u)), '')),
                                      '{}'::jsonb)
                        FROM unnest(v_usadas) u) AS valores,
                     ARRAY(SELECT u FROM unnest(v_usadas) u
                            WHERE NULLIF(btrim(o.v ->> (p_variables ->> u)), '') IS NULL) AS faltan
                FROM jsonb_array_elements(p_filas) WITH ORDINALITY o(v, n)
            ) f
        ) b
    ) x;

  RETURN v_id;
END $cem$;

COMMENT ON FUNCTION crm.crear_envio_masivo(text, text, text[], jsonb, text, text, uuid, jsonb, boolean) IS
  'Convierte las filas de un archivo en un borrador revisable: valida, rellena la plantilla y marca quién no recibiría y por qué. No crea contactos ni manda nada.';

-- ---------------------------------------------------------------------
-- 8 · Ajustar el ritmo y el horario, antes de lanzar o en pausa
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.ajustar_envio_masivo(
  p_id                  uuid,
  p_tamano_lote         int,
  p_minutos_entre_lotes int,
  p_tope_diario         int,
  p_frecuencia_dias     int,
  p_horario             jsonb)
RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = ''
AS $aem$
DECLARE
  v_estado text;
BEGIN
  IF COALESCE(public.get_my_role(), '') NOT IN ('admin', 'asesor') THEN
    RAISE EXCEPTION 'Solo un administrador o un asesor ajusta envíos masivos'
      USING ERRCODE = '42501';
  END IF;

  PERFORM set_config('crm.envios_masivos', 'si', true);

  SELECT m.estado INTO v_estado FROM crm.envios_masivos m WHERE m.id = p_id FOR UPDATE;
  IF v_estado IS NULL THEN
    RAISE EXCEPTION 'Ese envío no existe' USING ERRCODE = '22023';
  END IF;
  IF v_estado NOT IN ('borrador', 'pausado') THEN
    RAISE EXCEPTION 'Solo se ajusta un envío en borrador o en pausa' USING ERRCODE = '22023';
  END IF;
  IF NOT crm.horario_valido(p_horario) THEN
    RAISE EXCEPTION 'Ese horario no es válido' USING ERRCODE = '22023';
  END IF;

  UPDATE crm.envios_masivos
     SET tamano_lote = p_tamano_lote,
         minutos_entre_lotes = p_minutos_entre_lotes,
         tope_diario = p_tope_diario,
         frecuencia_dias = p_frecuencia_dias,
         horario = p_horario
   WHERE id = p_id;
END $aem$;

-- ---------------------------------------------------------------------
-- 9 · Lanzar
--
-- Vuelve a mirar todo lo que pudo cambiar desde el borrador (la
-- plantilla, la línea, las bajas, la frecuencia), pide la confirmación
-- con el número exacto de destinatarios, crea a los que no existían como
-- contactos y les abre el caso. Mandar, manda el despachador.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.lanzar_envio_masivo(p_id uuid, p_confirmacion int)
RETURNS int
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = ''
AS $lem$
DECLARE
  v_org      uuid := public.get_my_inmobiliaria();
  m          record;
  v_plantilla record;
  v_linea    record;
  v_dest     record;
  v_contacto uuid;
  v_op       uuid;
  v_listos   int;
BEGIN
  IF v_org IS NULL OR COALESCE(public.get_my_role(), '') NOT IN ('admin', 'asesor') THEN
    RAISE EXCEPTION 'Solo un administrador o un asesor lanza envíos masivos'
      USING ERRCODE = '42501';
  END IF;

  PERFORM set_config('crm.envios_masivos', 'si', true);

  SELECT * INTO m FROM crm.envios_masivos x WHERE x.id = p_id FOR UPDATE;
  IF m.id IS NULL THEN
    RAISE EXCEPTION 'Ese envío no existe' USING ERRCODE = '22023';
  END IF;
  IF m.estado <> 'borrador' THEN
    RAISE EXCEPTION 'Ese envío ya se lanzó o se canceló' USING ERRCODE = '22023';
  END IF;

  SELECT p.estado_meta, p.activa, p.wa_phone_number_id INTO v_plantilla
    FROM crm.plantillas p WHERE p.id = m.plantilla_id;
  IF NOT COALESCE(v_plantilla.activa, false) OR v_plantilla.estado_meta IS DISTINCT FROM 'aprobada' THEN
    RAISE EXCEPTION 'La plantilla todavía no está aprobada por Meta' USING ERRCODE = '22023';
  END IF;
  IF v_plantilla.wa_phone_number_id IS DISTINCT FROM m.wa_phone_number_id THEN
    RAISE EXCEPTION 'La plantilla ya no es de la línea de este envío' USING ERRCODE = '22023';
  END IF;

  SELECT l.activa, l.token_invalido_at INTO v_linea
    FROM crm.lineas l WHERE l.wa_phone_number_id = m.wa_phone_number_id;
  IF NOT COALESCE(v_linea.activa, false) THEN
    RAISE EXCEPTION 'La línea de este envío no está activa' USING ERRCODE = '22023';
  END IF;
  IF v_linea.token_invalido_at IS NOT NULL THEN
    RAISE EXCEPTION 'Meta rechaza la credencial de la línea: hay que reconectarla antes de enviar'
      USING ERRCODE = '22023';
  END IF;

  -- 1 · Los que ya existían en el CRM, por su teléfono.
  UPDATE crm.envios_masivos_destinatarios d
     SET contacto_id = i.contacto_id
    FROM crm.identidades i
   WHERE d.envio_masivo_id = p_id
     AND d.estado = 'listo'
     AND d.contacto_id IS NULL
     AND i.inmobiliaria_id = v_org
     AND i.tipo = 'telefono_e164'
     AND i.valor = d.telefono_e164;

  -- 2 · Lo que pudo cambiar desde el borrador: una baja, otro envío.
  UPDATE crm.envios_masivos_destinatarios d
     SET estado  = 'excluido',
         motivo  = x.motivo,
         detalle = CASE x.motivo WHEN 'frecuencia' THEN 'En los últimos ' || m.frecuencia_dias || ' días' END
    FROM (SELECT y.id, crm.motivo_exclusion_contacto(y.contacto_id, m.frecuencia_dias, p_id) AS motivo
            FROM crm.envios_masivos_destinatarios y
           WHERE y.envio_masivo_id = p_id AND y.estado = 'listo' AND y.contacto_id IS NOT NULL) x
   WHERE d.id = x.id AND x.motivo IS NOT NULL;

  -- 3 · La confirmación: el número exacto, no un «sí».
  SELECT count(*) INTO v_listos
    FROM crm.envios_masivos_destinatarios
   WHERE envio_masivo_id = p_id AND estado = 'listo';
  IF v_listos = 0 THEN
    RAISE EXCEPTION 'No queda nadie a quien enviarle' USING ERRCODE = '22023';
  END IF;
  IF p_confirmacion IS DISTINCT FROM v_listos THEN
    RAISE EXCEPTION 'La confirmación no coincide: son % destinatarios', v_listos
      USING ERRCODE = '22023';
  END IF;

  -- 4 · Los nuevos entran al CRM, con la misma identidad que usa la
  -- proyección: cuando contesten por WhatsApp, caen en este contacto.
  FOR v_dest IN
    SELECT x.id, x.telefono_e164, x.telefono_crudo, x.nombre
      FROM crm.envios_masivos_destinatarios x
     WHERE x.envio_masivo_id = p_id AND x.estado = 'listo' AND x.contacto_id IS NULL
     ORDER BY x.fila
  LOOP
    INSERT INTO crm.contactos (inmobiliaria_id, nombre, origen, tipo, telefono_crudo)
    VALUES (v_org, v_dest.nombre, 'cartera', 'cliente', v_dest.telefono_crudo)
    RETURNING id INTO v_contacto;

    INSERT INTO crm.identidades (inmobiliaria_id, contacto_id, tipo, valor, origen)
    VALUES (v_org, v_contacto, 'telefono_e164', v_dest.telefono_e164, 'cartera');

    UPDATE crm.envios_masivos_destinatarios SET contacto_id = v_contacto WHERE id = v_dest.id;
  END LOOP;

  -- El nombre del archivo, si es mejor que el que había.
  UPDATE crm.contactos c
     SET nombre = crm.mejor_nombre(c.nombre, d.nombre)
    FROM crm.envios_masivos_destinatarios d
   WHERE d.envio_masivo_id = p_id
     AND d.estado = 'listo'
     AND d.contacto_id = c.id
     AND d.nombre IS NOT NULL
     AND crm.mejor_nombre(c.nombre, d.nombre) IS DISTINCT FROM c.nombre;

  -- 5 · El caso administrativo, si se pidió: a quien está al día se le
  -- mueve a «En mora»; a quien no tiene caso, se le abre ahí. Un caso en
  -- acuerdo de pago, mantenimiento o terminación no se toca: lo lleva
  -- alguien del equipo.
  IF m.abrir_caso THEN
    FOR v_op IN
      SELECT o.id
        FROM crm.oportunidades o
        JOIN crm.envios_masivos_destinatarios x ON x.contacto_id = o.contacto_id
       WHERE x.envio_masivo_id = p_id
         AND x.estado = 'listo'
         AND o.estado = 'abierta'
         AND o.embudo = 'administrativa'
         AND o.etapa = 'al_dia'
    LOOP
      PERFORM crm.mover_etapa(v_op, 'en_mora', 'Envío masivo de cartera «' || m.nombre || '»');
    END LOOP;

    FOR v_dest IN
      SELECT DISTINCT x.contacto_id
        FROM crm.envios_masivos_destinatarios x
       WHERE x.envio_masivo_id = p_id
         AND x.estado = 'listo'
         AND NOT EXISTS (SELECT 1 FROM crm.oportunidades o
                          WHERE o.contacto_id = x.contacto_id
                            AND o.estado = 'abierta'
                            AND o.embudo = 'administrativa')
    LOOP
      INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, asesor_id)
      VALUES (v_org, v_dest.contacto_id, 'administrativa', 'en_mora',
              (SELECT c.asesor_id FROM crm.contactos c WHERE c.id = v_dest.contacto_id))
      RETURNING id INTO v_op;

      INSERT INTO crm.transiciones
        (inmobiliaria_id, oportunidad_id, etapa_hasta, estado_hasta, origen, motivo, usuario_id)
      VALUES (v_org, v_op, 'en_mora', 'abierta', 'humano',
              'Caso abierto por el envío masivo de cartera «' || m.nombre || '»',
              (SELECT auth.uid()));

      INSERT INTO crm.actividades
        (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, metadata, creado_por, ocurrido_at)
      VALUES (v_org, 'sistema', 'humano', v_dest.contacto_id,
              'Caso administrativo abierto en «En mora» por el envío masivo «' || m.nombre || '»',
              jsonb_build_object('oportunidad_id', v_op, 'envio_masivo_id', p_id),
              (SELECT auth.uid()), now());
    END LOOP;
  END IF;

  UPDATE crm.envios_masivos
     SET estado = 'en_curso',
         lanzado_por = (SELECT auth.uid()),
         lanzado_at = now(),
         proximo_lote_at = now(),
         ultimo_aviso = NULL
   WHERE id = p_id;

  RETURN v_listos;
END $lem$;

COMMENT ON FUNCTION crm.lanzar_envio_masivo(uuid, int) IS
  'Lanza un borrador: revalida, exige el número exacto de destinatarios, crea los contactos nuevos y abre los casos. Lo manda el despachador, por lotes y en horario.';

-- ---------------------------------------------------------------------
-- 10 · Pausar, reanudar, cancelar
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.cambiar_estado_envio_masivo(p_id uuid, p_accion text)
RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = ''
AS $cee$
DECLARE
  v_estado text;
  v_nuevo  text;
BEGIN
  IF COALESCE(public.get_my_role(), '') NOT IN ('admin', 'asesor') THEN
    RAISE EXCEPTION 'Solo un administrador o un asesor mueve envíos masivos'
      USING ERRCODE = '42501';
  END IF;

  PERFORM set_config('crm.envios_masivos', 'si', true);

  SELECT m.estado INTO v_estado FROM crm.envios_masivos m WHERE m.id = p_id FOR UPDATE;
  IF v_estado IS NULL THEN
    RAISE EXCEPTION 'Ese envío no existe' USING ERRCODE = '22023';
  END IF;

  v_nuevo := CASE
    WHEN p_accion = 'pausar'   AND v_estado = 'en_curso' THEN 'pausado'
    WHEN p_accion = 'reanudar' AND v_estado = 'pausado'  THEN 'en_curso'
    WHEN p_accion = 'cancelar' AND v_estado IN ('borrador', 'en_curso', 'pausado') THEN 'cancelado'
  END;
  IF v_nuevo IS NULL THEN
    RAISE EXCEPTION 'No se puede % un envío que está %', COALESCE(p_accion, '?'), v_estado
      USING ERRCODE = '22023';
  END IF;

  UPDATE crm.envios_masivos
     SET estado = v_nuevo,
         proximo_lote_at = CASE WHEN v_nuevo = 'en_curso' THEN now() ELSE proximo_lote_at END,
         terminado_at    = CASE WHEN v_nuevo = 'cancelado' THEN now() ELSE terminado_at END,
         ultimo_aviso    = CASE WHEN v_nuevo = 'en_curso' THEN NULL ELSE ultimo_aviso END
   WHERE id = p_id;

  -- Lo que no salió se queda sin salir. Lo que ya se mandó, se mandó.
  IF v_nuevo = 'cancelado' THEN
    UPDATE crm.envios_masivos_destinatarios
       SET estado = 'cancelado', motivo = 'cancelado'
     WHERE envio_masivo_id = p_id AND estado = 'listo';
  END IF;

  RETURN v_nuevo;
END $cee$;

-- ---------------------------------------------------------------------
-- 11 · Qué pasó con cada fila, y el resumen
--
-- Es lo que se le devuelve a cartera: la fila original con su estado.
-- «Respondió» es el primer mensaje entrante de esa persona, por esa
-- línea, después de que el recordatorio salió.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.resultados_envio_masivo(p_id uuid)
RETURNS TABLE (
  fila          int,
  datos         jsonb,
  telefono      text,
  nombre        text,
  contacto_id   uuid,
  resultado     text,
  motivo        text,
  detalle       text,
  enviado_at    timestamptz,
  entregado_at  timestamptz,
  leido_at      timestamptz,
  fallido_at    timestamptz,
  error         text,
  error_codigo  int,
  respondio_at  timestamptz,
  baja          boolean
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $rem$
  SELECT d.fila,
         d.datos,
         COALESCE(d.telefono_e164, d.telefono_crudo),
         d.nombre,
         d.contacto_id,
         CASE
           WHEN d.estado IN ('excluido', 'cancelado', 'listo') THEN
             CASE d.estado WHEN 'listo' THEN 'en_cola' ELSE d.estado END
           WHEN e.id IS NULL THEN 'sin_confirmar'
           WHEN e.estado = 'pendiente' AND e.tomado_at < now() - interval '10 minutes' THEN 'sin_confirmar'
           WHEN e.estado = 'pendiente' THEN 'enviando'
           ELSE e.estado
         END,
         d.motivo,
         d.detalle,
         e.enviado_at,
         e.entregado_at,
         e.leido_at,
         e.fallido_at,
         e.error,
         e.error_codigo,
         (SELECT min(a.ocurrido_at)
            FROM crm.actividades a
           WHERE a.contacto_id = d.contacto_id
             AND a.tipo = 'mensaje_entrante'
             AND a.ocurrido_at > COALESCE(e.enviado_at, e.tomado_at)
             AND (a.wa_phone_number_id IS NULL OR a.wa_phone_number_id = m.wa_phone_number_id)),
         COALESCE(c.opt_out, false)
    FROM crm.envios_masivos_destinatarios d
    JOIN crm.envios_masivos m ON m.id = d.envio_masivo_id
    LEFT JOIN crm.envios e ON e.id = d.envio_id
    LEFT JOIN crm.contactos c ON c.id = d.contacto_id
   WHERE d.envio_masivo_id = p_id
   ORDER BY d.fila;
$rem$;

CREATE OR REPLACE FUNCTION crm.resumen_envio_masivo(p_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $rsm$
  SELECT jsonb_build_object(
    'total',        count(*),
    'en_cola',      count(*) FILTER (WHERE r.resultado = 'en_cola'),
    'excluidos',    count(*) FILTER (WHERE r.resultado = 'excluido'),
    'cancelados',   count(*) FILTER (WHERE r.resultado = 'cancelado'),
    'enviando',     count(*) FILTER (WHERE r.resultado = 'enviando'),
    'sin_confirmar', count(*) FILTER (WHERE r.resultado = 'sin_confirmar'),
    'enviados',     count(*) FILTER (WHERE r.resultado IN ('enviado', 'entregado', 'leido')),
    'entregados',   count(*) FILTER (WHERE r.resultado IN ('entregado', 'leido')),
    'leidos',       count(*) FILTER (WHERE r.resultado = 'leido'),
    'fallidos',     count(*) FILTER (WHERE r.resultado = 'fallido'),
    'respondieron', count(*) FILTER (WHERE r.respondio_at IS NOT NULL),
    'bajas',        count(*) FILTER (WHERE r.baja AND r.resultado NOT IN ('excluido', 'cancelado', 'en_cola')),
    'por_motivo',   COALESCE((SELECT jsonb_object_agg(z.motivo, z.n)
                                FROM (SELECT x.motivo, count(*) AS n
                                        FROM crm.envios_masivos_destinatarios x
                                       WHERE x.envio_masivo_id = p_id AND x.motivo IS NOT NULL
                                       GROUP BY x.motivo) z), '{}'::jsonb)
  )
  FROM crm.resultados_envio_masivo(p_id) r;
$rsm$;

GRANT EXECUTE ON FUNCTION crm.crear_envio_masivo(text, text, text[], jsonb, text, text, uuid, jsonb, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION crm.ajustar_envio_masivo(uuid, int, int, int, int, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION crm.lanzar_envio_masivo(uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION crm.cambiar_estado_envio_masivo(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION crm.resultados_envio_masivo(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION crm.resumen_envio_masivo(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 12 · El despachador (de sistema: nadie lo llama desde la app)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.json_seguro(p_texto text)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path = ''
AS $js$
BEGIN
  RETURN p_texto::jsonb;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END $js$;

-- Lo único que sale a la red. Va aparte para que las pruebas lo cambien
-- por uno que no sale, sin tocar el resto.
CREATE OR REPLACE FUNCTION crm.pedir_envio_a_plataforma(p_url text, p_token text, p_cuerpo jsonb)
RETURNS bigint
LANGUAGE sql VOLATILE SET search_path = ''
AS $pep$
  SELECT net.http_post(
    url := rtrim(p_url, '/') || '/api/whatsapp/enviar',
    body := p_cuerpo,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-crm-token', p_token),
    timeout_milliseconds := 30000);
$pep$;

-- Lo que contestó la plataforma a cada petición. La plataforma ya anota
-- el resultado en crm.envios cuando puede; esto cubre lo que no:
--  · 200 con su wa_message_id, si la plataforma no alcanzó a anotarlo;
--  · 400 y 502: ese mensaje falló;
--  · 401, 403, 409 y 503: falla el CANAL, no el mensaje. No salió nada,
--    así que vuelve a la cola y el envío se pausa para que alguien mire.
-- Sin respuesta (tiempo agotado, red) no se sabe si salió: se queda
-- pendiente y la pantalla lo enseña como «sin confirmar». Reintentarlo
-- podría mandárselo dos veces.
CREATE OR REPLACE FUNCTION crm.anotar_respuestas_plataforma()
RETURNS integer
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $arp$
DECLARE
  v_n int := 0;
  v_m int;
  r   record;
BEGIN
  PERFORM set_config('crm.envios_masivos', 'si', true);

  UPDATE crm.envios e
     SET estado = 'enviado',
         wa_message_id = crm.json_seguro(h.content) ->> 'wa_message_id',
         enviado_at = COALESCE(e.enviado_at, h.created)
    FROM net._http_response h
   WHERE h.id = e.solicitud_http
     AND e.estado = 'pendiente'
     AND h.status_code = 200
     AND crm.json_seguro(h.content) ->> 'wa_message_id' IS NOT NULL;
  GET DIAGNOSTICS v_m = ROW_COUNT;
  v_n := v_n + v_m;

  UPDATE crm.envios e
     SET estado = 'fallido',
         error = COALESCE(crm.json_seguro(h.content) ->> 'error',
                          'La plataforma respondió ' || h.status_code),
         error_codigo = COALESCE(
           e.error_codigo,
           CASE WHEN (crm.json_seguro(h.content) ->> 'codigo') ~ '^[0-9]{1,9}$'
                THEN (crm.json_seguro(h.content) ->> 'codigo')::int END),
         fallido_at = now()
    FROM net._http_response h
   WHERE h.id = e.solicitud_http
     AND e.estado = 'pendiente'
     AND h.status_code IN (400, 502);
  GET DIAGNOSTICS v_m = ROW_COUNT;
  v_n := v_n + v_m;

  FOR r IN
    SELECT e.id AS envio_id, e.envio_masivo_id, h.status_code,
           crm.json_seguro(h.content) ->> 'error' AS error
      FROM crm.envios e
      JOIN net._http_response h ON h.id = e.solicitud_http
     WHERE e.estado = 'pendiente'
       AND h.status_code IN (401, 403, 409, 503)
  LOOP
    UPDATE crm.envios_masivos_destinatarios
       SET estado = 'listo', envio_id = NULL
     WHERE envio_id = r.envio_id;
    DELETE FROM crm.envios WHERE id = r.envio_id;
    UPDATE crm.envios_masivos
       SET estado = 'pausado',
           ultimo_aviso = 'Se pausó: la plataforma respondió ' || r.status_code
                          || COALESCE(' (' || r.error || ')', '')
                          || '. No salió nada; revisa el canal y reanúdalo.'
     WHERE id = r.envio_masivo_id AND estado = 'en_curso';
    v_n := v_n + 1;
  END LOOP;

  RETURN v_n;
END $arp$;

CREATE OR REPLACE FUNCTION crm.despachar_envios_masivos(p_ahora timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $dem$
DECLARE
  v_url        text;
  v_token      text;
  c            record;
  d            record;
  v_aviso      text;
  v_disponibles int;
  v_envio      uuid;
  v_quedan     boolean;
  v_total      int := 0;
BEGIN
  PERFORM set_config('crm.envios_masivos', 'si', true);

  -- Antes de mandar lo siguiente, lo que contestaron las anteriores.
  PERFORM crm.anotar_respuestas_plataforma();

  SELECT max(s.decrypted_secret) FILTER (WHERE s.name = 'crm_plataforma_url'),
         max(s.decrypted_secret) FILTER (WHERE s.name = 'crm_envio_token')
    INTO v_url, v_token
    FROM vault.decrypted_secrets s
   WHERE s.name IN ('crm_plataforma_url', 'crm_envio_token');

  FOR c IN
    SELECT m.*,
           l.embudo            AS linea_embudo,
           l.activa            AS linea_activa,
           l.token_invalido_at AS linea_token_invalido_at,
           p.activa            AS plantilla_activa,
           p.estado_meta       AS plantilla_estado,
           p.nombre_meta       AS plantilla_nombre_meta,
           p.idioma            AS plantilla_idioma,
           p.wa_phone_number_id AS plantilla_linea
      FROM crm.envios_masivos m
      LEFT JOIN crm.lineas l ON l.wa_phone_number_id = m.wa_phone_number_id
      LEFT JOIN crm.plantillas p ON p.id = m.plantilla_id
     WHERE m.estado = 'en_curso'
       AND COALESCE(m.proximo_lote_at, '-infinity'::timestamptz) <= p_ahora
     ORDER BY m.lanzado_at
       FOR UPDATE OF m SKIP LOCKED
  LOOP
    IF v_url IS NULL OR v_token IS NULL THEN
      UPDATE crm.envios_masivos
         SET ultimo_aviso = 'Esperando: falta configurar el canal en la base (crm_plataforma_url y crm_envio_token en Vault).'
       WHERE id = c.id AND ultimo_aviso IS DISTINCT FROM
             'Esperando: falta configurar el canal en la base (crm_plataforma_url y crm_envio_token en Vault).';
      CONTINUE;
    END IF;

    -- Lo que pudo cambiar desde que se lanzó. Se pausa: mejor que nada
    -- salga a que salga mal.
    v_aviso := CASE
      WHEN NOT COALESCE(c.linea_activa, false)
        THEN 'Se pausó: la línea ya no está activa.'
      WHEN c.linea_token_invalido_at IS NOT NULL
        THEN 'Se pausó: Meta rechaza la credencial de la línea; hay que reconectarla.'
      WHEN NOT COALESCE(c.plantilla_activa, false) OR c.plantilla_estado IS DISTINCT FROM 'aprobada'
        THEN 'Se pausó: la plantilla ya no está aprobada por Meta.'
      WHEN c.plantilla_linea IS DISTINCT FROM c.wa_phone_number_id
        THEN 'Se pausó: la plantilla ya no es de esta línea.'
    END;
    IF v_aviso IS NOT NULL THEN
      UPDATE crm.envios_masivos SET estado = 'pausado', ultimo_aviso = v_aviso WHERE id = c.id;
      CONTINUE;
    END IF;

    -- Fuera de horario no se hace nada: se vuelve a mirar en un minuto.
    IF NOT crm.en_horario_envio(c.horario, p_ahora) THEN
      CONTINUE;
    END IF;

    -- El tope de la línea: personas distintas que recibieron una plantilla
    -- en las últimas 24 horas, de cualquier envío.
    SELECT c.tope_diario - count(DISTINCT e.contacto_id) INTO v_disponibles
      FROM crm.envios e
     WHERE e.wa_phone_number_id = c.wa_phone_number_id
       AND e.plantilla_id IS NOT NULL
       AND e.created_at > p_ahora - interval '24 hours';
    IF v_disponibles <= 0 THEN
      UPDATE crm.envios_masivos
         SET proximo_lote_at = p_ahora + interval '15 minutes',
             ultimo_aviso = 'Esperando: la línea ya le escribió a ' || c.tope_diario
                            || ' personas en 24 horas, su tope.'
       WHERE id = c.id;
      CONTINUE;
    END IF;

    FOR d IN
      SELECT x.id, x.contacto_id, x.telefono_e164, x.cuerpo, x.valores
        FROM crm.envios_masivos_destinatarios x
       WHERE x.envio_masivo_id = c.id AND x.estado = 'listo'
       ORDER BY x.fila
       LIMIT LEAST(c.tamano_lote, v_disponibles)
         FOR UPDATE SKIP LOCKED
    LOOP
      INSERT INTO crm.envios
        (inmobiliaria_id, contacto_id, plantilla_id, cuerpo, canal, estado, enviado_por,
         wa_phone_number_id, envio_masivo_id, variables, tomado_at)
      VALUES
        (c.inmobiliaria_id, d.contacto_id, c.plantilla_id, d.cuerpo, 'meta', 'pendiente',
         c.lanzado_por, c.wa_phone_number_id, c.id, d.valores, p_ahora)
      RETURNING id INTO v_envio;

      UPDATE crm.envios_masivos_destinatarios
         SET estado = 'encolado', envio_id = v_envio
       WHERE id = d.id;

      -- El mismo cuerpo que manda el CRM por lib/canal.ts (contrato C1).
      UPDATE crm.envios
         SET solicitud_http = crm.pedir_envio_a_plataforma(v_url, v_token, jsonb_build_object(
               'inmobiliaria_id', c.inmobiliaria_id,
               'telefono', d.telefono_e164,
               'texto', d.cuerpo,
               'envio_id', v_envio,
               'desde', jsonb_build_object('wa_phone_number_id', c.wa_phone_number_id,
                                           'embudo', c.linea_embudo),
               'plantilla', jsonb_build_object('nombre_meta', c.plantilla_nombre_meta,
                                               'idioma', c.plantilla_idioma,
                                               'variables', d.valores)))
       WHERE id = v_envio;

      v_total := v_total + 1;
    END LOOP;

    SELECT EXISTS (SELECT 1 FROM crm.envios_masivos_destinatarios x
                    WHERE x.envio_masivo_id = c.id AND x.estado = 'listo')
      INTO v_quedan;

    UPDATE crm.envios_masivos
       SET proximo_lote_at = p_ahora + make_interval(mins => c.minutos_entre_lotes),
           estado          = CASE WHEN v_quedan THEN 'en_curso' ELSE 'terminado' END,
           terminado_at    = CASE WHEN v_quedan THEN NULL ELSE p_ahora END,
           ultimo_aviso    = NULL
     WHERE id = c.id;
  END LOOP;

  RETURN v_total;
END $dem$;

COMMENT ON FUNCTION crm.despachar_envios_masivos(timestamptz) IS
  'Cada minuto (pg_cron): toma el siguiente lote de cada envío masivo en curso, en su horario y dentro del tope diario de la línea, y se lo pide a la plataforma.';

-- Las filas originales traen deudas de personas: a los 90 días de
-- terminado o cancelado, se borran. Queda quién, qué estado y el envío.
CREATE OR REPLACE FUNCTION crm.purgar_envios_masivos(
  p_ahora timestamptz DEFAULT now(),
  p_dias  int DEFAULT 90)
RETURNS integer
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $pem$
DECLARE
  v_n int;
BEGIN
  PERFORM set_config('crm.envios_masivos', 'si', true);

  WITH viejos AS (
    UPDATE crm.envios_masivos m
       SET datos_borrados_at = p_ahora
     WHERE m.estado IN ('terminado', 'cancelado')
       AND m.datos_borrados_at IS NULL
       AND COALESCE(m.terminado_at, m.updated_at) < p_ahora - make_interval(days => p_dias)
    RETURNING m.id)
  UPDATE crm.envios_masivos_destinatarios d
     SET datos = NULL, valores = '{}'::jsonb, cuerpo = NULL
    FROM viejos v
   WHERE d.envio_masivo_id = v.id;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  RETURN v_n;
END $pem$;

-- ---------------------------------------------------------------------
-- 13 · La agenda
-- ---------------------------------------------------------------------
DO $cron$
BEGIN
  PERFORM cron.schedule(
    'crm_despachar_envios_masivos', '* * * * *',
    $trabajo$SELECT crm.despachar_envios_masivos();$trabajo$);
  PERFORM cron.schedule(
    'crm_purgar_envios_masivos', '17 8 * * *',
    $trabajo$SELECT crm.purgar_envios_masivos();$trabajo$);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron no disponible; agendar crm.despachar_envios_masivos() y crm.purgar_envios_masivos() a mano: %', SQLERRM;
END $cron$;
