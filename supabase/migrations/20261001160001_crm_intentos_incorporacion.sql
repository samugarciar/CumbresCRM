-- =====================================================================
-- Cada intento de incorporar un número, con el error de Meta tal cual.
--
-- DECISIÓN 28, fijada por el autor del brief (1 oct 2026)
-- La incorporación en coexistencia falla de formas concretas: el número
-- no tiene actividad suficiente, ya está en otra cuenta o portafolio, el
-- país no está soportado, está en espera tras una desconexión. Y cada
-- intento se gasta sobre un NÚMERO REAL — no hay entorno de prueba para
-- la coexistencia. Guardar solo la línea conectada deja ciego justo el
-- caso que más duele: el que falló, y por qué.
--
-- "TAL CUAL" SIGNIFICA EL OBJETO ENTERO
-- Meta no devuelve los errores con una sola forma. La Graph API manda
-- `{ code, error_subcode, message, fbtrace_id, … }`; el registro integrado
-- del navegador manda `{ error_id, error_message, session_id, … }`. Una
-- columna `codigo` rellenada leyendo un campo fijo perdería uno de los
-- dos. Por eso:
--   · `error` guarda el objeto de Meta COMPLETO, sin tocar;
--   · `error_codigo` es el código tal como lo leyó la plataforma, que es
--     quien sabe qué forma le llegó. En texto: no se convierte a número,
--     porque convertir es interpretar.
-- Ninguna de las dos se traduce a una frase en español. Eso lo hará una
-- pantalla, si la hay, con el dato original intacto debajo.
--
-- LA ÚNICA EXCEPCIÓN A "TAL CUAL": UN TOKEN
-- Si en el objeto aparece algo con la forma de un token de Meta, se
-- sustituye por '[token retirado]' y se marca la fila. Es el ajuste a la
-- decisión 23: el token no puede aparecer nunca en logs ni en errores, y
-- esta tabla la puede leer cualquiera de la inmobiliaria. Un error de
-- Meta no debería traerlo, pero un fallo en la plataforma —pasar el
-- contexto entero de la petición en vez del error— sí podría, y
-- guardarlo aquí sería repartirlo entre todo el equipo. Se prefiere
-- retirarlo y CONSERVAR el intento, porque el intento es justo lo que
-- esta tabla existe para no perder; la marca dice que algo se tocó.
-- =====================================================================

CREATE TABLE crm.intentos_incorporacion (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  inmobiliaria_id uuid NOT NULL
    REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,

  -- El embudo y no la línea: un intento puede fallar ANTES de que la
  -- línea exista, y la historia de intentos tiene que sobrevivir a que
  -- se borre una línea. Por eso tampoco hay foránea a crm.lineas.
  embudo text NOT NULL REFERENCES crm.embudos(codigo),

  resultado text NOT NULL
    CHECK (resultado IN ('exito', 'error', 'cancelado')),

  error_codigo text,
  error        jsonb,

  -- Lo que se sepa del número en ese momento. Puede no saberse nada: el
  -- registro puede fallar antes de que Meta asigne ningún id.
  wa_phone_number_id text,
  waba_id            text,

  -- Cuándo pasó, según la plataforma, y cuándo se anotó aquí. Distintos a
  -- propósito: un intento que se anota con retraso no cambia de fecha.
  ocurrido_at   timestamptz NOT NULL DEFAULT now(),
  registrado_at timestamptz NOT NULL DEFAULT now(),

  token_retirado boolean NOT NULL DEFAULT false,

  -- Un intento fallido sin el error de Meta no sirve para nada: es lo
  -- único que esta tabla tiene que no tenga la línea.
  CONSTRAINT intentos_error_con_su_error
    CHECK (resultado <> 'error' OR error IS NOT NULL),

  -- Un éxito con error es una contradicción, no un dato.
  CONSTRAINT intentos_exito_sin_error
    CHECK (resultado <> 'exito' OR (error IS NULL AND error_codigo IS NULL)),

  -- Un código sin el objeto de donde salió no se puede comprobar.
  CONSTRAINT intentos_codigo_con_su_error
    CHECK (error_codigo IS NULL OR error IS NOT NULL)
);

COMMENT ON TABLE crm.intentos_incorporacion IS
  'Cada intento de incorporar un número a la Cloud API, con el error de Meta tal cual. Decisión 28. Solo la escribe la plataforma (service_role), por crm.registrar_intento_incorporacion().';

-- Para la pregunta de la pantalla de líneas: qué pasó las últimas veces
-- en este embudo.
CREATE INDEX intentos_incorporacion_embudo
  ON crm.intentos_incorporacion (inmobiliaria_id, embudo, ocurrido_at DESC);

ALTER TABLE crm.intentos_incorporacion ENABLE ROW LEVEL SECURITY;

-- Se lee como las líneas: cualquiera de la inmobiliaria. Saber por qué no
-- entra un número no es un secreto, y quien llama a Meta para resolverlo
-- puede no ser admin.
--
-- NO hay política de escritura, a propósito: un intento lo anota la
-- plataforma, que usa service_role y no pasa por la RLS. Nadie con sesión
-- de usuario puede fabricar ni borrar un intento.
CREATE POLICY intentos_select ON crm.intentos_incorporacion
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());

-- ---------------------------------------------------------------------
-- El contrato con la plataforma
--
-- La llama por cada intento de incorporación, termine como termine. No
-- es idempotente, y es deliberado: dos intentos iguales son dos intentos
-- gastados sobre el mismo número, y contarlos es exactamente la idea.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.registrar_intento_incorporacion(
  p_inmobiliaria_id    uuid,
  p_embudo             text,
  p_resultado          text,
  p_error_codigo       text        DEFAULT NULL,
  p_error              jsonb       DEFAULT NULL,
  p_wa_phone_number_id text        DEFAULT NULL,
  p_waba_id            text        DEFAULT NULL,
  p_ocurrido_at        timestamptz DEFAULT now())
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $intento$
DECLARE
  -- La forma de un token de Meta: empieza por EAA y es muy largo. Treinta
  -- caracteres de margen para no confundirlo con un id corto.
  c_token constant text := 'EAA[A-Za-z0-9]{30,}';
  v_error  jsonb   := p_error;
  v_codigo text    := p_error_codigo;
  v_tocado boolean := false;
  v_id     uuid;
BEGIN
  IF v_error IS NOT NULL AND v_error::text ~ c_token THEN
    v_error  := regexp_replace(v_error::text, c_token, '[token retirado]', 'g')::jsonb;
    v_tocado := true;
  END IF;

  IF v_codigo IS NOT NULL AND v_codigo ~ c_token THEN
    v_codigo := regexp_replace(v_codigo, c_token, '[token retirado]', 'g');
    v_tocado := true;
  END IF;

  INSERT INTO crm.intentos_incorporacion
    (inmobiliaria_id, embudo, resultado, error_codigo, error,
     wa_phone_number_id, waba_id, ocurrido_at, token_retirado)
  VALUES
    (p_inmobiliaria_id, p_embudo, p_resultado, v_codigo, v_error,
     p_wa_phone_number_id, p_waba_id,
     -- Un reloj adelantado no puede fechar un intento en el futuro.
     LEAST(COALESCE(p_ocurrido_at, now()), now()),
     v_tocado)
  RETURNING id INTO v_id;

  RETURN v_id;
END $intento$;

COMMENT ON FUNCTION crm.registrar_intento_incorporacion(uuid, text, text, text, jsonb, text, text, timestamptz) IS
  'Contrato con la plataforma: anota un intento de incorporación, termine como termine (exito, error, cancelado). El error de Meta se guarda ENTERO y sin traducir; lo único que se retira es lo que tenga forma de token. Solo service_role.';

-- Escribe por el sistema: cerrada a cualquier sesión de usuario. Sin esto
-- nacería abierta —Postgres da EXECUTE a PUBLIC en toda función nueva— y
-- cualquier asesor podría fabricar intentos desde el navegador.
REVOKE ALL ON FUNCTION crm.registrar_intento_incorporacion(uuid, text, text, text, jsonb, text, text, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION crm.registrar_intento_incorporacion(uuid, text, text, text, jsonb, text, text, timestamptz)
  TO service_role;
