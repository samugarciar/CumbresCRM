-- =====================================================================
-- El reciclador también le escribe a quien nos dejó esperando (17 nov 2026)
--
-- LO QUE CAMBIA
-- La decisión 49 (13 nov) dejaba fuera a quien nos escribió de último y no
-- recibió respuesta: «esa falla es nuestra y la cubre el 🔥». Samuel la
-- cambió el 17 nov: esas conversaciones también entran al reciclador.
--
-- CÓMO QUEDA LA REGLA
--   · Silencio = desde el ÚLTIMO mensaje de la conversación, sea nuestro
--     o suyo. Si fue suyo, tiene que haber llegado por esta línea.
--   · Lo de siempre: N horas, dentro de dias_atras, 2 intentos por
--     silencio contados desde su último mensaje. Tras el primer intento
--     el último mensaje es nuestro y sigue como cualquier otro.
--   · Se sigue excluyendo el bot callado: si una persona del equipo está
--     atendiendo (escalamiento, a mano, relevo), no se le mete una
--     plantilla en medio. Cuando el silencio del escalamiento vence (6 h)
--     y nadie atendió, el bot vuelve y la conversación ya puede entrar.
--   · Es una perilla: reciclador_config.incluir_esperando, encendida por
--     defecto (lo que pidió Samuel). Apagada, la regla es la del 13 nov.
--
-- FIRMAS
--   · crm.candidatos_reciclaje devuelve `ultimo_mensaje_at` (antes
--     `ultimo_nuestro_at`) y `nos_esperaba`. Cambia el tipo de salida, así
--     que se borra y se crea.
--   · crm.configurar_reciclador gana p_incluir_esperando (con DEFAULT, así
--     que la llamada vieja sigue sirviendo). También se borra y se crea.
--   · crm.despachar_reciclaje se reescribe con el nombre nuevo.
-- =====================================================================

ALTER TABLE crm.reciclador_config
  ADD COLUMN incluir_esperando boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN crm.reciclador_config.incluir_esperando IS
  'También reciclar a quien nos escribió de último y no recibió respuesta (Samuel, 17 nov 2026). Apagado: solo a quien le hablamos de último.';

-- ---------------------------------------------------------------------
-- LA regla
-- ---------------------------------------------------------------------
DROP FUNCTION crm.candidatos_reciclaje(uuid, timestamptz, int);

CREATE FUNCTION crm.candidatos_reciclaje(
  p_linea_id uuid,
  p_ahora    timestamptz DEFAULT now(),
  p_limite   int DEFAULT 500)
RETURNS TABLE (
  contacto_id      uuid,
  nombre           text,
  telefono_e164    text,
  ultimo_mensaje_at timestamptz,
  ultimo_suyo_at   timestamptz,
  nos_esperaba     boolean,
  intento          int
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $cand$
  WITH cfg AS (
    SELECT r.horas_silencio, r.max_intentos, r.dias_atras, r.incluir_esperando,
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
           max(a.ocurrido_at) FILTER (WHERE a.tipo = 'mensaje_saliente') AS ult_nuestro,
           max(a.ocurrido_at) FILTER (WHERE a.tipo = 'mensaje_entrante') AS ult_suyo_linea
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
    SELECT r.contacto_id, s.ult_suyo,
           GREATEST(r.ult_nuestro, s.ult_suyo) AS ultimo,
           (r.ult_nuestro IS NULL OR s.ult_suyo >= r.ult_nuestro) AS nos_esperaba
      FROM recientes r
      CROSS JOIN cfg
      CROSS JOIN LATERAL (
        -- Su último mensaje por CUALQUIER línea: si nos escribió por otra,
        -- esta conversación no está muerta.
        SELECT max(a.ocurrido_at) AS ult_suyo
          FROM crm.actividades a
         WHERE a.contacto_id = r.contacto_id
           AND a.tipo = 'mensaje_entrante'
           AND a.ocurrido_at <= p_ahora
      ) s
     WHERE s.ult_suyo IS NOT NULL
       AND (
         -- Nosotros hablamos de último…
         r.ult_nuestro > s.ult_suyo
         -- …o nos dejó esperando, por ESTA línea, y la perilla lo permite.
         OR (cfg.incluir_esperando
             AND r.ult_suyo_linea = s.ult_suyo
             AND (r.ult_nuestro IS NULL OR s.ult_suyo >= r.ult_nuestro))
       )
       -- …y lleva el silencio que pide la configuración.
       AND GREATEST(r.ult_nuestro, s.ult_suyo)
           <= p_ahora - make_interval(hours => cfg.horas_silencio)
  )
  SELECT c.id, c.nombre, c.telefono_e164, m.ultimo, m.ult_suyo, m.nos_esperaba,
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
   ORDER BY m.ultimo ASC
   LIMIT p_limite;
$cand$;

COMMENT ON FUNCTION crm.candidatos_reciclaje(uuid, timestamptz, int) IS
  'LA regla del reciclador: conversaciones de esta línea calladas más de horas_silencio y dentro de dias_atras —hablamos de último, o (con incluir_esperando) nos dejó esperando por esta línea—, con consentimiento, sin opt-out, con el bot activo, sin visita agendada ni caso administrativo, y con intentos por debajo del tope. La usan la pantalla y el despachador.';

REVOKE ALL ON FUNCTION crm.candidatos_reciclaje(uuid, timestamptz, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION crm.candidatos_reciclaje(uuid, timestamptz, int) TO authenticated;

-- ---------------------------------------------------------------------
-- Configurar, con la perilla nueva
-- ---------------------------------------------------------------------
DROP FUNCTION crm.configurar_reciclador(uuid, boolean, boolean, int, int, int, int, uuid, jsonb);

CREATE FUNCTION crm.configurar_reciclador(
  p_linea_id          uuid,
  p_activo            boolean,
  p_simulacion        boolean,
  p_horas_silencio    int,
  p_max_intentos      int,
  p_dias_atras        int,
  p_tope_diario       int,
  p_plantilla_id      uuid,
  p_horario           jsonb DEFAULT NULL,
  p_incluir_esperando boolean DEFAULT true)
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
     dias_atras, tope_diario, plantilla_id, horario, incluir_esperando, actualizado_por)
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
     COALESCE(p_incluir_esperando, true),
     (SELECT auth.uid()))
  ON CONFLICT (linea_id) DO UPDATE
     SET activo            = EXCLUDED.activo,
         simulacion        = EXCLUDED.simulacion,
         horas_silencio    = EXCLUDED.horas_silencio,
         max_intentos      = EXCLUDED.max_intentos,
         dias_atras        = EXCLUDED.dias_atras,
         tope_diario       = EXCLUDED.tope_diario,
         plantilla_id      = EXCLUDED.plantilla_id,
         horario           = COALESCE(p_horario, r.horario),
         incluir_esperando = EXCLUDED.incluir_esperando,
         actualizado_por   = EXCLUDED.actualizado_por,
         -- Lo que se avisó era de la configuración vieja.
         ultimo_aviso      = NULL;
END $conf$;

COMMENT ON FUNCTION crm.configurar_reciclador(uuid, boolean, boolean, int, int, int, int, uuid, jsonb, boolean) IS
  'Enciende, apaga o ajusta el reciclador de una línea comercial. Solo admin (RLS). Para enviar de verdad (no simulación) exige plantilla aprobada. p_incluir_esperando: también a quien nos dejó esperando.';

REVOKE ALL ON FUNCTION crm.configurar_reciclador(uuid, boolean, boolean, int, int, int, int, uuid, jsonb, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION crm.configurar_reciclador(uuid, boolean, boolean, int, int, int, int, uuid, jsonb, boolean) TO authenticated;

-- ---------------------------------------------------------------------
-- El despachador, con el nombre nuevo de la columna
-- ---------------------------------------------------------------------
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
          (c.inmobiliaria_id, c.linea_id, d.contacto_id, d.intento, d.ultimo_mensaje_at, true,
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
          (c.inmobiliaria_id, c.linea_id, d.contacto_id, d.intento, d.ultimo_mensaje_at, false,
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

REVOKE ALL ON FUNCTION crm.despachar_reciclaje(timestamptz) FROM PUBLIC, anon, authenticated;
