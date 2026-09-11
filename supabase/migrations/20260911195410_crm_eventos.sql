-- =====================================================================
-- crm.eventos — el buzón de proyección.
--
-- ESTO ES UNA PIEZA DE SEGURIDAD, NO DE FUNCIONALIDAD.
--
-- El CRM recibe sus datos por triggers colgados de tablas de `public`.
-- Un trigger que lanza una excepción ABORTA la transacción de quien lo
-- disparó: si el trigger de proyección tiene un bug, el agente comercial
-- no puede guardar el mensaje y se queda MUDO con un cliente real de
-- WhatsApp, en vivo.
--
-- El patrón: el trigger intenta proyectar dentro de un bloque
-- `EXCEPTION WHEN OTHERS`. Si falla, en vez de propagar, deja aquí el
-- evento con estado 'fallido' y el error. Un job lo reintenta después.
-- El negocio nunca se entera de que el CRM se rompió.
--
-- Medido antes de construir encima: supabase/tests/02_patron_proyeccion.sql
-- =====================================================================

CREATE TABLE crm.eventos (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

  inmobiliaria_id uuid REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,

  -- Qué pasó, en el lenguaje del origen: 'mensaje_whatsapp', 'cita',
  -- 'solicitud_apertura'. CHECK y no enum: añadir un tipo no debe exigir
  -- una migración pesada.
  tipo text NOT NULL CHECK (tipo IN (
    'mensaje_whatsapp', 'cita', 'solicitud_apertura', 'backfill'
  )),

  tabla_origen text NOT NULL,
  fila_origen_id text NOT NULL,     -- text: los orígenes usan uuid y bigint
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,

  estado text NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'ok', 'fallido', 'abandonado')),

  intentos int NOT NULL DEFAULT 0,
  error text,

  created_at timestamptz NOT NULL DEFAULT now(),
  procesado_at timestamptz
);

-- La cola de trabajo: solo lo que falta por procesar.
CREATE INDEX eventos_pendientes
  ON crm.eventos (created_at)
  WHERE estado IN ('pendiente', 'fallido');

-- Idempotencia: una fila de origen no se proyecta dos veces por el mismo
-- motivo. Es lo que permite reintentar sin duplicar contactos.
CREATE UNIQUE INDEX eventos_origen_uniq
  ON crm.eventos (tabla_origen, fila_origen_id, tipo);

CREATE INDEX eventos_org ON crm.eventos (inmobiliaria_id, created_at DESC);

-- ---------------------------------------------------------------------
-- RLS: solo admin, y solo lectura desde la aplicación.
--
-- Esta tabla es diagnóstico interno: quién la mira es quien depura, y
-- escribirla a mano no tiene sentido — la llenan los triggers, que corren
-- como definidor y no pasan por estas políticas.
-- ---------------------------------------------------------------------
ALTER TABLE crm.eventos ENABLE ROW LEVEL SECURITY;

CREATE POLICY eventos_select ON crm.eventos
  FOR SELECT TO authenticated
  USING (
    inmobiliaria_id = public.get_my_inmobiliaria()
    AND public.get_my_role() = 'admin'
  );

COMMENT ON TABLE crm.eventos IS
  'Buzón de proyección. Un trigger que falla deja aquí el evento en vez de tumbar la transacción del agente comercial. Ver tests/02_patron_proyeccion.sql.';
