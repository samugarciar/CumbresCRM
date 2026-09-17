-- =====================================================================
-- El bot, apagable por lead.
--
-- LA REGLA DE NEGOCIO, DICHA POR SAMUEL
-- "El líder en cuanto a comunicación con clientes es el asesor."
-- El bot sigue siendo opt-out —contesta por defecto, porque hoy cubre
-- 7.819 mensajes y hay una sola asesora entrando a diario— pero el
-- asesor manda, y cuando toma una conversación el bot se calla.
--
-- TRES INTERRUPTORES, EN TRES SITIOS DISTINTOS
--   1. General, por inmobiliaria → public.agentes_config.activo, en la
--      plataforma. Ya existe; esto NO lo toca.
--   2. Automático al escalar → aquí abajo, en sincronizar_escalamientos.
--   3. A mano, por lead → un botón en la ficha.
--
-- POR QUÉ EL ESTADO CUELGA DEL CONTACTO Y NO DE LA OPORTUNIDAD
-- El bot le habla a una persona, no a una oportunidad, y resuelve por
-- teléfono. Además 435 oportunidades se han cerrado solas por silencio:
-- colgarlo de ahí haría que el bot volviera a hablar el día que una
-- oportunidad se cierra. Mismo criterio que crm.requerimientos.
-- =====================================================================

ALTER TABLE crm.contactos
  ADD COLUMN bot_activo boolean NOT NULL DEFAULT true,
  -- Cuándo se tocó por última vez, y quién. NULL en `por` = lo hizo el
  -- sistema, no una persona: el mismo marcador que ya usa
  -- oportunidades.cerrada_por para las cerradas por silencio.
  ADD COLUMN bot_cambiado_at timestamptz,
  ADD COLUMN bot_cambiado_por uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,
  ADD COLUMN bot_motivo text
    CHECK (bot_motivo IN ('escalamiento', 'manual')),
  -- Un bot callado sin motivo es un bot que nadie sabe por qué calla.
  ADD CONSTRAINT contactos_bot_apagado_con_motivo
    CHECK (bot_activo OR bot_motivo IS NOT NULL);

COMMENT ON COLUMN crm.contactos.bot_activo IS
  'Si el agente comercial puede responderle a esta persona. Se consulta con crm.bot_puede_responder().';

-- ---------------------------------------------------------------------
-- La pregunta que hace el agente, y la única que necesita
--
-- Diseñada como API del agente, no de la pantalla: firma estable,
-- SECURITY DEFINER, documentada. Es la regla 2 de las que se adoptaron
-- para la integración con el bot.
--
-- Corre en el camino de CADA mensaje entrante, así que es una sola
-- lectura por el índice único de telefono_e164. Nada más puede entrar
-- aquí: el escalamiento costaba 614 ms y por eso vive en un cron.
--
-- DOS DECISIONES QUE PARECEN DETALLES Y NO LO SON:
--
-- 1. Un teléfono DESCONOCIDO devuelve true. Cuando alguien escribe por
--    primera vez todavía no existe su fila —la crea la proyección
--    después—, así que fallar hacia "callado" dejaría sin respuesta
--    justo a los leads nuevos, que son los que más importan.
--
-- 2. LLEVA INMOBILIARIA, y no es decorativo. El índice único de
--    teléfono es (inmobiliaria_id, telefono_e164): el mismo número
--    puede existir en dos inquilinos. Preguntando solo por teléfono,
--    una inmobiliaria apagando su bot callaría el de la otra. El agente
--    ya sabe en nombre de quién trabaja, así que se le pide.
--    bool_and se queda igualmente: con inquilino hay como mucho una
--    fila, y si algún día hubiera dos, gana el silencio — que una de
--    ellas esté apagada significa que alguien tomó la conversación.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.bot_puede_responder(
  p_inmobiliaria_id uuid,
  p_telefono        text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $puede$
  SELECT COALESCE(bool_and(c.bot_activo), true)
    FROM crm.contactos c
   WHERE c.inmobiliaria_id = p_inmobiliaria_id
     AND c.telefono_e164 = crm.normalizar_telefono(p_telefono)
     AND c.deleted_at IS NULL;
$puede$;

COMMENT ON FUNCTION crm.bot_puede_responder(uuid, text) IS
  'Contrato con el agente comercial: ¿puede el bot responderle a este teléfono? Desconocido = sí. Va por inquilino: el teléfono solo es único dentro de una inmobiliaria.';

GRANT EXECUTE ON FUNCTION crm.bot_puede_responder(uuid, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- El interruptor de la ficha
--
-- SECURITY INVOKER: manda la RLS, y `bot_cambiado_por` queda con el id
-- de quien lo pulsó. Un bot apagado que no sabe quién lo apagó no sirve
-- como memoria de equipo — el mismo motivo que las notas.
--
-- Deja rastro en el historial como actividad 'sistema'. No inventa un
-- tipo nuevo: el que abre la ficha tiene que ver "aquí se calló el bot"
-- en la misma línea de tiempo que todo lo demás.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.cambiar_bot(
  p_contacto_id uuid,
  p_activo      boolean)
RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $cambiar$
DECLARE
  v_inmobiliaria uuid;
  v_antes boolean;
BEGIN
  SELECT c.inmobiliaria_id, c.bot_activo INTO v_inmobiliaria, v_antes
    FROM crm.contactos c
   WHERE c.id = p_contacto_id AND c.deleted_at IS NULL;

  -- Sin fila visible: o no existe, o la RLS no la deja ver. Las dos
  -- respuestas son la misma a propósito.
  IF v_inmobiliaria IS NULL THEN RETURN false; END IF;

  -- Pulsar dos veces no escribe dos veces ni ensucia el historial.
  IF v_antes = p_activo THEN RETURN true; END IF;

  UPDATE crm.contactos
     SET bot_activo       = p_activo,
         bot_motivo       = CASE WHEN p_activo THEN NULL ELSE 'manual' END,
         bot_cambiado_at  = now(),
         bot_cambiado_por = auth.uid()
   WHERE id = p_contacto_id;

  INSERT INTO crm.actividades
    (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, creado_por)
  VALUES (
    v_inmobiliaria, 'sistema', 'humano', p_contacto_id,
    CASE WHEN p_activo
      THEN 'El bot vuelve a responderle a esta persona.'
      ELSE 'El bot deja de responderle: un asesor atiende esta conversación.'
    END,
    auth.uid());

  RETURN true;
END $cambiar$;

COMMENT ON FUNCTION crm.cambiar_bot(uuid, boolean) IS
  'Apaga o enciende el bot para un contacto. Escribe con el token de quien lo pulsa: la RLS decide y queda registrado quién fue.';

GRANT EXECUTE ON FUNCTION crm.cambiar_bot(uuid, boolean) TO authenticated;

-- ---------------------------------------------------------------------
-- Apagarlo solo cuando el lead escala
--
-- Escalar significa exactamente "quiero hablar con una persona". Que el
-- bot siga contestando después de eso es lo que Samuel quiere evitar.
--
-- ⚠️ SOLO HACIA ADELANTE, Y ESTO ES LO IMPORTANTE DE ESTA FUNCIÓN.
-- En producción hay 1.275 escalamientos históricos repartidos en 264
-- contactos. Una versión ingenua de esto —"apaga el bot donde
-- escalado_at no sea nulo"— dejaría mudo al bot en 264 conversaciones
-- reales en la primera pasada del cron, sin que nadie lo pidiera. Eso no
-- es una función, es un incidente.
--
-- Dos cierres para que no pueda pasar:
--   · solo los contactos que ESTA pasada acaba de tocar (`tocadas`),
--   · y solo si el escalamiento es de las últimas 48 horas — la misma
--     regla de frescura que ya usa la alerta del tablero.
-- Al desplegar, escalado_at ya está sincronizado: `tocadas` sale vacía y
-- no se apaga ni uno. Que es justo lo que tiene que pasar.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.sincronizar_escalamientos()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $escal$
DECLARE
  v_n integer;
BEGIN
  WITH puente AS (
    -- uso → conversación → mensajes → la actividad que proyectamos.
    -- En producción ninguna conversación apunta a más de un contacto,
    -- así que el puente no es ambiguo.
    SELECT a.contacto_id, m.conversacion_id
      FROM crm.actividades a
      JOIN public.agente_comercial_mensajes m
        ON m.id::text = a.metadata->>'origen_id'
     WHERE a.metadata->>'origen_tabla' = 'agente_comercial_mensajes'
       AND a.contacto_id IS NOT NULL
  ), primera AS (
    SELECT p.contacto_id, MIN(u.created_at) AS escalado_at
      FROM puente p
      JOIN public.agente_comercial_uso u ON u.conversacion_id = p.conversacion_id
     WHERE u.escalado
     GROUP BY p.contacto_id
  ), tocadas AS (
    UPDATE crm.oportunidades o
       SET escalado_at = pr.escalado_at, updated_at = now()
      FROM primera pr
     WHERE o.contacto_id = pr.contacto_id
       AND o.estado = 'abierta'
       AND o.escalado_at IS DISTINCT FROM pr.escalado_at
    RETURNING o.contacto_id, pr.escalado_at
  ), apagadas AS (
    UPDATE crm.contactos c
       SET bot_activo       = false,
           bot_motivo       = 'escalamiento',
           bot_cambiado_at  = now(),
           bot_cambiado_por = NULL   -- lo hizo el sistema, no una persona
      FROM tocadas t
     WHERE c.id = t.contacto_id
       AND c.bot_activo
       AND t.escalado_at > now() - interval '48 hours'
    RETURNING c.id AS contacto_id, c.inmobiliaria_id
  ), rastro AS (
    INSERT INTO crm.actividades
      (inmobiliaria_id, tipo, origen, contacto_id, cuerpo)
    SELECT a.inmobiliaria_id, 'sistema', 'sistema', a.contacto_id,
           'El bot dejó de responderle: pidió hablar con una persona.'
      FROM apagadas a
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_n FROM tocadas;
  RETURN v_n;
END $escal$;

COMMENT ON FUNCTION crm.sincronizar_escalamientos() IS
  'Sincroniza escalado_at desde agente_comercial_uso y calla al bot en los que ACABAN de escalar. Nunca retroactivo.';
