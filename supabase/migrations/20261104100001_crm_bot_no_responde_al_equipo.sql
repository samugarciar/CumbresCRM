-- =====================================================================
-- El bot no le responde a la gente del equipo (4 nov 2026)
--
-- EL CASO QUE LO TRAE
-- Los asesores le escriben a la línea comercial desde su celular: para
-- pedir un enlace, avisar que un inmueble ya no está, preguntar por las
-- citas. Y el bot les contesta como a un cliente. El 4 nov Juan Sebastián
-- avisó que Madera Natural ya no estaba disponible y el bot le respondió
-- «Tomo nota»: no toma nota de nada, y el aviso se perdió en el chat.
-- Cuando la oficina le escribe desde el CRM, el relevo calla al bot, pero
-- vuelve a los 30 minutos (crm.ventana_relevo): ese día pasó tres veces.
--
-- LA REGLA
-- Un teléfono que es de un usuario ACTIVO de la inmobiliaria
-- (public.usuarios.telefono, el que se edita en /asesores de la
-- plataforma) nunca recibe respuesta del bot. Sin marcar a nadie a mano:
-- un asesor nuevo queda cubierto al registrarlo con su número, y uno
-- desactivado vuelve a ser un contacto como cualquiera.
--  · crm.telefono_del_equipo: la pregunta, en un solo sitio.
--  · crm.bot_puede_responder: la hace antes que todo lo demás.
--  · crm.registrar_relevo: no abre relevo con el equipo. No hay nada que
--    callar ni que devolver, y el historial no se llena de «el bot deja
--    de / vuelve a responderle».
--  · crm.del_equipo: el nombre, para que la ficha lo diga.
-- Sus mensajes siguen entrando al CRM igual que siempre: la oficina les
-- puede escribir desde la ficha.
--
-- Cuerpos de bot_puede_responder y registrar_relevo tomados de producción
-- el 4 nov (pg_get_functiondef), con solo esos cambios. CREATE OR REPLACE
-- conserva los permisos. Idempotente.
-- =====================================================================

-- La columna es de la plataforma (su migración 2026-10-23_asesores_activos)
-- y en producción ya existe: esto no hace nada allá. Está aquí para que la
-- base local, que se arma solo con las migraciones del CRM, la tenga.
ALTER TABLE public.usuarios
  ADD COLUMN IF NOT EXISTS activo boolean NOT NULL DEFAULT true;


-- ---------------------------------------------------------------------
-- 1 · ¿Este teléfono es de alguien del equipo?
--
-- De sistema: la llaman bot_puede_responder y registrar_relevo, que son
-- SECURITY DEFINER. Nace cerrada (20261001235001).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.telefono_del_equipo(p_inmobiliaria_id uuid, p_telefono text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- Las dos puntas normalizadas: en /asesores el número se escribe como
  -- sea («300 555 1234», «+57 300…») y WhatsApp lo manda con el 57.
  -- Un BSUID no normaliza a teléfono (NULL) y nunca coincide.
  SELECT EXISTS (
    SELECT 1
      FROM public.usuarios u
     WHERE u.inmobiliaria_id = p_inmobiliaria_id
       AND u.activo
       AND crm.normalizar_telefono(u.telefono) = crm.normalizar_telefono(p_telefono)
  );
$function$;

COMMENT ON FUNCTION crm.telefono_del_equipo(uuid, text) IS
  'true si el teléfono es de un usuario activo de la inmobiliaria (public.usuarios.telefono). '
  'Al equipo el bot nunca le responde y el relevo no se abre (20261104100001).';


-- ---------------------------------------------------------------------
-- 2 · bot_puede_responder: al equipo, nunca
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.bot_puede_responder(p_inmobiliaria_id uuid, p_telefono text, p_wa_phone_number_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- Alguien del equipo: ni con el bot encendido en su ficha.
  SELECT NOT crm.telefono_del_equipo(p_inmobiliaria_id, p_telefono)
     AND COALESCE(
           (SELECT bool_and(c.bot_activo)
              FROM crm.contactos c
             WHERE c.inmobiliaria_id = p_inmobiliaria_id
               AND (c.telefono_e164 = crm.normalizar_telefono(p_telefono)
                    OR c.id IN (SELECT i.contacto_id
                                  FROM crm.identidades i
                                 WHERE i.inmobiliaria_id = p_inmobiliaria_id
                                   AND i.tipo = 'whatsapp_bsuid'
                                   AND i.valor = btrim(p_telefono)))
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
$function$;


-- ---------------------------------------------------------------------
-- 3 · registrar_relevo: con el equipo no hay relevo
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.registrar_relevo(p_wa_phone_number_id text, p_telefono text, p_ocurrido_at timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_inmobiliaria uuid;
  v_bot_atiende  boolean;
  -- Un reloj adelantado no puede estirar el relevo hacia el futuro.
  v_momento      timestamptz := LEAST(COALESCE(p_ocurrido_at, now()), now());
  v_contacto     crm.contactos%ROWTYPE;
  v_duracion     text := crm.duracion_legible(crm.ventana_relevo());
BEGIN
  SELECT l.inmobiliaria_id, e.bot_atiende INTO v_inmobiliaria, v_bot_atiende
    FROM crm.lineas l
    JOIN crm.embudos e ON e.codigo = l.embudo
   WHERE l.wa_phone_number_id = p_wa_phone_number_id
     AND l.activa;

  IF v_inmobiliaria IS NULL OR NOT v_bot_atiende THEN
    RETURN false;
  END IF;

  -- Al equipo el bot nunca le responde (crm.bot_puede_responder): callarlo
  -- no cambiaría nada y solo dejaría dos avisos en el historial.
  IF crm.telefono_del_equipo(v_inmobiliaria, p_telefono) THEN
    RETURN false;
  END IF;

  -- La FRESCURA, no la ventana: la segunda red contra el historial que
  -- Meta reproduce al conectar (20261001150001). Con la ventana en 1 h la
  -- guarda de abajo es más estricta, pero esta sigue protegiendo si un día
  -- la ventana sube por encima de las 6 h.
  IF v_momento < now() - crm.frescura_relevo() THEN
    RETURN false;
  END IF;

  -- Un relevo que nace vencido no se abre: un eco atrasado más de una
  -- ventana callaría al bot solo para devolverle la voz en la siguiente
  -- pasada del cron, con dos avisos en el historial. Y sobre un relevo
  -- abierto no movería nada que importe.
  IF v_momento <= now() - crm.ventana_relevo() THEN
    RETURN false;
  END IF;

  SELECT * INTO v_contacto
    FROM crm.contactos c
   WHERE c.inmobiliaria_id = v_inmobiliaria
     AND (c.telefono_e164 = crm.normalizar_telefono(p_telefono)
          OR c.id IN (SELECT i.contacto_id
                        FROM crm.identidades i
                       WHERE i.inmobiliaria_id = v_inmobiliaria
                         AND i.tipo = 'whatsapp_bsuid'
                         AND i.valor = btrim(p_telefono)))
     AND c.deleted_at IS NULL
   FOR UPDATE OF c;

  IF v_contacto.id IS NULL THEN
    RETURN false;
  END IF;

  IF v_contacto.bot_activo THEN
    UPDATE crm.contactos
       SET bot_activo       = false,
           bot_motivo       = 'relevo',
           bot_cambiado_at  = v_momento,
           bot_cambiado_por = NULL   -- el eco no dice QUIÉN escribió
     WHERE id = v_contacto.id;

    INSERT INTO crm.actividades
      (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
    VALUES (v_contacto.inmobiliaria_id, 'sistema', 'sistema', v_contacto.id,
            'El bot deja de responderle: alguien del equipo le escribió.',
            v_momento);

  ELSIF v_contacto.bot_motivo = 'escalamiento' AND v_contacto.bot_caduca THEN
    -- Pidió una persona y una persona le escribió: desde aquí es un
    -- relevo como cualquiera. Si el asesor no vuelve a escribir en una
    -- ventana, el bot vuelve.
    UPDATE crm.contactos
       SET bot_motivo       = 'relevo',
           bot_cambiado_at  = v_momento,
           bot_cambiado_por = NULL
     WHERE id = v_contacto.id;

    INSERT INTO crm.actividades
      (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
    VALUES (v_contacto.inmobiliaria_id, 'sistema', 'sistema', v_contacto.id,
            'Alguien del equipo atendió a quien pidió una persona: el bot vuelve si nadie le escribe en '
              || v_duracion || '.',
            v_momento);

  ELSIF v_contacto.bot_motivo = 'relevo' THEN
    -- Ya estaba en relevo: la ventana corre con el último mensaje. Sin
    -- aviso nuevo; uno por mensaje enterraría el historial.
    UPDATE crm.contactos
       SET bot_cambiado_at = GREATEST(bot_cambiado_at, v_momento)
     WHERE id = v_contacto.id;

  ELSE
    -- Manual, o un escalamiento que alguien dejó sin caducidad: manda
    -- quien lo decidió.
    RETURN false;
  END IF;

  RETURN true;
END $function$;


-- ---------------------------------------------------------------------
-- 4 · La ficha: ¿de quién del equipo es este contacto?
--
-- De pantalla: SECURITY INVOKER, así que manda la RLS de las dos tablas
-- (el contacto visible para quien mira; los usuarios de su inmobiliaria).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.del_equipo(p_contacto_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  SELECT u.nombre_completo
    FROM crm.contactos c
    JOIN public.usuarios u
      ON u.inmobiliaria_id = c.inmobiliaria_id
     AND u.activo
     AND crm.normalizar_telefono(u.telefono) = c.telefono_e164
   WHERE c.id = p_contacto_id
     AND c.deleted_at IS NULL
   ORDER BY u.created_at
   LIMIT 1;
$function$;

COMMENT ON FUNCTION crm.del_equipo(uuid) IS
  'El nombre del usuario activo dueño del teléfono de este contacto, o NULL. La ficha lo usa para '
  'decir que el bot no le responde (crm.telefono_del_equipo).';

GRANT EXECUTE ON FUNCTION crm.del_equipo(uuid) TO authenticated;
