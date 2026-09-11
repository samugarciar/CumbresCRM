-- =====================================================================
-- crm.actividades — el timeline unificado.
--
-- Es lo que convierte al CRM en memoria: un solo flujo donde aparecen
-- los mensajes de WhatsApp, las visitas, las solicitudes de horario, las
-- notas de los asesores y los cambios de etapa, en orden cronológico.
--
-- POR QUÉ LLAVES FORÁNEAS EXPLÍCITAS Y NO UN PAR POLIMÓRFICO
-- Un `(tipo_relacionado, id_relacionado)` sería más flexible, pero
-- Postgres no puede garantizar integridad sobre eso: acabarías con
-- actividades apuntando a registros que ya no existen. Con columnas
-- explícitas y un CHECK de "al menos una no nula", la base lo impide. Y
-- una visita puede colgar del contacto Y del inmueble a la vez, que es
-- justo lo que se necesita.
-- =====================================================================

CREATE TABLE crm.actividades (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

  inmobiliaria_id uuid NOT NULL
    REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,

  tipo text NOT NULL CHECK (tipo IN (
    'mensaje_entrante', 'mensaje_saliente', 'nota', 'llamada',
    'visita_agendada', 'visita_realizada', 'visita_cancelada',
    'solicitud_apertura', 'sistema'
  )),

  -- Quién lo produjo. Separar al agente de IA de la persona importa:
  -- un timeline que no distingue "le escribió Laura" de "le contestó el
  -- bot" miente sobre lo que pasó.
  origen text NOT NULL DEFAULT 'sistema'
    CHECK (origen IN ('humano', 'agente_ia', 'sistema')),

  contacto_id uuid REFERENCES crm.contactos(id) ON DELETE CASCADE,
  inmueble_id uuid REFERENCES public.inmuebles(id) ON DELETE SET NULL,
  cita_id uuid REFERENCES public.citas(id) ON DELETE SET NULL,

  cuerpo text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  -- Cuándo ocurrió de verdad, que no es cuándo lo guardamos: el backfill
  -- inserta hoy actividades de julio.
  ocurrido_at timestamptz NOT NULL DEFAULT now(),

  creado_por uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT actividades_algo_relacionado CHECK (
    num_nonnulls(contacto_id, inmueble_id, cita_id) >= 1
  )
);

-- El orden en que se lee una ficha: lo más reciente arriba.
CREATE INDEX actividades_timeline
  ON crm.actividades (contacto_id, ocurrido_at DESC);

CREATE INDEX actividades_org
  ON crm.actividades (inmobiliaria_id, ocurrido_at DESC);

CREATE INDEX actividades_inmueble
  ON crm.actividades (inmueble_id, ocurrido_at DESC)
  WHERE inmueble_id IS NOT NULL;

-- Idempotencia del backfill y de la proyección: la misma fila de origen
-- no genera dos actividades. La clave va en metadata para no añadir dos
-- columnas que solo sirven a esto.
CREATE UNIQUE INDEX actividades_origen_uniq
  ON crm.actividades ((metadata->>'origen_tabla'), (metadata->>'origen_id'))
  WHERE metadata ? 'origen_id';

ALTER TABLE crm.actividades ENABLE ROW LEVEL SECURITY;

CREATE POLICY actividades_select ON crm.actividades
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());

CREATE POLICY actividades_insert ON crm.actividades
  FOR INSERT TO authenticated
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria());

-- Editar y borrar historial no se permite desde la aplicación, a nadie.
-- Un timeline que se puede reescribir no sirve como memoria ni como
-- prueba. Corregir se hace añadiendo una nota, no borrando.

COMMENT ON TABLE crm.actividades IS
  'Timeline unificado. Sin UPDATE ni DELETE desde la app a propósito: un historial reescribible no sirve como memoria.';
