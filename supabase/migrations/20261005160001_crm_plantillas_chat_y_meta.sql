-- =====================================================================
-- Plantillas de Chat vs. WhatsApp Meta (Decisiones 29 y 30)
--
-- Separa las respuestas rápidas de chat (que no pasan por Meta ni pagan
-- tarifa de plantilla) de las plantillas oficiales de WhatsApp (que Meta
-- aprueba y cobra).
-- =====================================================================

ALTER TABLE crm.plantillas
  ADD COLUMN IF NOT EXISTS tipo text NOT NULL DEFAULT 'whatsapp',
  ADD COLUMN IF NOT EXISTS idioma text NOT NULL DEFAULT 'es',
  ADD COLUMN IF NOT EXISTS motivo_rechazo_meta text;

-- Restricción de tipos de plantilla
ALTER TABLE crm.plantillas
  DROP CONSTRAINT IF EXISTS plantillas_tipo_valido;

ALTER TABLE crm.plantillas
  ADD CONSTRAINT plantillas_tipo_valido
  CHECK (tipo IN ('chat', 'whatsapp'));

-- Idiomas válidos para Meta
ALTER TABLE crm.plantillas
  DROP CONSTRAINT IF EXISTS plantillas_idioma_valido;

ALTER TABLE crm.plantillas
  ADD CONSTRAINT plantillas_idioma_valido
  CHECK (idioma IN ('es', 'es_CO', 'en', 'en_US'));

-- La restricción de categoría se flexibiliza para chat (admite 'general')
-- pero sigue exigiendo 'utilidad' o 'marketing' para WhatsApp Meta
ALTER TABLE crm.plantillas
  DROP CONSTRAINT IF EXISTS plantillas_categoria_check;

ALTER TABLE crm.plantillas
  DROP CONSTRAINT IF EXISTS plantillas_categoria_valida;

ALTER TABLE crm.plantillas
  ADD CONSTRAINT plantillas_categoria_valida
  CHECK (
    (tipo = 'whatsapp' AND categoria IN ('utilidad', 'marketing'))
    OR (tipo = 'chat' AND categoria IN ('utilidad', 'marketing', 'general', 'arrendamiento', 'visitas'))
  );

-- Ajustar la restricción de aprobada con nombre: solo aplica si es whatsapp
ALTER TABLE crm.plantillas
  DROP CONSTRAINT IF EXISTS plantillas_aprobada_con_nombre;

ALTER TABLE crm.plantillas
  ADD CONSTRAINT plantillas_aprobada_con_nombre
  CHECK (tipo <> 'whatsapp' OR estado_meta <> 'aprobada' OR btrim(COALESCE(nombre_meta, '')) <> '');

-- Comentarios explicativos
COMMENT ON COLUMN crm.plantillas.tipo IS
  'chat: respuesta rápida para conversaciones dentro de 24h (sin trámite en Meta). whatsapp: plantilla oficial aprobada por Meta (HSM).';

COMMENT ON COLUMN crm.plantillas.idioma IS
  'Código de idioma requerido por Meta al tramitar la plantilla (por defecto "es").';

COMMENT ON COLUMN crm.plantillas.motivo_rechazo_meta IS
  'Detalle o motivo devuelto por Meta cuando rechaza una plantilla (ej. INCORRECT_CATEGORY, INVALID_FORMAT).';
