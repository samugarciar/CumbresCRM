-- =====================================================================
-- El freno de la 324 deja de callar al bot en la línea 312 (26 oct 2026)
--
-- LO QUE PASABA
-- crm.frenos_bot es el freno del bot para quien NO está en el CRM: lo que
-- todavía entra por la 324 (Kommo y n8n). Lo pone el escalamiento de esa
-- conversación y lo quita el cron (20261016120001). Pero
-- crm.bot_puede_responder lo miraba siempre, por teléfono, sin importar
-- por dónde entró el mensaje: a una persona que pidió un asesor por la 324
-- y luego escribe por la línea oficial (312, Cloud API) el bot no le
-- contestaba en la 312, donde el CRM sí la ve y nadie sabe que está
-- callada.
--
-- LA REGLA NUEVA
-- crm.bot_puede_responder(inmobiliaria, teléfono, wa_phone_number_id):
--   · contactos.bot_activo aplica siempre (el silencio del CRM es de la
--     persona, por cualquier línea);
--   · el freno de crm.frenos_bot aplica solo si el mensaje NO entró por una
--     línea activa de crm.lineas de esa inmobiliaria (p_wa_phone_number_id
--     NULL o desconocido): es el freno de la 324.
-- La versión de dos argumentos se queda y delega con NULL: el camino de n8n
-- y de la 324 sigue exactamente igual que hoy.
--
-- La nueva nace cerrada: solo la llama la plataforma (service_role).
-- Sin cambios de datos. Idempotente.
-- =====================================================================

CREATE OR REPLACE FUNCTION crm.bot_puede_responder(
  p_inmobiliaria_id    uuid,
  p_telefono           text,
  p_wa_phone_number_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $puede$
  SELECT COALESCE(
           (SELECT bool_and(c.bot_activo)
              FROM crm.contactos c
             WHERE c.inmobiliaria_id = p_inmobiliaria_id
               AND c.telefono_e164 = crm.normalizar_telefono(p_telefono)
               AND c.deleted_at IS NULL),
           true)
     AND (
           -- Entró por una línea oficial: el freno de la 324 no aplica.
           EXISTS (SELECT 1
                     FROM crm.lineas l
                    WHERE p_wa_phone_number_id IS NOT NULL
                      AND l.wa_phone_number_id = p_wa_phone_number_id
                      AND l.inmobiliaria_id = p_inmobiliaria_id
                      AND l.activa)
           OR COALESCE(
                (SELECT f.bot_activo
                   FROM crm.frenos_bot f
                  WHERE f.inmobiliaria_id = p_inmobiliaria_id
                    AND f.telefono_e164 = crm.normalizar_telefono(p_telefono)),
                true)
         );
$puede$;

COMMENT ON FUNCTION crm.bot_puede_responder(uuid, text, text) IS
  '¿Puede el bot contestarle a este teléfono por esta línea? contactos.bot_activo aplica siempre; '
  'el freno de crm.frenos_bot (la 324) solo si el mensaje no entró por una línea activa de crm.lineas.';

REVOKE ALL ON FUNCTION crm.bot_puede_responder(uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION crm.bot_puede_responder(uuid, text, text) TO service_role;

-- La de dos argumentos (n8n, la 324): delega sin línea, que es lo de hoy.
CREATE OR REPLACE FUNCTION crm.bot_puede_responder(p_inmobiliaria_id uuid, p_telefono text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $puede2$
  SELECT crm.bot_puede_responder(p_inmobiliaria_id, p_telefono, NULL::text);
$puede2$;

COMMENT ON FUNCTION crm.bot_puede_responder(uuid, text) IS
  'Versión sin línea (n8n y la 324): delega en bot_puede_responder(uuid, text, text) con NULL, '
  'así que el freno de crm.frenos_bot aplica como siempre.';
