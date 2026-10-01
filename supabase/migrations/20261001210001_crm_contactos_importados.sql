-- =====================================================================
-- La cuarentena de la libreta del celular. CONSTRUIDA, NO CONECTADA.
--
-- DECISIÓN 26 (1 oct 2026)
-- Al pedir `smb_app_state_sync`, Meta manda la libreta de contactos del
-- celular en el que vive el número: `full_name`, `first_name`,
-- `phone_number` y `action` (add / remove). Es la libreta de alguien del
-- equipo, con sus contactos PERSONALES adentro. No va a crm.contactos:
-- va a una cuarentena, con la línea de origen y la fecha, sin fusión
-- automática con nada. Pasa a contacto de verdad solo si coincide con
-- una conversación existente o si alguien la revisa y la promueve.
--
-- NADA LA ALIMENTA, Y NO PUEDE
-- En Colombia el tratamiento de datos personales tiene reglas propias, y
-- la decisión de importar esa libreta es de Cumbres, no nuestra. Hasta
-- que Cumbres dé el visto bueno legal:
--   · no hay función que escriba aquí, ni trigger, ni nada;
--   · NI service_role puede insertar: se le retira el permiso. La
--     plataforma no podría alimentarla aunque se equivocara;
--   · la prueba 35 tumba cualquier función de `crm` que mencione esta
--     tabla. Activarla exige tocar esa prueba a sabiendas.
-- Activar la cuarentena = una migración nueva que cree la función de
-- ingesta para service_role, con el visto bueno anotado en el vault.
--
-- Borrar SÍ se puede siempre: retirar datos personales nunca puede
-- quedar bloqueado. Y borrar la línea borra su libreta en cascada.
-- =====================================================================

CREATE TABLE crm.contactos_importados (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  inmobiliaria_id uuid NOT NULL
    REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,

  -- De qué libreta salió. Si la línea se borra, su libreta se va con
  -- ella: no hay razón para guardar la libreta de un celular que ya no
  -- está conectado.
  linea_id uuid NOT NULL REFERENCES crm.lineas(id) ON DELETE CASCADE,

  -- Lo que mandó Meta, tal cual, y su versión normalizada. La E.164 puede
  -- fallar —un número fijo, uno extranjero mal escrito— y entonces queda
  -- NULL: un importado sin teléfono utilizable no coincide con nadie.
  telefono_crudo text NOT NULL,
  telefono_e164  text,
  nombre         text,   -- full_name
  nombre_corto   text,   -- first_name

  -- Cuándo lo dijo Meta (metadata.timestamp) y cuándo llegó aquí.
  meta_at     timestamptz,
  recibido_at timestamptz NOT NULL DEFAULT now(),

  -- Salir de la cuarentena. Las dos únicas puertas de la decisión 26:
  --   coincidencia  el teléfono ya tenía conversación en el CRM
  --   manual        alguien lo revisó y lo promovió a mano
  contacto_id    uuid REFERENCES crm.contactos(id) ON DELETE SET NULL,
  promovido_at   timestamptz,
  promovido_como text CHECK (promovido_como IN ('coincidencia', 'manual')),
  promovido_por  uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,

  -- Una vez por número y por libreta: un `add` repetido no duplica.
  CONSTRAINT contactos_importados_uno_por_libreta
    UNIQUE (linea_id, telefono_crudo),

  -- Promovido o no, pero no a medias.
  CONSTRAINT contactos_importados_promocion_completa CHECK (
    (promovido_at IS NULL AND promovido_como IS NULL AND promovido_por IS NULL)
    OR (promovido_at IS NOT NULL AND promovido_como IS NOT NULL)),

  -- Una promoción manual tiene autor: "alguien lo revisó" es una persona.
  CONSTRAINT contactos_importados_manual_con_autor CHECK (
    promovido_como IS DISTINCT FROM 'manual' OR promovido_por IS NOT NULL)
);

COMMENT ON TABLE crm.contactos_importados IS
  'Cuarentena de la libreta del celular (smb_app_state_sync), decisión 26. CONSTRUIDA PERO NO CONECTADA: nada la alimenta hasta el visto bueno legal de Cumbres, y ni service_role puede insertar. Activarla es una migración aparte.';

ALTER TABLE crm.contactos_importados ENABLE ROW LEVEL SECURITY;

-- Solo la ven los admin de la inmobiliaria. Es la libreta personal de
-- alguien del equipo: que cualquier asesor pueda hojearla es justo lo que
-- la cuarentena viene a evitar.
CREATE POLICY contactos_importados_select ON crm.contactos_importados
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria()
         AND public.get_my_role() = 'admin');

-- Un admin puede vaciarla: retirar datos personales nunca se bloquea.
CREATE POLICY contactos_importados_delete ON crm.contactos_importados
  FOR DELETE TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria()
         AND public.get_my_role() = 'admin');

-- Los permisos, uno por uno y a la vista. Los privilegios por defecto del
-- esquema darían a authenticated y a service_role todo; aquí se deja solo
-- leer y borrar.
REVOKE ALL ON crm.contactos_importados FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, DELETE ON crm.contactos_importados TO authenticated, service_role;
