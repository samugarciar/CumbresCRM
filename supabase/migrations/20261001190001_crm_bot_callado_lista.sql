-- =====================================================================
-- Todas las conversaciones con el bot callado, y cuánto llevan así.
--
-- DECISIÓN 25 (1 oct 2026)
-- El escalamiento que alguien atendió NO vuelve solo: le devolvería al
-- bot justo la conversación que decidió que lo superaba. Pero un bot
-- callado para siempre es una conversación que se puede pudrir sin que
-- nadie se entere. La respuesta del autor del brief: hacerlo VISIBLE.
--
-- POR QUÉ UNA LISTA Y NO OTRO AVISO
-- crm.mi_dia ya avisa de 'bot_callado' —escalados que nadie atendió— y
-- desde el 1 oct existe bot_caduca para los silencios que no vuelven
-- solos. Un aviso más en «Mi día» por cada bot callado repetiría esos dos
-- y, sobre todo, metería ahí los silencios MANUALES y los de RELEVO, que
-- son normales: alguien dijo que se encargaba. Una lista de tareas que
-- grita por lo normal deja de leerse.
--
-- Así que esto es un sitio donde MIRAR, no un aviso: todas, sea cual sea
-- el motivo, con lo necesario para ver cuál se está pudriendo:
--   · desde cuándo, y quién lo calló;
--   · si el bot vuelve solo, y cuándo; o si no vuelve nunca, y por qué;
--   · cuándo escribió la persona por última vez.
-- crm.mi_dia no se toca.
--
-- QUÉ NO DICE
-- No dice "sin responder". Las asesoras contestan en Kommo, que el CRM no
-- ve, y un "sin responder" calculado desde aquí sería falso la mitad de
-- las veces. Se enseña el HECHO —cuándo escribió la persona— y el juicio
-- lo pone quien mira. Cuando la coexistencia traiga los ecos del celular,
-- esto se podrá afinar.
--
-- Vista con security_invoker: la RLS de quien consulta decide qué filas
-- ve. No hay función nueva, así que no hay nada que cerrar en la lista
-- blanca de la prueba 27: las tres que usa ya son de pantalla.
-- =====================================================================

CREATE VIEW crm.v_bot_callado WITH (security_invoker = true) AS
SELECT
  c.id               AS contacto_id,
  c.inmobiliaria_id,
  c.nombre,
  c.telefono_e164,
  c.bot_motivo       AS motivo,
  c.bot_cambiado_at  AS callado_desde,
  c.bot_cambiado_por AS callado_por,
  u.nombre_completo  AS callado_por_nombre,
  c.bot_caduca,
  -- Solo significa algo para el escalamiento: si alguien lo atendió, ese
  -- silencio ya no caduca (decisión 25).
  aten.atendido,
  -- Cuándo recupera el bot la voz por su cuenta, con las MISMAS reglas que
  -- los dos crones (crm.reactivar_relevos y crm.reactivar_bots) y las
  -- mismas perillas. NULL = no vuelve solo: manual, escalamiento atendido,
  -- o uno de los silencios anteriores al 1 oct que se dejaron sin caducar.
  CASE
    WHEN c.bot_motivo = 'relevo'
      THEN c.bot_cambiado_at + crm.ventana_relevo()
    WHEN c.bot_motivo = 'escalamiento' AND c.bot_caduca AND NOT aten.atendido
      THEN c.bot_cambiado_at + crm.ventana_silencio_escalamiento()
  END                AS vuelve_at,
  (SELECT max(a.ocurrido_at)
     FROM crm.actividades a
    WHERE a.contacto_id = c.id
      AND a.tipo = 'mensaje_entrante') AS ultimo_entrante_at
FROM crm.contactos c
CROSS JOIN LATERAL (
  SELECT c.bot_motivo = 'escalamiento'
         AND crm.bot_atendido_desde(c.id, c.bot_cambiado_at) AS atendido
) aten
LEFT JOIN crm.v_asesores u ON u.id = c.bot_cambiado_por
WHERE c.deleted_at IS NULL
  AND NOT c.bot_activo;

COMMENT ON VIEW crm.v_bot_callado IS
  'Todas las conversaciones con el bot callado, sea cual sea el motivo: desde cuándo, quién, si vuelve solo y cuándo, y cuándo escribió la persona por última vez. Decisión 25. Es un sitio donde mirar, no un aviso: los avisos siguen en crm.mi_dia.';

-- Solo lectura. Los privilegios por defecto del esquema le darían a
-- authenticated también INSERT, UPDATE y DELETE: con los JOIN la vista no
-- es actualizable y fallarían igual, pero un permiso que no se usa es un
-- permiso que alguien acaba usando el día que la vista cambie.
REVOKE ALL ON crm.v_bot_callado FROM PUBLIC, anon, authenticated;
GRANT SELECT ON crm.v_bot_callado TO authenticated, service_role;
