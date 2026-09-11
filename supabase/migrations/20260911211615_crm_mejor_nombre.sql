-- =====================================================================
-- crm.mejor_nombre — elegir entre dos nombres de la misma persona.
--
-- DE DÓNDE SALE EL PROBLEMA
-- El nombre de una conversación de WhatsApp es el NOMBRE DE PERFIL que la
-- propia persona se puso: "MG❤️", "Juli☺️", "JLFR", ".". Kommo muestra
-- exactamente eso, porque es lo único que la API de WhatsApp manda. Medido
-- sobre los datos reales: 13-15% traen emoji y 56-63% son una sola palabra.
--
-- Pero el CRM tiene una segunda fuente que Kommo no tiene: cuando el
-- agente agenda una visita, LE PREGUNTA EL NOMBRE al cliente y lo guarda
-- en citas.cliente_nombre. Ese suele ser el nombre de verdad.
--
-- Antes ganaba el primero que llegara (COALESCE), y el backfill procesa
-- las conversaciones primero — o sea que ganaba siempre el apodo.
--
-- HONESTIDAD SOBRE EL TAMAÑO DE LA MEJORA
-- Medido el 11 sep 2026: de las 67 personas que conversaron Y agendaron,
-- las 67 ya tenían un nombre de dos palabras en WhatsApp. Para ellas esto
-- no cambia nada. Importa hacia adelante, con la mayoría que hoy tiene un
-- nombre de una sola palabra y todavía no ha agendado.
-- =====================================================================

CREATE OR REPLACE FUNCTION crm.calidad_nombre(p_nombre text)
RETURNS int
LANGUAGE sql IMMUTABLE SET search_path = ''
AS $calidad$
  -- Cuántas PALABRAS CON LETRAS tiene. Es una medida tosca a propósito:
  -- cualquier cosa más lista (detectar apellidos, listas de nombres
  -- colombianos) falla con los casos raros y es imposible de explicar
  -- cuando alguien pregunta por qué el CRM eligió un nombre u otro.
  --   'María González' → 2     'MG❤️' → 1     '☺️' → 0     '' → 0
  SELECT COALESCE(
    (SELECT count(*)::int
       FROM unnest(regexp_split_to_array(btrim(COALESCE(p_nombre, '')), '\s+')) w
      WHERE w ~ '[A-Za-zÀ-ÿ]'),
    0);
$calidad$;

CREATE OR REPLACE FUNCTION crm.mejor_nombre(p_actual text, p_candidato text)
RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = ''
AS $mejor$
  -- En empate gana el que ya estaba: si no, cada mensaje nuevo podría
  -- cambiar el nombre de la ficha y nadie entendería por qué.
  SELECT CASE
    WHEN btrim(COALESCE(p_candidato, '')) = '' THEN p_actual
    WHEN btrim(COALESCE(p_actual, ''))    = '' THEN p_candidato
    WHEN crm.calidad_nombre(p_candidato) > crm.calidad_nombre(p_actual)
      THEN p_candidato
    ELSE p_actual
  END;
$mejor$;

COMMENT ON FUNCTION crm.mejor_nombre(text, text) IS
  'Elige el mejor de dos nombres de la misma persona: gana el que tenga más palabras con letras; en empate, el que ya estaba.';

GRANT EXECUTE ON FUNCTION crm.calidad_nombre(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION crm.mejor_nombre(text, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- resolver_contacto pasa a usarlo.
--
-- Mismo cuerpo que en 20260911195413_crm_identidades.sql —donde está toda
-- la documentación del porqué— con un solo cambio: el nombre ya no se
-- resuelve con COALESCE sino con crm.mejor_nombre.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.resolver_contacto(
  p_inmobiliaria_id uuid,
  p_identidades jsonb,
  p_nombre text DEFAULT NULL,
  p_origen text DEFAULT NULL,
  p_tipo_contacto text DEFAULT 'cliente',
  p_telefono_crudo text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $resolver$
DECLARE
  v_orden constant text[] := ARRAY[
    'telefono_e164', 'whatsapp_username', 'kommo_lead',
    'kommo_contact', 'email', 'meta_psid', 'otro'
  ];
  v_tipo      text;
  v_contacto  uuid;
  v_ident     jsonb;
BEGIN
  IF p_identidades IS NULL OR jsonb_array_length(p_identidades) = 0 THEN
    RETURN NULL;
  END IF;

  FOREACH v_tipo IN ARRAY v_orden LOOP
    SELECT i.contacto_id INTO v_contacto
      FROM crm.identidades i
      JOIN jsonb_array_elements(p_identidades) e
        ON e->>'tipo' = i.tipo AND e->>'valor' = i.valor
     WHERE i.inmobiliaria_id = p_inmobiliaria_id
       AND i.tipo = v_tipo
     LIMIT 1;
    EXIT WHEN v_contacto IS NOT NULL;
  END LOOP;

  IF v_contacto IS NULL THEN
    INSERT INTO crm.contactos (inmobiliaria_id, nombre, origen, tipo, telefono_crudo)
    VALUES (p_inmobiliaria_id, p_nombre, p_origen,
            COALESCE(p_tipo_contacto, 'cliente'), p_telefono_crudo)
    RETURNING id INTO v_contacto;
  ELSE
    -- EL CAMBIO: el nombre se elige por calidad, no por orden de llegada.
    -- El resto sigue siendo "lo primero que se supo gana", porque para
    -- origen y teléfono crudo el dato más viejo es el que alguien
    -- verificó a mano.
    UPDATE crm.contactos
       SET nombre         = crm.mejor_nombre(nombre, p_nombre),
           origen         = COALESCE(origen, p_origen),
           telefono_crudo = COALESCE(telefono_crudo, p_telefono_crudo)
     WHERE id = v_contacto;
  END IF;

  FOR v_ident IN SELECT * FROM jsonb_array_elements(p_identidades) LOOP
    INSERT INTO crm.identidades (inmobiliaria_id, contacto_id, tipo, valor, origen)
    VALUES (p_inmobiliaria_id, v_contacto,
            v_ident->>'tipo', v_ident->>'valor', p_origen)
    ON CONFLICT (inmobiliaria_id, tipo, valor) DO NOTHING;
  END LOOP;

  RETURN v_contacto;
END $resolver$;
