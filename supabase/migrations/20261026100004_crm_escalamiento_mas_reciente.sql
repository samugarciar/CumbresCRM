-- =====================================================================
-- El escalamiento se ancla al más reciente, no al primero (26 oct 2026)
--
-- LO QUE PASABA
-- crm.sincronizar_escalamientos tomaba MIN(created_at) de los
-- escalamientos de la conversación del agente. Dos efectos:
--   · Un contacto que nació el 25 oct en la 312 heredaba el primer
--     escalamiento de su conversación en la era Kommo: en el Tablero salía
--     «Pidió persona hace 2 meses» en una oportunidad de ayer.
--   · Un segundo escalamiento, días después del primero, no cambiaba nada:
--     el valor seguía siendo el primero y el bot no se volvía a callar
--     aunque la persona pidiera otra vez hablar con alguien.
--
-- LA REGLA NUEVA
--   · Se toma el MÁS RECIENTE, y solo entre los que ocurrieron desde que
--     existe el contacto (u.created_at >= contacto.created_at).
--   · La oportunidad se actualiza solo hacia adelante (el valor nuevo es
--     mayor que el que tenía) y si el escalamiento es de esta oportunidad
--     (>= o.created_at), no de una anterior.
--   · El bot se calla solo si el escalamiento es posterior al último
--     cambio del bot (bot_cambiado_at) y de las últimas 48 h. Quien lo
--     encendió a mano DESPUÉS de que la persona pidiera ayuda no vuelve a
--     quedar callado por ese mismo pedido.
--   · Lo mismo en la mitad del freno (crm.frenos_bot): un escalamiento
--     anterior al último cambio del freno no lo vuelve a apagar.
--
-- Los datos que ya quedaron mal (escalado_at anterior al contacto) se
-- limpian aparte: supabase/manual/2026-10-26_escalado_antes_del_contacto.sql.
--
-- Misma firma y mismos permisos. Idempotente.
-- =====================================================================

CREATE OR REPLACE FUNCTION crm.sincronizar_escalamientos()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $sincronizar$
DECLARE
  v_n integer;
  v_f integer;
BEGIN
  WITH puente AS (
    SELECT a.contacto_id, m.conversacion_id
      FROM crm.actividades a
      JOIN public.agente_comercial_mensajes m
        ON m.id::text = a.metadata->>'origen_id'
     WHERE a.metadata->>'origen_tabla' = 'agente_comercial_mensajes'
       AND a.contacto_id IS NOT NULL
  ), reciente AS (
    -- El más reciente, y solo de cuando el contacto ya existía: lo de la
    -- era Kommo, antes de que naciera en el CRM, no cuenta.
    SELECT p.contacto_id, MAX(u.created_at) AS escalado_at
      FROM puente p
      JOIN crm.contactos k ON k.id = p.contacto_id
      JOIN public.agente_comercial_uso u ON u.conversacion_id = p.conversacion_id
     WHERE u.escalado
       AND u.created_at >= k.created_at
     GROUP BY p.contacto_id
  ), tocadas AS (
    UPDATE crm.oportunidades o
       SET escalado_at = r.escalado_at, updated_at = now()
      FROM reciente r
     WHERE o.contacto_id = r.contacto_id
       AND o.estado = 'abierta'
       -- Escalar es pedir un asesor comercial: el bot solo atiende ahí.
       AND o.embudo = 'comercial'
       -- Solo hacia adelante, y solo lo que pasó en esta oportunidad.
       AND r.escalado_at > COALESCE(o.escalado_at, '-infinity'::timestamptz)
       AND r.escalado_at >= o.created_at
    RETURNING o.contacto_id, r.escalado_at
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
       -- Si alguien lo encendió a mano después de este pedido, manda eso.
       AND t.escalado_at > COALESCE(c.bot_cambiado_at, '-infinity'::timestamptz)
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

  WITH escalados AS (
    SELECT DISTINCT ON (c.inmobiliaria_id, crm.normalizar_telefono(c.telefono))
           c.inmobiliaria_id,
           crm.normalizar_telefono(c.telefono) AS telefono_e164,
           c.id AS conversacion_id,
           c.cliente_nombre,
           u.created_at AS escalado_at
      FROM public.agente_comercial_uso u
      JOIN public.agente_comercial_conversaciones c ON c.id = u.conversacion_id
      JOIN crm.preferencias p
        ON p.inmobiliaria_id = c.inmobiliaria_id
       AND p.solo_lineas_oficiales
     WHERE u.escalado
       AND u.created_at > p.solo_lineas_desde
       AND u.created_at > now() - interval '48 hours'
       AND crm.normalizar_telefono(c.telefono) IS NOT NULL
     ORDER BY c.inmobiliaria_id, crm.normalizar_telefono(c.telefono), u.created_at DESC
  ), fuera_del_crm AS (
    -- Quien tiene una oportunidad comercial abierta ya lo cubre la
    -- primera mitad.
    SELECT e.*
      FROM escalados e
     WHERE NOT EXISTS (
       SELECT 1
         FROM crm.contactos k
         JOIN crm.oportunidades o ON o.contacto_id = k.id
        WHERE k.inmobiliaria_id = e.inmobiliaria_id
          AND k.telefono_e164 = e.telefono_e164
          AND k.deleted_at IS NULL
          AND o.estado = 'abierta'
          AND o.embudo = 'comercial')
  ), frenados AS (
    INSERT INTO crm.frenos_bot AS f
      (inmobiliaria_id, telefono_e164, conversacion_id, nombre,
       bot_activo, bot_motivo, bot_caduca, bot_cambiado_at, escalado_at)
    SELECT e.inmobiliaria_id, e.telefono_e164, e.conversacion_id, e.cliente_nombre,
           false, 'escalamiento', true, now(), e.escalado_at
      FROM fuera_del_crm e
    ON CONFLICT (inmobiliaria_id, telefono_e164) DO UPDATE
       -- Se calla ahora solo si estaba hablando y el pedido es posterior al
       -- último cambio del freno (alguien pudo encenderlo a mano después).
       SET bot_activo       = f.bot_activo
                              AND EXCLUDED.escalado_at <= COALESCE(f.bot_cambiado_at, '-infinity'::timestamptz),
           bot_motivo       = CASE WHEN f.bot_activo
                                    AND EXCLUDED.escalado_at > COALESCE(f.bot_cambiado_at, '-infinity'::timestamptz)
                                   THEN 'escalamiento' ELSE f.bot_motivo END,
           bot_caduca       = CASE WHEN f.bot_activo
                                    AND EXCLUDED.escalado_at > COALESCE(f.bot_cambiado_at, '-infinity'::timestamptz)
                                   THEN true ELSE f.bot_caduca END,
           bot_cambiado_at  = CASE WHEN f.bot_activo
                                    AND EXCLUDED.escalado_at > COALESCE(f.bot_cambiado_at, '-infinity'::timestamptz)
                                   THEN now() ELSE f.bot_cambiado_at END,
           bot_cambiado_por = CASE WHEN f.bot_activo
                                    AND EXCLUDED.escalado_at > COALESCE(f.bot_cambiado_at, '-infinity'::timestamptz)
                                   THEN NULL ELSE f.bot_cambiado_por END,
           escalado_at      = EXCLUDED.escalado_at,
           conversacion_id  = EXCLUDED.conversacion_id,
           nombre           = COALESCE(EXCLUDED.nombre, f.nombre)
     WHERE f.escalado_at IS NULL OR EXCLUDED.escalado_at > f.escalado_at
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_f FROM frenados;

  RETURN v_n + v_f;
END $sincronizar$;

COMMENT ON FUNCTION crm.sincronizar_escalamientos() IS
  'Sincroniza escalado_at con el escalamiento MÁS RECIENTE desde que existe el contacto (y la oportunidad), '
  'y calla al bot en los que acaban de escalar (48 h) si nadie lo encendió a mano después. Nunca retroactivo.';
