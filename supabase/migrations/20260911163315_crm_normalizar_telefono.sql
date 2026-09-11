-- =====================================================================
-- crm.normalizar_telefono — lleva un teléfono escrito de cualquier forma
-- a formato E.164 (+<indicativo><numero>), o devuelve NULL si no se puede
-- decidir sin adivinar.
--
-- POR QUÉ IMPORTA TANTO
-- El teléfono es la llave natural del contacto: los leads entran por
-- WhatsApp y muchos nunca dan correo. La misma persona aparece hoy como
-- "3001234567", "+57 300 123 4567" y "573001234567" en tablas distintas.
-- Sin normalizar, son tres personas.
--
-- LA REGLA QUE GOBIERNA EL DISEÑO
-- Los dos errores posibles NO cuestan lo mismo:
--   · partir una persona en dos registros  → molesto, y se deshace fusionando
--   · fusionar dos personas en un registro → mezcla conversaciones, visitas
--     y consentimientos de dos seres humanos, y NO se deshace. Además, bajo
--     la Ley 1581, es mostrarle a alguien los datos de otro.
-- Ante la duda, entonces, se devuelve NULL. Quien llama guarda el valor
-- crudo aparte y una persona lo revisa. Preferimos quedarnos cortos.
--
-- MEDIDO SOBRE DATOS REALES (11 sep 2026, citas + solicitudes_apertura):
-- de 608 teléfonos, 595 normalizan (97,9%) y salen 440 personas distintas.
-- De los 13 que no: ~9 son números extranjeros legítimos (Perú y EE.UU.,
-- colombianos en el exterior buscando arriendo), 1 parece un dedazo y 3
-- están vacíos.
-- =====================================================================

CREATE OR REPLACE FUNCTION crm.normalizar_telefono(p_tel text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  d      text;     -- solo los dígitos
  marca  boolean;  -- venía marcado como internacional ('+' o '00')
BEGIN
  IF p_tel IS NULL THEN
    RETURN NULL;
  END IF;

  marca := ltrim(p_tel) LIKE '+%';
  d     := regexp_replace(p_tel, '[^0-9]', '', 'g');

  IF d = '' THEN
    RETURN NULL;
  END IF;

  -- '00' es el prefijo internacional a la vieja usanza: 00573001234567
  IF left(d, 2) = '00' THEN
    d     := substr(d, 3);
    marca := true;
  END IF;

  -- -------------------------------------------------------------------
  -- Colombia primero, aunque venga con '+'. Un "+3001234567" no es un
  -- número de Grecia (+30): es un móvil colombiano al que le falta el 57.
  -- -------------------------------------------------------------------

  -- Móvil: 10 dígitos que empiezan en 3
  IF d ~ '^3[0-9]{9}$' THEN
    RETURN '+57' || d;
  END IF;

  -- Fijo (numeración nueva de 10 dígitos): 60 + indicativo + 7 dígitos
  IF d ~ '^60[0-9]{8}$' THEN
    RETURN '+57' || d;
  END IF;

  -- Ya trae el 57 delante, móvil o fijo
  IF d ~ '^57(3[0-9]{9}|60[0-9]{8})$' THEN
    RETURN '+' || d;
  END IF;

  -- -------------------------------------------------------------------
  -- Guarda de ambigüedad: 11 dígitos que empiezan en 3.
  --
  -- Podría leerse como internacional (+3X…, algún país europeo), pero en
  -- una inmobiliaria de Medellín es muchísimo más probable que sea un
  -- móvil colombiano con un dígito de más. Adivinar cualquiera de las dos
  -- cosas puede fusionar personas, así que no se adivina.
  -- -------------------------------------------------------------------
  IF d ~ '^3[0-9]{10}$' THEN
    RETURN NULL;
  END IF;

  -- -------------------------------------------------------------------
  -- Internacional. Se acepta cuando hay evidencia de que lo es:
  --   · venía con '+' o '00', o
  --   · tiene 11 dígitos o más, que ya no cabe en la numeración local.
  --
  -- La condición de longitud es deliberada: un número pelado de 10
  -- dígitos en este CRM es colombiano. Si no encajó en las reglas de
  -- arriba, es un error de digitación, no un número de otro país, y
  -- convertirlo en "+80…" sería inventar.
  -- -------------------------------------------------------------------
  IF d ~ '^[1-9][0-9]{7,14}$' AND (marca OR length(d) >= 11) THEN
    RETURN '+' || d;
  END IF;

  -- Fijos de 7 dígitos sin indicativo, longitudes imposibles, basura.
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION crm.normalizar_telefono(text) IS
  'Teléfono en cualquier forma → E.164, o NULL si decidirlo exigiría adivinar. Ante la duda devuelve NULL: fusionar dos personas es un daño que no se deshace.';

GRANT EXECUTE ON FUNCTION crm.normalizar_telefono(text) TO authenticated, service_role;
