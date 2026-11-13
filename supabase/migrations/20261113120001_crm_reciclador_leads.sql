-- =====================================================================
-- El reciclador de leads (13 nov 2026)
--
-- LO QUE PIDIÓ SAMUEL
-- Que el CRM le escriba solo, con una plantilla aprobada por Meta, a las
-- conversaciones que se murieron, y que desde la pantalla se pueda
-- encender, apagar y cambiar el tiempo.
--
-- LAS DECISIONES (13 nov, Samuel)
--   · Las horas son silencio UNIDIRECCIONAL: nosotros (el bot o una
--     persona del equipo) escribimos de último y el cliente no contesta.
--     Al que nos dejó esperando a NOSOTROS no se le recicla: esa falla es
--     nuestra y la cubre crm.esperando_desde (el 🔥 de la bandeja).
--   · Máximo 2 intentos por silencio. Si la persona contesta, el conteo
--     vuelve a cero: es otro silencio.
--   · Mira 7 días hacia atrás como mucho. Encenderlo no despierta el
--     histórico entero de golpe.
--   · Plantilla genérica por ahora (sin lo que pidió ni lo que le calza).
--
-- CÓMO ENCAJA CON LO QUE YA HABÍA
--   · Sale por el mismo tubo que los envíos masivos: una fila en
--     crm.envios y crm.pedir_envio_a_plataforma (pg_net) contra
--     /api/whatsapp/enviar. La respuesta la anota
--     crm.anotar_respuestas_plataforma, que se amplía aquí para lo que no
--     es de un envío masivo.
--   · El cuerpo lleva `origen: 'reciclador'`. La plataforma, con eso, NO
--     anota relevo: si lo anotara, el bot se callaría 30 minutos justo
--     cuando el lead revive y contesta.
--   · El horario y los festivos son los de los envíos masivos
--     (crm.en_horario_envio).
--   · Modo simulación: calcula y anota a quién le escribiría, sin mandar
--     nada. Así se enciende primero en seco y se mira la lista.
--
-- LA REGLA vive en crm.candidatos_reciclaje y en ningún otro sitio: la
-- usan la vista previa de la pantalla y el despachador.
--
-- Idempotente en lo que se puede (CREATE OR REPLACE); las tablas son nuevas.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1 · La configuración: una fila por línea
-- ---------------------------------------------------------------------
CREATE TABLE crm.reciclador_config (
  linea_id uuid PRIMARY KEY REFERENCES crm.lineas(id) ON DELETE CASCADE,
  inmobiliaria_id uuid NOT NULL
    REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,

  activo     boolean NOT NULL DEFAULT false,
  simulacion boolean NOT NULL DEFAULT true,

  horas_silencio int NOT NULL DEFAULT 12 CHECK (horas_silencio BETWEEN 1 AND 168),
  max_intentos   int NOT NULL DEFAULT 2  CHECK (max_intentos BETWEEN 1 AND 3),
  dias_atras     int NOT NULL DEFAULT 7  CHECK (dias_atras BETWEEN 1 AND 30),
  tope_diario    int NOT NULL DEFAULT 50 CHECK (tope_diario BETWEEN 1 AND 1000),

  plantilla_id uuid REFERENCES crm.plantillas(id) ON DELETE SET NULL,

  horario jsonb NOT NULL DEFAULT '{
      "zona": "America/Bogota",
      "franjas": {
        "1": ["08:00", "18:00"], "2": ["08:00", "18:00"], "3": ["08:00", "18:00"],
        "4": ["08:00", "18:00"], "5": ["08:00", "18:00"], "6": ["08:00", "13:00"]
      }
    }'::jsonb
    CHECK (crm.horario_valido(horario)),

  -- Lo último que el despachador quiere que alguien sepa.
  ultimo_aviso text,
  ultima_pasada_at timestamptz,

  -- Quién lo tocó. Sin llave a public.usuarios a propósito: quien actúa
  -- puede no ser una persona (decisión de integración con el agente).
  actualizado_por uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE crm.reciclador_config IS
  'El reciclador de leads de una línea: encendido, simulación, horas de silencio, intentos, días hacia atrás, tope diario, plantilla y horario. Solo se cambia con crm.configurar_reciclador.';

CREATE TRIGGER reciclador_config_updated_at BEFORE UPDATE ON crm.reciclador_config
  FOR EACH ROW EXECUTE FUNCTION crm.tocar_updated_at();

ALTER TABLE crm.reciclador_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY reciclador_config_select ON crm.reciclador_config
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = (SELECT public.get_my_inmobiliaria()));
-- Escribir: solo un admin de la inmobiliaria, y solo por
-- crm.configurar_reciclador (el disparador de abajo).
CREATE POLICY reciclador_config_insert ON crm.reciclador_config
  FOR INSERT TO authenticated
  WITH CHECK (inmobiliaria_id = (SELECT public.get_my_inmobiliaria())
              AND (SELECT public.get_my_role()) = 'admin');
CREATE POLICY reciclador_config_update ON crm.reciclador_config
  FOR UPDATE TO authenticated
  USING (inmobiliaria_id = (SELECT public.get_my_inmobiliaria())
         AND (SELECT public.get_my_role()) = 'admin')
  WITH CHECK (inmobiliaria_id = (SELECT public.get_my_inmobiliaria())
              AND (SELECT public.get_my_role()) = 'admin');
REVOKE ALL ON crm.reciclador_config FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON crm.reciclador_config TO authenticated;

-- La RLS no distingue columnas: sin esto, un admin podría escribir la
-- fila a mano desde el navegador y saltarse las validaciones de la
-- función (plantilla de la línea, variables, aprobación). Mismo patrón
-- que crm.envios_masivos.
CREATE OR REPLACE FUNCTION crm.reciclador_solo_por_funciones()
RETURNS trigger
LANGUAGE plpgsql SET search_path = ''
AS $rsf$
BEGIN
  IF pg_trigger_depth() = 1
     AND current_setting('crm.reciclador', true) IS DISTINCT FROM 'si' THEN
    RAISE EXCEPTION 'El reciclador solo se configura con crm.configurar_reciclador'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $rsf$;

CREATE TRIGGER reciclador_config_solo_por_funciones
  BEFORE INSERT OR UPDATE ON crm.reciclador_config
  FOR EACH ROW EXECUTE FUNCTION crm.reciclador_solo_por_funciones();

-- ---------------------------------------------------------------------
-- 2 · Los intentos: uno por mensaje que mandó (o habría mandado)
-- ---------------------------------------------------------------------
CREATE TABLE crm.reciclador_intentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inmobiliaria_id uuid NOT NULL
    REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,
  linea_id    uuid NOT NULL REFERENCES crm.lineas(id) ON DELETE CASCADE,
  contacto_id uuid NOT NULL REFERENCES crm.contactos(id) ON DELETE CASCADE,

  -- 1 o 2 dentro del mismo silencio.
  numero smallint NOT NULL CHECK (numero BETWEEN 1 AND 3),
  -- El mensaje nuestro que quedó sin respuesta.
  silencio_desde timestamptz NOT NULL,

  simulado boolean NOT NULL,
  envio_id uuid REFERENCES crm.envios(id) ON DELETE SET NULL,
  cuerpo text NOT NULL,

  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE crm.reciclador_intentos IS
  'Cada mensaje que el reciclador mandó (o, en simulación, habría mandado). Cuenta los intentos por silencio y mide quién respondió.';

CREATE INDEX reciclador_intentos_contacto
  ON crm.reciclador_intentos (contacto_id, linea_id, created_at DESC);
CREATE INDEX reciclador_intentos_linea
  ON crm.reciclador_intentos (linea_id, created_at DESC);
CREATE INDEX reciclador_intentos_envio
  ON crm.reciclador_intentos (envio_id) WHERE envio_id IS NOT NULL;

ALTER TABLE crm.reciclador_intentos ENABLE ROW LEVEL SECURITY;
CREATE POLICY reciclador_intentos_select ON crm.reciclador_intentos
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = (SELECT public.get_my_inmobiliaria()));
REVOKE ALL ON crm.reciclador_intentos FROM anon, authenticated;
GRANT SELECT ON crm.reciclador_intentos TO authenticated;

-- ---------------------------------------------------------------------
-- 3 · LA regla: a quién le escribiría ahora
--
-- Barre solo las actividades de la línea dentro de la ventana
-- (índice actividades_org) y, para cada contacto que queda, mira su
-- último mensaje entrante por cualquier línea (índice
-- actividades_timeline): si nos escribió por otra línea, no está muerto.
--
-- SECURITY INVOKER: la pantalla la llama como asesor y la RLS la limita a
-- su inmobiliaria; el despachador la llama como dueño.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.candidatos_reciclaje(
  p_linea_id uuid,
  p_ahora    timestamptz DEFAULT now(),
  p_limite   int DEFAULT 500)
RETURNS TABLE (
  contacto_id      uuid,
  nombre           text,
  telefono_e164    text,
  ultimo_nuestro_at timestamptz,
  ultimo_suyo_at   timestamptz,
  intento          int
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $cand$
  WITH cfg AS (
    SELECT r.horas_silencio, r.max_intentos, r.dias_atras,
           l.inmobiliaria_id, l.wa_phone_number_id AS pnid,
           -- Si la plantilla dice {{nombre}}, quien no tiene nombre no entra:
           -- Meta rechaza una variable vacía y un «Hola ,» es peor que nada.
           COALESCE(p.cuerpo ~ '\{\{\s*nombre\s*\}\}', false) AS pide_nombre
      FROM crm.reciclador_config r
      JOIN crm.lineas l ON l.id = r.linea_id
      LEFT JOIN crm.plantillas p ON p.id = r.plantilla_id
     WHERE r.linea_id = p_linea_id
  ),
  -- Lo que pasó por la línea dentro de la ventana, por persona.
  recientes AS (
    SELECT a.contacto_id,
           max(a.ocurrido_at) FILTER (WHERE a.tipo = 'mensaje_saliente') AS ult_nuestro
      FROM cfg
      JOIN crm.actividades a
        ON a.inmobiliaria_id = cfg.inmobiliaria_id
       AND a.ocurrido_at >= p_ahora - make_interval(days => cfg.dias_atras)
       AND a.ocurrido_at <= p_ahora
     WHERE a.wa_phone_number_id = cfg.pnid
       AND a.contacto_id IS NOT NULL
       AND a.tipo IN ('mensaje_entrante', 'mensaje_saliente')
     GROUP BY a.contacto_id
  ),
  muertos AS (
    SELECT r.contacto_id, r.ult_nuestro, s.ult_suyo
      FROM recientes r
      CROSS JOIN cfg
      CROSS JOIN LATERAL (
        SELECT max(a.ocurrido_at) AS ult_suyo
          FROM crm.actividades a
         WHERE a.contacto_id = r.contacto_id
           AND a.tipo = 'mensaje_entrante'
           AND a.ocurrido_at <= p_ahora
      ) s
     WHERE r.ult_nuestro IS NOT NULL
       -- Alguna vez nos escribió: el reciclador revive conversaciones, no
       -- abre conversaciones con quien nunca habló.
       AND s.ult_suyo IS NOT NULL
       -- Nosotros hablamos de último…
       AND r.ult_nuestro > s.ult_suyo
       -- …y lleva el silencio que pide la configuración.
       AND r.ult_nuestro <= p_ahora - make_interval(hours => cfg.horas_silencio)
  )
  SELECT c.id, c.nombre, c.telefono_e164, m.ult_nuestro, m.ult_suyo,
         (i.hechos + 1)::int
    FROM muertos m
    CROSS JOIN cfg
    JOIN crm.contactos c ON c.id = m.contacto_id
    CROSS JOIN LATERAL (
      -- Los intentos de ESTE silencio: los de después de su último mensaje.
      SELECT count(*)::int AS hechos, max(x.created_at) AS ultimo
        FROM crm.reciclador_intentos x
       WHERE x.contacto_id = c.id
         AND x.linea_id = p_linea_id
         AND x.created_at > m.ult_suyo
    ) i
   WHERE c.deleted_at IS NULL
     AND c.merged_into_id IS NULL
     AND c.consentimiento
     AND NOT c.opt_out
     AND c.telefono_e164 IS NOT NULL
     AND c.tipo IN ('cliente', 'ambos')
     -- Con el bot callado hay una persona atendiendo (escalamiento, a mano
     -- o relevo): no se le mete un mensaje automático en medio.
     AND c.bot_activo
     AND (NOT cfg.pide_nombre OR NULLIF(btrim(c.nombre), '') IS NOT NULL)
     -- El tope de intentos, y entre uno y otro el mismo silencio. Se mide
     -- también desde el intento porque en simulación no sale mensaje.
     AND i.hechos < cfg.max_intentos
     AND (i.ultimo IS NULL
          OR i.ultimo <= p_ahora - make_interval(hours => cfg.horas_silencio))
     -- Nunca inquilinos con su caso administrativo abierto.
     AND NOT EXISTS (
       SELECT 1 FROM crm.oportunidades o
        WHERE o.contacto_id = c.id
          AND o.embudo = 'administrativa'
          AND o.estado = 'abierta')
     -- Si alguien del equipo cerró su oportunidad comercial después de que
     -- hablara (ganada o perdida), ya se decidió: no se recicla.
     AND NOT EXISTS (
       SELECT 1 FROM crm.oportunidades o
        WHERE o.contacto_id = c.id
          AND o.embudo = 'comercial'
          AND o.estado <> 'abierta'
          AND o.cerrada_at > m.ult_suyo)
     -- Con una visita agendada de hoy en adelante no está muerto.
     AND NOT EXISTS (
       SELECT 1
         FROM crm.actividades a
         JOIN public.citas ci ON ci.id = a.cita_id
        WHERE a.contacto_id = c.id
          AND a.cita_id IS NOT NULL
          AND ci.estado = 'agendada'
          AND ci.fecha >= crm.hoy())
     -- Algo ya en camino para esta persona: no se le manda otro encima.
     AND NOT EXISTS (
       SELECT 1 FROM crm.envios e
        WHERE e.contacto_id = c.id
          AND e.estado = 'pendiente'
          AND e.created_at > p_ahora - interval '1 day')
   ORDER BY m.ult_nuestro ASC
   LIMIT p_limite;
$cand$;

COMMENT ON FUNCTION crm.candidatos_reciclaje(uuid, timestamptz, int) IS
  'LA regla del reciclador: personas con quien hablamos de último por esta línea, calladas más de horas_silencio y dentro de dias_atras, con consentimiento, sin opt-out, con el bot activo, sin visita agendada ni caso administrativo, y con intentos por debajo del tope. La usan la pantalla y el despachador.';

REVOKE ALL ON FUNCTION crm.candidatos_reciclaje(uuid, timestamptz, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION crm.candidatos_reciclaje(uuid, timestamptz, int) TO authenticated;

-- ---------------------------------------------------------------------
-- 4 · Configurar: solo un admin de la inmobiliaria de la línea
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.configurar_reciclador(
  p_linea_id       uuid,
  p_activo         boolean,
  p_simulacion     boolean,
  p_horas_silencio int,
  p_max_intentos   int,
  p_dias_atras     int,
  p_tope_diario    int,
  p_plantilla_id   uuid,
  p_horario        jsonb DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = ''
AS $conf$
DECLARE
  v_linea     crm.lineas%ROWTYPE;
  v_plantilla crm.plantillas%ROWTYPE;
BEGIN
  SELECT * INTO v_linea FROM crm.lineas WHERE id = p_linea_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esa línea no existe' USING ERRCODE = 'P0002';
  END IF;

  -- La RLS ya lo impediría; esto es para decirlo con palabras.
  IF public.get_my_role() IS DISTINCT FROM 'admin'
     OR public.get_my_inmobiliaria() IS DISTINCT FROM v_linea.inmobiliaria_id THEN
    RAISE EXCEPTION 'Solo un administrador puede configurar el reciclador'
      USING ERRCODE = '42501';
  END IF;

  IF v_linea.embudo <> 'comercial' THEN
    RAISE EXCEPTION 'El reciclador es solo para la línea comercial' USING ERRCODE = '22023';
  END IF;

  IF p_plantilla_id IS NOT NULL THEN
    SELECT * INTO v_plantilla FROM crm.plantillas WHERE id = p_plantilla_id;
    IF NOT FOUND OR v_plantilla.inmobiliaria_id <> v_linea.inmobiliaria_id
       OR v_plantilla.wa_phone_number_id IS DISTINCT FROM v_linea.wa_phone_number_id THEN
      RAISE EXCEPTION 'Esa plantilla no es de esta línea' USING ERRCODE = '22023';
    END IF;
    -- Solo {{nombre}}: el reciclador no sabe rellenar nada más.
    IF EXISTS (
      SELECT 1 FROM regexp_matches(v_plantilla.cuerpo, '\{\{\s*([a-z_]+)\s*\}\}', 'g') AS m(v)
       WHERE m.v[1] <> 'nombre') THEN
      RAISE EXCEPTION 'La plantilla solo puede usar la variable {{nombre}}' USING ERRCODE = '22023';
    END IF;
  END IF;

  IF p_activo AND NOT p_simulacion THEN
    IF p_plantilla_id IS NULL
       OR NOT v_plantilla.activa
       OR v_plantilla.estado_meta IS DISTINCT FROM 'aprobada' THEN
      RAISE EXCEPTION 'Para enviar de verdad hace falta una plantilla aprobada por Meta'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  IF p_horario IS NOT NULL AND NOT crm.horario_valido(p_horario) THEN
    RAISE EXCEPTION 'Ese horario no es válido' USING ERRCODE = '22023';
  END IF;

  PERFORM set_config('crm.reciclador', 'si', true);

  INSERT INTO crm.reciclador_config AS r
    (linea_id, inmobiliaria_id, activo, simulacion, horas_silencio, max_intentos,
     dias_atras, tope_diario, plantilla_id, horario, actualizado_por)
  VALUES
    (p_linea_id, v_linea.inmobiliaria_id, p_activo, p_simulacion, p_horas_silencio,
     p_max_intentos, p_dias_atras, p_tope_diario, p_plantilla_id,
     COALESCE(p_horario, '{
       "zona": "America/Bogota",
       "franjas": {
         "1": ["08:00", "18:00"], "2": ["08:00", "18:00"], "3": ["08:00", "18:00"],
         "4": ["08:00", "18:00"], "5": ["08:00", "18:00"], "6": ["08:00", "13:00"]
       }
     }'::jsonb),
     (SELECT auth.uid()))
  ON CONFLICT (linea_id) DO UPDATE
     SET activo          = EXCLUDED.activo,
         simulacion      = EXCLUDED.simulacion,
         horas_silencio  = EXCLUDED.horas_silencio,
         max_intentos    = EXCLUDED.max_intentos,
         dias_atras      = EXCLUDED.dias_atras,
         tope_diario     = EXCLUDED.tope_diario,
         plantilla_id    = EXCLUDED.plantilla_id,
         horario         = COALESCE(p_horario, r.horario),
         actualizado_por = EXCLUDED.actualizado_por,
         -- Lo que se avisó era de la configuración vieja.
         ultimo_aviso    = NULL;
END $conf$;

COMMENT ON FUNCTION crm.configurar_reciclador(uuid, boolean, boolean, int, int, int, int, uuid, jsonb) IS
  'Enciende, apaga o ajusta el reciclador de una línea comercial. Solo admin (RLS). Para enviar de verdad (no simulación) exige plantilla aprobada.';

REVOKE ALL ON FUNCTION crm.configurar_reciclador(uuid, boolean, boolean, int, int, int, int, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION crm.configurar_reciclador(uuid, boolean, boolean, int, int, int, int, uuid, jsonb) TO authenticated;

-- ---------------------------------------------------------------------
-- 5 · El despachador
--
-- Cada 5 minutos. Por pasada manda como mucho un lote pequeño por línea:
-- repartido en el día se parece más a una persona y le da tiempo a Meta
-- de devolver un error de calidad antes de que salgan cincuenta.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.lote_reciclador()
RETURNS int LANGUAGE sql IMMUTABLE SET search_path = '' AS $$ SELECT 10 $$;

CREATE OR REPLACE FUNCTION crm.despachar_reciclaje(p_ahora timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $drc$
DECLARE
  v_url   text;
  v_token text;
  c       record;
  d       record;
  v_aviso text;
  v_disponibles int;
  v_valores jsonb;
  v_cuerpo  text;
  v_envio   uuid;
  v_total   int := 0;
BEGIN
  PERFORM set_config('crm.reciclador', 'si', true);

  SELECT max(s.decrypted_secret) FILTER (WHERE s.name = 'crm_plataforma_url'),
         max(s.decrypted_secret) FILTER (WHERE s.name = 'crm_envio_token')
    INTO v_url, v_token
    FROM vault.decrypted_secrets s
   WHERE s.name IN ('crm_plataforma_url', 'crm_envio_token');

  FOR c IN
    SELECT r.*,
           l.embudo            AS linea_embudo,
           l.activa            AS linea_activa,
           l.wa_phone_number_id AS linea_pnid,
           l.token_invalido_at AS linea_token_invalido_at,
           p.activa            AS plantilla_activa,
           p.estado_meta       AS plantilla_estado,
           p.nombre_meta       AS plantilla_nombre_meta,
           p.idioma            AS plantilla_idioma,
           p.cuerpo            AS plantilla_cuerpo,
           p.wa_phone_number_id AS plantilla_linea
      FROM crm.reciclador_config r
      JOIN crm.lineas l ON l.id = r.linea_id
      LEFT JOIN crm.plantillas p ON p.id = r.plantilla_id
     WHERE r.activo
     ORDER BY r.linea_id
       FOR UPDATE OF r SKIP LOCKED
  LOOP
    v_aviso := CASE
      WHEN NOT c.linea_activa
        THEN 'En pausa: la línea no está activa.'
      WHEN c.linea_token_invalido_at IS NOT NULL AND NOT c.simulacion
        THEN 'En pausa: Meta rechaza la credencial de la línea; hay que reconectarla.'
      WHEN c.plantilla_id IS NULL
        THEN 'En pausa: falta elegir la plantilla.'
      WHEN c.plantilla_linea IS DISTINCT FROM c.linea_pnid
        THEN 'En pausa: la plantilla ya no es de esta línea.'
      WHEN NOT c.simulacion
           AND (NOT c.plantilla_activa OR c.plantilla_estado IS DISTINCT FROM 'aprobada')
        THEN 'En pausa: la plantilla no está aprobada por Meta.'
      WHEN NOT c.simulacion AND (v_url IS NULL OR v_token IS NULL)
        THEN 'En pausa: falta configurar el canal en la base (crm_plataforma_url y crm_envio_token en Vault).'
    END;
    IF v_aviso IS NOT NULL THEN
      UPDATE crm.reciclador_config
         SET ultimo_aviso = v_aviso, ultima_pasada_at = p_ahora
       WHERE linea_id = c.linea_id;
      CONTINUE;
    END IF;

    -- Fuera de horario (o festivo) no se manda: lo que espere sale en la
    -- siguiente franja, si sigue callado.
    IF NOT crm.en_horario_envio(c.horario, p_ahora) THEN
      UPDATE crm.reciclador_config
         SET ultimo_aviso = NULL, ultima_pasada_at = p_ahora
       WHERE linea_id = c.linea_id;
      CONTINUE;
    END IF;

    SELECT c.tope_diario - count(*) INTO v_disponibles
      FROM crm.reciclador_intentos x
     WHERE x.linea_id = c.linea_id
       AND x.created_at > p_ahora - interval '24 hours';
    IF v_disponibles <= 0 THEN
      UPDATE crm.reciclador_config
         SET ultimo_aviso = 'Esperando: ya salieron ' || c.tope_diario
                            || ' mensajes en 24 horas, el tope.',
             ultima_pasada_at = p_ahora
       WHERE linea_id = c.linea_id;
      CONTINUE;
    END IF;

    FOR d IN
      SELECT * FROM crm.candidatos_reciclaje(
        c.linea_id, p_ahora, LEAST(v_disponibles, crm.lote_reciclador()))
    LOOP
      v_valores := CASE
        WHEN c.plantilla_cuerpo ~ '\{\{\s*nombre\s*\}\}'
          THEN jsonb_build_object('nombre', split_part(btrim(d.nombre), ' ', 1))
        ELSE '{}'::jsonb
      END;
      v_cuerpo := crm.rellenar_cuerpo(c.plantilla_cuerpo, v_valores);

      IF c.simulacion THEN
        INSERT INTO crm.reciclador_intentos
          (inmobiliaria_id, linea_id, contacto_id, numero, silencio_desde, simulado, cuerpo, created_at)
        VALUES
          (c.inmobiliaria_id, c.linea_id, d.contacto_id, d.intento, d.ultimo_nuestro_at, true,
           v_cuerpo, p_ahora);
      ELSE
        INSERT INTO crm.envios
          (inmobiliaria_id, contacto_id, plantilla_id, cuerpo, canal, estado,
           wa_phone_number_id, variables, tomado_at)
        VALUES
          (c.inmobiliaria_id, d.contacto_id, c.plantilla_id, v_cuerpo, 'meta', 'pendiente',
           c.linea_pnid, v_valores, p_ahora)
        RETURNING id INTO v_envio;

        INSERT INTO crm.reciclador_intentos
          (inmobiliaria_id, linea_id, contacto_id, numero, silencio_desde, simulado,
           envio_id, cuerpo, created_at)
        VALUES
          (c.inmobiliaria_id, c.linea_id, d.contacto_id, d.intento, d.ultimo_nuestro_at, false,
           v_envio, v_cuerpo, p_ahora);

        -- El cuerpo de lib/canal.ts (contrato C1) más `origen`, que le dice
        -- a la plataforma que no anote relevo.
        UPDATE crm.envios
           SET solicitud_http = crm.pedir_envio_a_plataforma(v_url, v_token, jsonb_build_object(
                 'inmobiliaria_id', c.inmobiliaria_id,
                 'telefono', d.telefono_e164,
                 'texto', v_cuerpo,
                 'envio_id', v_envio,
                 'origen', 'reciclador',
                 'desde', jsonb_build_object('wa_phone_number_id', c.linea_pnid,
                                             'embudo', c.linea_embudo),
                 'plantilla', jsonb_build_object('nombre_meta', c.plantilla_nombre_meta,
                                                 'idioma', c.plantilla_idioma,
                                                 'variables', v_valores)))
         WHERE id = v_envio;
      END IF;

      v_total := v_total + 1;
    END LOOP;

    UPDATE crm.reciclador_config
       SET ultimo_aviso = NULL, ultima_pasada_at = p_ahora
     WHERE linea_id = c.linea_id;
  END LOOP;

  RETURN v_total;
END $drc$;

COMMENT ON FUNCTION crm.despachar_reciclaje(timestamptz) IS
  'Cada 5 minutos (pg_cron): para cada línea con el reciclador encendido, en su horario y bajo su tope, toma un lote de crm.candidatos_reciclaje y lo manda (o lo anota, en simulación).';

REVOKE ALL ON FUNCTION crm.despachar_reciclaje(timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.lote_reciclador() FROM PUBLIC, anon;

-- ---------------------------------------------------------------------
-- 6 · Lo que contestó la plataforma, también para el reciclador
--
-- Igual que antes para los envíos masivos. Lo nuevo: cuando falla el
-- CANAL (401, 403, 409, 503) en un envío del reciclador, no salió nada,
-- así que el intento se borra (no cuenta) y el reciclador se APAGA con
-- el motivo: reintentar cada 5 minutos contra un canal roto no arregla
-- nada y llena el registro.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.anotar_respuestas_plataforma()
RETURNS integer
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $arp$
DECLARE
  v_n int := 0;
  v_m int;
  r   record;
BEGIN
  PERFORM set_config('crm.envios_masivos', 'si', true);
  PERFORM set_config('crm.reciclador', 'si', true);

  UPDATE crm.envios e
     SET estado = 'enviado',
         wa_message_id = crm.json_seguro(h.content) ->> 'wa_message_id',
         enviado_at = COALESCE(e.enviado_at, h.created)
    FROM net._http_response h
   WHERE h.id = e.solicitud_http
     AND e.estado = 'pendiente'
     AND h.status_code = 200
     AND crm.json_seguro(h.content) ->> 'wa_message_id' IS NOT NULL;
  GET DIAGNOSTICS v_m = ROW_COUNT;
  v_n := v_n + v_m;

  UPDATE crm.envios e
     SET estado = 'fallido',
         error = COALESCE(crm.json_seguro(h.content) ->> 'error',
                          'La plataforma respondió ' || h.status_code),
         error_codigo = COALESCE(
           e.error_codigo,
           CASE WHEN (crm.json_seguro(h.content) ->> 'codigo') ~ '^[0-9]{1,9}$'
                THEN (crm.json_seguro(h.content) ->> 'codigo')::int END),
         fallido_at = now()
    FROM net._http_response h
   WHERE h.id = e.solicitud_http
     AND e.estado = 'pendiente'
     AND h.status_code IN (400, 502);
  GET DIAGNOSTICS v_m = ROW_COUNT;
  v_n := v_n + v_m;

  FOR r IN
    SELECT e.id AS envio_id, e.envio_masivo_id, h.status_code,
           crm.json_seguro(h.content) ->> 'error' AS error
      FROM crm.envios e
      JOIN net._http_response h ON h.id = e.solicitud_http
     WHERE e.estado = 'pendiente'
       AND h.status_code IN (401, 403, 409, 503)
  LOOP
    IF r.envio_masivo_id IS NOT NULL THEN
      UPDATE crm.envios_masivos_destinatarios
         SET estado = 'listo', envio_id = NULL
       WHERE envio_id = r.envio_id;
      DELETE FROM crm.envios WHERE id = r.envio_id;
      UPDATE crm.envios_masivos
         SET estado = 'pausado',
             ultimo_aviso = 'Se pausó: la plataforma respondió ' || r.status_code
                            || COALESCE(' (' || r.error || ')', '')
                            || '. No salió nada; revisa el canal y reanúdalo.'
       WHERE id = r.envio_masivo_id AND estado = 'en_curso';
    ELSE
      UPDATE crm.reciclador_config rc
         SET activo = false,
             ultimo_aviso = 'Se apagó: la plataforma respondió ' || r.status_code
                            || COALESCE(' (' || r.error || ')', '')
                            || '. No salió nada; revisa el canal y vuelve a encenderlo.'
        FROM crm.reciclador_intentos x
       WHERE x.envio_id = r.envio_id
         AND rc.linea_id = x.linea_id;
      DELETE FROM crm.reciclador_intentos WHERE envio_id = r.envio_id;
      DELETE FROM crm.envios WHERE id = r.envio_id;
    END IF;
    v_n := v_n + 1;
  END LOOP;

  RETURN v_n;
END $arp$;

-- ---------------------------------------------------------------------
-- 7 · Lo que ve la pantalla
-- ---------------------------------------------------------------------

-- Cómo va: lo de los últimos p_dias. «Respondió» = un mensaje entrante
-- suyo en las 72 horas siguientes al intento, por cualquier línea.
CREATE OR REPLACE FUNCTION crm.resumen_reciclaje(p_linea_id uuid, p_dias int DEFAULT 7)
RETURNS TABLE (
  enviados    int,
  simulados   int,
  fallidos    int,
  respondieron int,
  en_espera   int
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $res$
  WITH x AS (
    SELECT i.*, e.estado AS envio_estado,
           EXISTS (
             SELECT 1 FROM crm.actividades a
              WHERE a.contacto_id = i.contacto_id
                AND a.tipo = 'mensaje_entrante'
                AND a.ocurrido_at > i.created_at
                AND a.ocurrido_at <= i.created_at + interval '72 hours') AS respondio
      FROM crm.reciclador_intentos i
      LEFT JOIN crm.envios e ON e.id = i.envio_id
     WHERE i.linea_id = p_linea_id
       AND i.created_at > now() - make_interval(days => p_dias)
  )
  SELECT
    count(*) FILTER (WHERE NOT simulado AND envio_estado IS DISTINCT FROM 'fallido')::int,
    count(*) FILTER (WHERE simulado)::int,
    count(*) FILTER (WHERE envio_estado = 'fallido')::int,
    count(*) FILTER (WHERE NOT simulado AND respondio)::int,
    (SELECT count(*)::int FROM crm.candidatos_reciclaje(p_linea_id, now(), 1000))
  FROM x;
$res$;

COMMENT ON FUNCTION crm.resumen_reciclaje(uuid, int) IS
  'Cómo va el reciclador de una línea: enviados, simulados, fallidos y cuántos respondieron en 72 horas, más cuántos esperan turno ahora.';

-- La lista de lo que hizo, lo más nuevo primero.
CREATE OR REPLACE FUNCTION crm.historial_reciclaje(p_linea_id uuid, p_limite int DEFAULT 50)
RETURNS TABLE (
  intento_id  uuid,
  contacto_id uuid,
  nombre      text,
  telefono_e164 text,
  numero      int,
  simulado    boolean,
  creado_at   timestamptz,
  estado      text,
  error       text,
  respondio_at timestamptz
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $his$
  SELECT i.id, i.contacto_id, c.nombre, c.telefono_e164, i.numero::int, i.simulado,
         i.created_at,
         CASE WHEN i.simulado THEN 'simulado' ELSE COALESCE(e.estado, 'pendiente') END,
         e.error,
         (SELECT min(a.ocurrido_at) FROM crm.actividades a
           WHERE a.contacto_id = i.contacto_id
             AND a.tipo = 'mensaje_entrante'
             AND a.ocurrido_at > i.created_at)
    FROM crm.reciclador_intentos i
    JOIN crm.contactos c ON c.id = i.contacto_id
    LEFT JOIN crm.envios e ON e.id = i.envio_id
   WHERE i.linea_id = p_linea_id
   ORDER BY i.created_at DESC
   LIMIT LEAST(GREATEST(p_limite, 1), 200);
$his$;

COMMENT ON FUNCTION crm.historial_reciclaje(uuid, int) IS
  'Los últimos intentos del reciclador de una línea, con su estado y cuándo respondió la persona (si respondió).';

REVOKE ALL ON FUNCTION crm.resumen_reciclaje(uuid, int) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION crm.historial_reciclaje(uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION crm.resumen_reciclaje(uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION crm.historial_reciclaje(uuid, int) TO authenticated;

-- ---------------------------------------------------------------------
-- 8 · La agenda
-- ---------------------------------------------------------------------
DO $cron$
BEGIN
  PERFORM cron.schedule(
    'crm_despachar_reciclaje', '*/5 * * * *',
    $trabajo$SELECT crm.despachar_reciclaje();$trabajo$);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron no disponible; agendar crm.despachar_reciclaje() a mano: %', SQLERRM;
END $cron$;
