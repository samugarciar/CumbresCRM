-- =====================================================================
-- crm.contactos — la columna vertebral del CRM.
--
-- Hoy la misma persona vive como texto suelto en cuatro sitios sin
-- unificar: agente_comercial_conversaciones, citas, solicitudes_apertura
-- y captacion_prospectos. Por eso nadie puede responder "¿qué ha pasado
-- con este señor?". Esta tabla es la respuesta a esa pregunta.
-- =====================================================================

-- pg_trgm para la búsqueda por nombre tolerante a erratas ("Jhon" encuentra
-- "John"). Va al esquema `extensions`, NO a `public`: crear una extensión
-- en public sería escribir en el esquema del otro repo.
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;

CREATE TABLE crm.contactos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- FK directa a public, no a una vista, por dos razones: una FK no es
  -- una escritura (solo impide insertar basura), y Postgres no admite
  -- vistas como destino de una llave foránea. Es lo que evita que un
  -- webhook con service role —que ignora la RLS— cree un contacto con un
  -- inmobiliaria_id inventado, que quedaría invisible para todos o, peor,
  -- caería en la inmobiliaria equivocada.
  inmobiliaria_id uuid NOT NULL
    REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,

  -- ---------------------------------------------------------------
  -- Identidad
  -- ---------------------------------------------------------------
  -- La llave natural. NULL cuando el crudo no se pudo normalizar sin
  -- adivinar; el índice único es parcial, así que los nulos no chocan.
  telefono_e164 text,
  -- Siempre se conserva lo que llegó, aunque se haya normalizado bien:
  -- es lo que permite revisar a mano los casos dudosos.
  telefono_crudo text,

  nombre text,
  email text,

  tipo text NOT NULL DEFAULT 'cliente'
    CHECK (tipo IN ('cliente', 'propietario', 'ambos')),

  -- ---------------------------------------------------------------
  -- Procedencia
  -- ---------------------------------------------------------------
  origen text,                                  -- whatsapp, meta_ads, mercadolibre, referido, import…
  utm jsonb NOT NULL DEFAULT '{}'::jsonb,
  external_ids jsonb NOT NULL DEFAULT '{}'::jsonb,  -- {"kommo_lead_id": "...", "kommo_contact_id": "..."}

  asesor_id uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,

  -- ---------------------------------------------------------------
  -- Habeas Data (Ley 1581 de 2012)
  --
  -- Va desde el primer día, no "cuando haga falta": añadir estas columnas
  -- después obliga a rellenar el pasado a ciegas, y el dato que importa
  -- —cuándo y por qué canal autorizó— ya no se puede reconstruir.
  -- ---------------------------------------------------------------
  consentimiento boolean NOT NULL DEFAULT false,
  consentimiento_at timestamptz,
  consentimiento_canal text,                    -- whatsapp, formulario_web, presencial…

  notas text,

  -- Para fusiones de duplicados: el perdedor apunta al que quedó.
  merged_into_id uuid REFERENCES crm.contactos(id) ON DELETE SET NULL,

  -- Denormalizado a propósito: ordenar la bandeja por "quién escribió más
  -- recientemente" es la consulta más frecuente de un CRM, y calcularla
  -- contra el timeline en cada carga no escala.
  ultima_actividad_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,

  -- Forma de E.164 garantizada por regex y no llamando a
  -- crm.normalizar_telefono(): un CHECK que depende de una función la
  -- deja congelada, porque mejorarla podría invalidar filas ya guardadas.
  CONSTRAINT contactos_e164_valido CHECK (
    telefono_e164 IS NULL OR telefono_e164 ~ '^\+[1-9][0-9]{7,14}$'
  ),

  CONSTRAINT contactos_consentimiento_con_fecha CHECK (
    consentimiento = false OR consentimiento_at IS NOT NULL
  )
);

-- ---------------------------------------------------------------------
-- Índices
-- ---------------------------------------------------------------------

-- El índice que impide duplicados. Las dos condiciones del WHERE son
-- deliberadas:
--   · telefono_e164 IS NOT NULL → los contactos sin llave no chocan entre
--     sí; si no, los 13 casos dudosos del histórico se estorbarían.
--   · deleted_at IS NULL → borrar un contacto no impide volver a crear
--     otro con el mismo teléfono.
CREATE UNIQUE INDEX contactos_telefono_uniq
  ON crm.contactos (inmobiliaria_id, telefono_e164)
  WHERE deleted_at IS NULL AND telefono_e164 IS NOT NULL;

CREATE INDEX contactos_org
  ON crm.contactos (inmobiliaria_id) WHERE deleted_at IS NULL;

CREATE INDEX contactos_asesor
  ON crm.contactos (inmobiliaria_id, asesor_id) WHERE deleted_at IS NULL;

-- Orden natural de la bandeja: lo más reciente arriba.
CREATE INDEX contactos_actividad
  ON crm.contactos (inmobiliaria_id, ultima_actividad_at DESC NULLS LAST)
  WHERE deleted_at IS NULL;

-- Búsqueda por nombre tolerante a erratas.
CREATE INDEX contactos_nombre_trgm
  ON crm.contactos USING gin (nombre extensions.gin_trgm_ops);

-- Para reencontrar un contacto por su id de Kommo durante la transición.
CREATE INDEX contactos_external_ids
  ON crm.contactos USING gin (external_ids);

-- Los que hay que revisar a mano: teléfono que no normalizó.
CREATE INDEX contactos_sin_llave
  ON crm.contactos (inmobiliaria_id)
  WHERE deleted_at IS NULL AND telefono_e164 IS NULL;

-- ---------------------------------------------------------------------
-- updated_at
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.tocar_updated_at()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

CREATE TRIGGER contactos_updated_at
  BEFORE UPDATE ON crm.contactos
  FOR EACH ROW EXECUTE FUNCTION crm.tocar_updated_at();

-- ---------------------------------------------------------------------
-- RLS
--
-- Decisión: TODO miembro de la inmobiliaria ve TODOS sus contactos.
-- El CRM es la memoria de la empresa; que un asesor no vea que otro ya
-- habló con alguien es justo el problema que se viene a resolver, y es lo
-- que produce que dos asesores llamen al mismo cliente. Borrar, en cambio,
-- queda solo para admin.
--
-- Se reutilizan public.get_my_inmobiliaria() y public.get_my_role(), que
-- ya existen y están probadas en producción. Son lecturas de `public`.
-- ---------------------------------------------------------------------
ALTER TABLE crm.contactos ENABLE ROW LEVEL SECURITY;

CREATE POLICY contactos_select ON crm.contactos
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());

CREATE POLICY contactos_insert ON crm.contactos
  FOR INSERT TO authenticated
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria());

CREATE POLICY contactos_update ON crm.contactos
  FOR UPDATE TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria())
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria());

CREATE POLICY contactos_delete ON crm.contactos
  FOR DELETE TO authenticated
  USING (
    inmobiliaria_id = public.get_my_inmobiliaria()
    AND public.get_my_role() = 'admin'
  );

COMMENT ON TABLE crm.contactos IS
  'Columna vertebral del CRM: una persona por teléfono normalizado. Unifica lo que hoy vive suelto en agente_comercial_conversaciones, citas, solicitudes_apertura y captacion_prospectos.';
COMMENT ON COLUMN crm.contactos.telefono_e164 IS
  'Llave natural en E.164. NULL cuando el crudo no se pudo normalizar sin adivinar — ver crm.normalizar_telefono.';
COMMENT ON COLUMN crm.contactos.telefono_crudo IS
  'El texto tal como llegó. Se conserva siempre, para poder revisar a mano lo que no normalizó.';
