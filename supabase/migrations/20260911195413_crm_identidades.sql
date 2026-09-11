-- =====================================================================
-- crm.identidades — dejar de tratar la identidad como un campo.
--
-- POR QUÉ CAMBIA EL MODELO QUE SE CREÓ EN LA FASE 1-A
-- Ahí el teléfono era LA llave. Medir el histórico mostró que eso ya
-- falla hoy: 225 personas reales, con conversaciones y nombre, llegaron
-- sin teléfono utilizable. Y va a fallar más — WhatsApp avanza hacia
-- identificar por username sin exponer el número, y en la fase 5 entra
-- el correo.
--
-- La corrección no es añadir otro caso especial, es reconocer que una
-- persona se reconoce por VARIAS cosas y que cualquiera de ellas puede
-- faltar. Una fila por forma de reconocerla; N por contacto.
--
-- Es el mismo razonamiento que el multi-tenant: cuesta una tabla hoy, y
-- cuesta migrar mil contactos y cada consulta si se deja para después.
-- =====================================================================

CREATE TABLE crm.identidades (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

  inmobiliaria_id uuid NOT NULL
    REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,
  contacto_id uuid NOT NULL
    REFERENCES crm.contactos(id) ON DELETE CASCADE,

  -- CHECK y no enum: a un enum de Postgres se le pueden añadir valores
  -- pero no quitarlos ni reordenarlos. Aquí van a aparecer tipos nuevos
  -- (el username de WhatsApp cuando llegue el canal propio, quizá un id
  -- de Instagram) y no queremos que cada uno sea una migración pesada.
  tipo text NOT NULL CHECK (tipo IN (
    'telefono_e164',
    'whatsapp_username',
    'kommo_lead',
    'kommo_contact',
    'email',
    'meta_psid',
    'otro'
  )),

  valor text NOT NULL,

  origen text,                                  -- de qué fuente salió
  created_at timestamptz NOT NULL DEFAULT now(),

  -- Un teléfono guardado como identidad tiene que ser E.164 de verdad.
  -- Mínimo 10 dígitos contando el indicativo: con 8 se colaba un
  -- "+50123456" que no corresponde a ningún país.
  CONSTRAINT identidades_telefono_valido CHECK (
    tipo <> 'telefono_e164' OR valor ~ '^\+[1-9][0-9]{9,14}$'
  )
);

-- LA llave de identidad. Dos personas no pueden compartir el mismo
-- teléfono, ni el mismo username, ni el mismo id de Kommo — pero el
-- mismo texto SÍ puede existir con tipos distintos sin colisionar.
CREATE UNIQUE INDEX identidades_uniq
  ON crm.identidades (inmobiliaria_id, tipo, valor);

CREATE INDEX identidades_contacto
  ON crm.identidades (contacto_id, tipo);

ALTER TABLE crm.identidades ENABLE ROW LEVEL SECURITY;

CREATE POLICY identidades_select ON crm.identidades
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());

CREATE POLICY identidades_insert ON crm.identidades
  FOR INSERT TO authenticated
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria());

CREATE POLICY identidades_delete ON crm.identidades
  FOR DELETE TO authenticated
  USING (
    inmobiliaria_id = public.get_my_inmobiliaria()
    AND public.get_my_role() = 'admin'
  );

-- ---------------------------------------------------------------------
-- La llave se muda: `contactos.telefono_e164` deja de ser única.
--
-- No se borra la columna: pasa a ser el TELÉFONO PRINCIPAL CACHEADO, que
-- es lo que la lista y la ficha muestran y por lo que se ordena. La
-- unicidad vive ahora en crm.identidades.
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS crm.contactos_telefono_uniq;

COMMENT ON COLUMN crm.contactos.telefono_e164 IS
  'Teléfono principal CACHEADO para mostrar, buscar y ordenar. No es la llave: la unicidad vive en crm.identidades. Lo mantiene un trigger.';

-- ---------------------------------------------------------------------
-- Mantener el caché al día.
--
-- Si alguien tiene dos teléfonos, gana el más reciente: la gente cambia
-- de número, y el CRM debe mostrar al que hay que llamar hoy.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.sincronizar_telefono_principal()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_contacto uuid := COALESCE(NEW.contacto_id, OLD.contacto_id);
BEGIN
  UPDATE crm.contactos c
     SET telefono_e164 = (
           SELECT i.valor
             FROM crm.identidades i
            WHERE i.contacto_id = v_contacto
              AND i.tipo = 'telefono_e164'
            ORDER BY i.created_at DESC, i.id DESC
            LIMIT 1
         )
   WHERE c.id = v_contacto;
  RETURN NULL;
END $$;

CREATE TRIGGER identidades_sincronizar_telefono
  AFTER INSERT OR UPDATE OR DELETE ON crm.identidades
  FOR EACH ROW EXECUTE FUNCTION crm.sincronizar_telefono_principal();

-- ---------------------------------------------------------------------
-- crm.resolver_contacto — el ÚNICO camino para reconocer a alguien.
--
-- Recibe todas las identidades que se conocen de una persona y devuelve
-- el contacto, creándolo si hace falta. Buscar por cualquiera de ellas,
-- en orden de precedencia, es lo que evita duplicar a quien llega hoy
-- por WhatsApp sin número y mañana por un formulario con teléfono.
--
-- SECURITY DEFINER porque lo llaman los triggers de proyección y el
-- backfill, que corren fuera de una sesión de usuario. Por eso recibe la
-- inmobiliaria explícita: aquí la RLS no protege, y quien llama responde.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.resolver_contacto(
  p_inmobiliaria_id uuid,
  p_identidades jsonb,          -- [{"tipo":"telefono_e164","valor":"+57…"}, …]
  p_nombre text DEFAULT NULL,
  p_origen text DEFAULT NULL,
  p_tipo_contacto text DEFAULT 'cliente',
  p_telefono_crudo text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  -- Orden de precedencia al buscar. El teléfono manda porque es la
  -- identidad más estable y la que comparten más fuentes.
  v_orden constant text[] := ARRAY[
    'telefono_e164', 'whatsapp_username', 'kommo_lead',
    'kommo_contact', 'email', 'meta_psid', 'otro'
  ];
  v_tipo      text;
  v_contacto  uuid;
  v_ident     jsonb;
BEGIN
  IF p_identidades IS NULL OR jsonb_array_length(p_identidades) = 0 THEN
    -- Sin ninguna forma de reconocer a la persona no se crea nada: un
    -- contacto irreconocible es basura que nadie podrá fusionar después.
    RETURN NULL;
  END IF;

  -- 1) ¿Ya lo conocemos por alguna de estas identidades?
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

  -- 2) Si no, es alguien nuevo.
  IF v_contacto IS NULL THEN
    INSERT INTO crm.contactos (inmobiliaria_id, nombre, origen, tipo, telefono_crudo)
    VALUES (p_inmobiliaria_id, p_nombre, p_origen,
            COALESCE(p_tipo_contacto, 'cliente'), p_telefono_crudo)
    RETURNING id INTO v_contacto;
  ELSE
    -- Completar lo que faltaba, sin pisar lo que ya había: el dato más
    -- viejo suele ser el que alguien verificó a mano.
    UPDATE crm.contactos
       SET nombre         = COALESCE(nombre, p_nombre),
           origen         = COALESCE(origen, p_origen),
           telefono_crudo = COALESCE(telefono_crudo, p_telefono_crudo)
     WHERE id = v_contacto;
  END IF;

  -- 3) Enlazar todas las identidades conocidas.
  --
  -- ON CONFLICT DO NOTHING cubre dos casos: que ya estuviera enlazada a
  -- ESTE contacto (normal), o que pertenezca a OTRO. Lo segundo es un
  -- candidato a fusión y hoy se deja quieto a propósito: fusionar mal es
  -- el daño que no se deshace. Se resolverá con reglas explícitas cuando
  -- haya casos reales que mirar.
  FOR v_ident IN SELECT * FROM jsonb_array_elements(p_identidades) LOOP
    INSERT INTO crm.identidades (inmobiliaria_id, contacto_id, tipo, valor, origen)
    VALUES (p_inmobiliaria_id, v_contacto,
            v_ident->>'tipo', v_ident->>'valor', p_origen)
    ON CONFLICT (inmobiliaria_id, tipo, valor) DO NOTHING;
  END LOOP;

  RETURN v_contacto;
END $$;

COMMENT ON FUNCTION crm.resolver_contacto(uuid, jsonb, text, text, text, text) IS
  'Reconoce o crea a una persona a partir de cualquiera de sus identidades. Único camino de identidad del CRM: triggers y backfill pasan por aquí.';

GRANT EXECUTE ON FUNCTION crm.resolver_contacto(uuid, jsonb, text, text, text, text)
  TO authenticated, service_role;
