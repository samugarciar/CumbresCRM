-- =====================================================================
-- Fase 5-A — Plantillas de mensaje.
--
-- POR QUÉ LAS PLANTILLAS NO SON UN EXTRA DE COMODIDAD
-- WhatsApp tiene una ventana de 24 horas: pasado ese plazo desde el
-- último mensaje del cliente, solo se pueden enviar plantillas aprobadas
-- por Meta. Texto libre, no.
--
-- Y casi todo el público está fuera de esa ventana. Medido en producción:
--   981 de 982 conversaciones terminan con un mensaje NUESTRO
--   670 llevan más de 14 días en silencio
--   303 se cerraron solas por 30 días de silencio
--
-- La bandeja de reactivación —lo que la investigación llamó "probablemente
-- la fuente de ingreso más barata del proyecto"— es ENTERAMENTE tráfico
-- fuera de ventana. Así que las plantillas no son la comodidad: son el
-- único camino legal para lo que más valor tiene.
--
-- QUÉ SE CONSTRUYE AQUÍ Y QUÉ NO
-- Esto es todo lo que NO depende de con quién se envíe: la plantilla, sus
-- variables, el relleno con datos reales y el registro. El transporte
-- —n8n o la Cloud API de Meta— es una decisión de Samuel y se conecta
-- después sin tocar nada de esto.
--
-- ⚠️ La política de plantillas hay que confirmarla contra la
-- documentación vigente de Meta antes de conectar el envío, no contra lo
-- que nadie recuerde.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Las variables que existen
--
-- Catálogo CERRADO a propósito. Una plantilla que menciona {{descuento}}
-- —que no existe— se enviaría con el hueco sin rellenar a un cliente
-- real. Mejor que reviente al guardarla que delante de la persona.
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
    'habitaciones'
  ];
$vd$;

-- Las que una plantilla usa y no existen. Vacío = se puede guardar.
CREATE OR REPLACE FUNCTION crm.variables_desconocidas(p_cuerpo text)
RETURNS text[]
LANGUAGE sql IMMUTABLE SET search_path = ''
AS $vx$
  SELECT COALESCE(array_agg(DISTINCT v), ARRAY[]::text[])
  FROM (
    SELECT (regexp_matches(COALESCE(p_cuerpo, ''), '\{\{\s*([a-z_]+)\s*\}\}', 'g'))[1] AS v
  ) x
  WHERE NOT (v = ANY (crm.variables_disponibles()));
$vx$;

CREATE TABLE crm.plantillas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  inmobiliaria_id uuid NOT NULL
    REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,

  nombre text NOT NULL CHECK (btrim(nombre) <> ''),
  cuerpo text NOT NULL CHECK (btrim(cuerpo) <> ''),

  -- Meta clasifica las plantillas y la categoría cambia lo que se puede
  -- decir y cuánto cuesta. Reactivar a alguien dormido es marketing;
  -- confirmar una visita que él pidió es utilidad.
  categoria text NOT NULL DEFAULT 'utilidad'
    CHECK (categoria IN ('utilidad', 'marketing')),

  -- Dónde va en el trámite con Meta. Declarativo mientras no haya API:
  -- el CRM no puede verificarlo solo, y fingir que sí sería peor que
  -- decir "esto lo escribió alguien a mano".
  estado_meta text NOT NULL DEFAULT 'borrador'
    CHECK (estado_meta IN ('borrador', 'enviada', 'aprobada', 'rechazada')),
  -- El nombre EXACTO con el que está dada de alta en Meta. Sin esto no se
  -- puede mandar aunque esté aprobada.
  nombre_meta text,

  activa boolean NOT NULL DEFAULT true,

  creada_por uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Que reviente aquí y no delante del cliente.
  CONSTRAINT plantillas_variables_existen
    CHECK (cardinality(crm.variables_desconocidas(cuerpo)) = 0),

  -- Aprobada sin nombre en Meta es una plantilla que no se puede usar.
  CONSTRAINT plantillas_aprobada_con_nombre
    CHECK (estado_meta <> 'aprobada' OR btrim(COALESCE(nombre_meta, '')) <> '')
);

CREATE UNIQUE INDEX plantillas_nombre_unico
  ON crm.plantillas (inmobiliaria_id, lower(btrim(nombre)))
  WHERE activa;

ALTER TABLE crm.plantillas ENABLE ROW LEVEL SECURITY;

CREATE POLICY plantillas_select ON crm.plantillas
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());

-- Escribir plantillas es de admin: una plantilla mal escrita sale a
-- cientos de clientes de golpe, y eso no se deshace.
CREATE POLICY plantillas_escribir ON crm.plantillas
  FOR ALL TO authenticated
  USING (
    inmobiliaria_id = public.get_my_inmobiliaria()
    AND public.get_my_role() = 'admin'
  )
  WITH CHECK (
    inmobiliaria_id = public.get_my_inmobiliaria()
    AND public.get_my_role() = 'admin'
  );

COMMENT ON TABLE crm.plantillas IS
  'Mensajes reutilizables con variables. Fuera de la ventana de 24h de WhatsApp son el único envío posible.';

-- ---------------------------------------------------------------------
-- Rellenar una plantilla con datos de verdad
--
-- Vive en la base y no en la aplicación a propósito: hoy la usa la
-- pantalla, mañana el agente. Dos renderizadores es como el asesor y el
-- bot acaban mandando textos distintos con la misma plantilla.
--
-- Lo que falta se deja VISIBLE como «[sin precio]» en vez de vacío: un
-- hueco silencioso se cuela hasta el cliente; un corchete lo para el
-- asesor antes de copiar.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.render_plantilla(
  p_plantilla_id uuid,
  p_contacto_id  uuid DEFAULT NULL,
  p_inmueble_id  uuid DEFAULT NULL,
  p_asesor       text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path = ''
AS $render$
DECLARE
  v_cuerpo text;
  c record;
  i record;
BEGIN
  SELECT p.cuerpo INTO v_cuerpo
    FROM crm.plantillas p WHERE p.id = p_plantilla_id AND p.activa;
  IF v_cuerpo IS NULL THEN RETURN NULL; END IF;

  SELECT ct.nombre, ct.telefono_e164 INTO c
    FROM crm.contactos ct WHERE ct.id = p_contacto_id;

  SELECT v.titulo, v.barrio, v.ciudad, v.precio, v.habitaciones INTO i
    FROM crm.v_inmuebles v WHERE v.id = p_inmueble_id;

  v_cuerpo := regexp_replace(v_cuerpo, '\{\{\s*nombre\s*\}\}',
                COALESCE(NULLIF(btrim(c.nombre), ''), '[sin nombre]'), 'g');
  v_cuerpo := regexp_replace(v_cuerpo, '\{\{\s*telefono\s*\}\}',
                COALESCE(c.telefono_e164, '[sin teléfono]'), 'g');
  v_cuerpo := regexp_replace(v_cuerpo, '\{\{\s*asesor\s*\}\}',
                COALESCE(NULLIF(btrim(p_asesor), ''), '[asesor]'), 'g');
  v_cuerpo := regexp_replace(v_cuerpo, '\{\{\s*inmueble\s*\}\}',
                COALESCE(i.titulo, '[sin inmueble]'), 'g');
  v_cuerpo := regexp_replace(v_cuerpo, '\{\{\s*barrio\s*\}\}',
                COALESCE(i.barrio, '[sin barrio]'), 'g');
  v_cuerpo := regexp_replace(v_cuerpo, '\{\{\s*ciudad\s*\}\}',
                COALESCE(i.ciudad, '[sin ciudad]'), 'g');
  -- Separador de miles forzado a punto: 'G' usa el del locale del
  -- servidor, que en esta base es la coma. "$1,500,000" se lee mal aquí.
  v_cuerpo := regexp_replace(v_cuerpo, '\{\{\s*precio\s*\}\}',
                COALESCE('$' || replace(to_char(i.precio, 'FM999G999G999'), ',', '.'),
                         '[sin precio]'), 'g');
  v_cuerpo := regexp_replace(v_cuerpo, '\{\{\s*habitaciones\s*\}\}',
                COALESCE(i.habitaciones::text, '[sin dato]'), 'g');

  RETURN v_cuerpo;
END $render$;

GRANT SELECT ON crm.plantillas TO authenticated;
GRANT EXECUTE ON FUNCTION crm.render_plantilla(uuid, uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION crm.variables_disponibles() TO authenticated;
GRANT EXECUTE ON FUNCTION crm.variables_desconocidas(text) TO authenticated;

-- ---------------------------------------------------------------------
-- El registro de envíos
--
-- Nace vacía y se queda vacía hasta que haya transporte. Está aquí porque
-- el día que se pueda enviar hay que poder responder "¿ya le escribimos a
-- esta persona?" desde el primer envío, no desde el momento en que a
-- alguien se le ocurra registrarlo.
--
-- COPIAR NO ES ENVIAR, y no se registra como tal. Que un asesor copie el
-- texto al portapapeles no prueba que lo mandara — anotarlo aquí sería
-- inventar un hecho, el mismo error que ya se corrigió con las visitas
-- retroactivas.
-- ---------------------------------------------------------------------
CREATE TABLE crm.envios (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  inmobiliaria_id uuid NOT NULL
    REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,
  contacto_id  uuid NOT NULL REFERENCES crm.contactos(id) ON DELETE CASCADE,
  plantilla_id uuid REFERENCES crm.plantillas(id) ON DELETE SET NULL,
  inmueble_id  uuid REFERENCES public.inmuebles(id) ON DELETE SET NULL,

  -- El texto EXACTO que salió, no la plantilla. La plantilla se edita; lo
  -- que se le dijo a una persona no cambia nunca.
  cuerpo text NOT NULL,

  -- Por dónde salió. Se llena cuando exista transporte.
  canal text CHECK (canal IN ('n8n', 'meta')),
  estado text NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'enviado', 'fallido')),
  error text,

  enviado_por uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  enviado_at timestamptz
);

CREATE INDEX envios_contacto ON crm.envios (contacto_id, created_at DESC);

ALTER TABLE crm.envios ENABLE ROW LEVEL SECURITY;

CREATE POLICY envios_select ON crm.envios
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());

CREATE POLICY envios_insert ON crm.envios
  FOR INSERT TO authenticated
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria());

COMMENT ON TABLE crm.envios IS
  'Qué se le mandó a quién, con el texto exacto que salió. Vacía hasta que haya transporte: copiar no es enviar.';

-- ---------------------------------------------------------------------
-- Tres plantillas de partida
--
-- Se siembran porque una pantalla de plantillas vacía no enseña nada:
-- nadie sabe qué forma tiene una plantilla hasta que ve una. Son las tres
-- conversaciones que el negocio ya tiene todos los días.
-- ---------------------------------------------------------------------
-- Va en una FUNCIÓN y no en un INSERT suelto porque las migraciones
-- corren ANTES que seed.sql: en local `public.inmobiliarias` está vacía
-- cuando esto se aplica, así que un insert directo no sembraría nada.
-- En producción sí habría funcionado — que es peor, porque el fallo solo
-- aparecería donde no se prueba. Idempotente: se puede llamar cuando se
-- dé de alta una inmobiliaria nueva.
CREATE OR REPLACE FUNCTION crm.sembrar_plantillas()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $sembrar$
DECLARE v_n integer;
BEGIN
INSERT INTO crm.plantillas (inmobiliaria_id, nombre, cuerpo, categoria)
SELECT i.id, p.nombre, p.cuerpo, p.categoria
FROM public.inmobiliarias i
CROSS JOIN (VALUES
  ('Recomendación de inmueble',
   E'Hola {{nombre}}, soy {{asesor}} de Cumbres.\n\n'
   'Me acordé de lo que estabas buscando y nos entró esto:\n\n'
   '{{inmueble}}\n{{barrio}}, {{ciudad}}\n{{habitaciones}} habitaciones · {{precio}}\n\n'
   '¿Te sirve que coordinemos una visita?',
   'marketing'),
  ('Recordatorio de visita',
   E'Hola {{nombre}}, te escribo de Cumbres para confirmar tu visita a {{inmueble}} en {{barrio}}.\n\n'
   '¿Sigue en pie?',
   'utilidad'),
  ('Retomar contacto',
   E'Hola {{nombre}}, soy {{asesor}} de Cumbres.\n\n'
   'Hace un tiempo estuviste buscando con nosotros. ¿Sigues interesado? '
   'Tenemos opciones nuevas y me encantaría mostrarte.',
   'marketing')
) AS p(nombre, cuerpo, categoria)
WHERE NOT EXISTS (
  SELECT 1 FROM crm.plantillas x
   WHERE x.inmobiliaria_id = i.id
     AND lower(btrim(x.nombre)) = lower(btrim(p.nombre))
     AND x.activa
);
GET DIAGNOSTICS v_n = ROW_COUNT;
RETURN v_n;
END $sembrar$;

REVOKE ALL ON FUNCTION crm.sembrar_plantillas() FROM public, anon, authenticated;

-- En producción las inmobiliarias ya existen, así que esto siembra de
-- verdad. En local no hace nada y lo llama seed.sql después.
SELECT crm.sembrar_plantillas();
