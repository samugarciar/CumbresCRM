-- =====================================================================
-- Arregla un fallo real del normalizador, detectado al cruzar dos
-- consultas sobre producción.
--
-- El informe contó 224 teléfonos raros en agente_comercial_conversaciones;
-- una consulta directa encontró 225. La diferencia era una fila escrita
-- con un '+' delante: la regla aceptaba desde 8 dígitos cuando había
-- marca internacional, así que "+50123456" pasaba como número válido de
-- algún país y entraba a la lista de personas distintas alguien que no
-- existe.
--
-- Ocho dígitos CONTANDO EL INDICATIVO no alcanzan para prácticamente
-- ningún plan de numeración. El mínimo sube a 10.
-- =====================================================================

CREATE OR REPLACE FUNCTION crm.normalizar_telefono(p_tel text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  d      text;
  marca  boolean;
BEGIN
  IF p_tel IS NULL THEN
    RETURN NULL;
  END IF;

  marca := ltrim(p_tel) LIKE '+%';
  d     := regexp_replace(p_tel, '[^0-9]', '', 'g');

  IF d = '' THEN
    RETURN NULL;
  END IF;

  IF left(d, 2) = '00' THEN
    d     := substr(d, 3);
    marca := true;
  END IF;

  -- Colombia primero, aunque venga con '+': un "+3001234567" es un móvil
  -- colombiano sin el 57, no un número de Grecia.
  IF d ~ '^3[0-9]{9}$' THEN
    RETURN '+57' || d;
  END IF;

  IF d ~ '^60[0-9]{8}$' THEN
    RETURN '+57' || d;
  END IF;

  IF d ~ '^57(3[0-9]{9}|60[0-9]{8})$' THEN
    RETURN '+' || d;
  END IF;

  -- Once dígitos que empiezan en 3: casi seguro un dedazo en un móvil
  -- colombiano, no un número europeo. No se adivina.
  IF d ~ '^3[0-9]{10}$' THEN
    RETURN NULL;
  END IF;

  -- Internacional. EL CAMBIO ESTÁ AQUÍ: antes '{7,14}' (8 dígitos
  -- mínimo), ahora '{9,14}' (10 mínimo).
  IF d ~ '^[1-9][0-9]{9,14}$' AND (marca OR length(d) >= 11) THEN
    RETURN '+' || d;
  END IF;

  RETURN NULL;
END;
$$;

-- La columna cacheada acepta lo mismo que la identidad.
ALTER TABLE crm.contactos DROP CONSTRAINT IF EXISTS contactos_e164_valido;
ALTER TABLE crm.contactos ADD CONSTRAINT contactos_e164_valido CHECK (
  telefono_e164 IS NULL OR telefono_e164 ~ '^\+[1-9][0-9]{9,14}$'
);
