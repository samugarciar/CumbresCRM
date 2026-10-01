-- =====================================================================
-- Dos perillas para el relevo, que hasta hoy era una sola.
--
-- AJUSTE A LA DECISIÓN 24, pedido por el autor del brief (1 oct 2026)
-- crm.ventana_relevo() hacía dos trabajos con el mismo valor:
--   · la VENTANA del relevo: cuánto tiempo sin mensajes del equipo hace
--     falta para que el bot recupere el turno (reactivar_relevos y la hora
--     que enseña la ficha, bot_vuelve_at);
--   · el FILTRO DE FRESCURA de registrar_relevo: un mensaje humano de más
--     de 6 h no calla al bot, porque al conectar un número Meta reproduce
--     el historial con mensajes de hace meses.
--
-- Coinciden por casualidad, no por diseño. Si mañana la ventana baja a
-- 2 h, el filtro bajaría con ella sin que nadie lo hubiera decidido: un eco
-- que llega con 3 horas de retraso —un webhook lento, un reintento de
-- Meta— dejaría de contar como relevo, y el bot le hablaría encima a una
-- persona que acaba de escribirle al cliente.
--
-- EL FILTRO DE FRESCURA ES LA SEGUNDA RED, NO LA PRIMERA
-- El brief fijó que el filtro primario es el ORIGEN: a registrar_relevo
-- solo la llaman los ecos (smb_message_echoes) y los envíos del emisor;
-- el historial, nunca. Eso lo cumple la plataforma, que es quien sabe de
-- dónde vino cada mensaje. La antigüedad queda para lo que se cuele:
-- webhooks demorados y ecos reproducidos.
--
-- La función se redefine con la MISMA firma: no hay sobrecarga posible, y
-- la prueba 23 lo vigila de todos modos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- La perilla nueva
--
-- Cerrada a authenticated a propósito, al revés que ventana_relevo. Esa
-- tiene que estar abierta porque la llama bot_vuelve_at, que es SECURITY
-- INVOKER y corre con el rol de quien mira la ficha. Esta solo la llama
-- registrar_relevo, que es SECURITY DEFINER: corre como su dueño y no
-- necesita que nadie más pueda ejecutarla. Sin el REVOKE nacería abierta
-- —Postgres da EXECUTE a PUBLIC en toda función nueva— y la prueba 27
-- caería, que es justo para lo que está.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.frescura_relevo()
RETURNS interval
LANGUAGE sql IMMUTABLE SET search_path = ''
AS $fr$ SELECT interval '6 hours'; $fr$;

COMMENT ON FUNCTION crm.frescura_relevo() IS
  'Antigüedad máxima de un mensaje humano para que cuente como relevo. 6 h, separada de crm.ventana_relevo() el 1 oct 2026. Es la SEGUNDA red: la primera es el origen (solo ecos y envíos del emisor). Cambiarla no mueve la ventana del relevo.';

REVOKE ALL ON FUNCTION crm.frescura_relevo() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION crm.frescura_relevo() TO service_role;

COMMENT ON FUNCTION crm.ventana_relevo() IS
  'Cuánto tiempo sin mensajes del equipo hace falta para que el bot recupere el turno tras un relevo. 6 h, decidido el 26 sep. Cambiarla cambia la regla, el aviso del historial y la hora que enseña la ficha. NO cambia el filtro de frescura de registrar_relevo: eso es crm.frescura_relevo(), desde el 1 oct.';

-- ---------------------------------------------------------------------
-- registrar_relevo, filtrando por frescura en vez de por la ventana
--
-- Idéntica a la de 20260926120001_crm_coexistencia.sql salvo esa línea:
-- se extrajo del fichero en vez de copiarse a mano.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.registrar_relevo(
  p_wa_phone_number_id text,
  p_telefono           text,
  p_ocurrido_at        timestamptz DEFAULT now())
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $relevo$
DECLARE
  v_inmobiliaria uuid;
  v_bot_atiende  boolean;
  -- Un reloj adelantado no puede estirar el relevo hacia el futuro.
  v_momento      timestamptz := LEAST(COALESCE(p_ocurrido_at, now()), now());
  v_contacto     crm.contactos%ROWTYPE;
BEGIN
  SELECT l.inmobiliaria_id, e.bot_atiende INTO v_inmobiliaria, v_bot_atiende
    FROM crm.lineas l
    JOIN crm.embudos e ON e.codigo = l.embudo
   WHERE l.wa_phone_number_id = p_wa_phone_number_id
     AND l.activa;

  IF v_inmobiliaria IS NULL OR NOT v_bot_atiende THEN
    RETURN false;
  END IF;

  -- La FRESCURA, no la ventana. Son dos perillas desde el 1 oct: que hoy
  -- valgan lo mismo es casualidad, y bajar la ventana no debe estrechar
  -- este filtro sin que nadie lo decida.
  IF v_momento < now() - crm.frescura_relevo() THEN
    RETURN false;
  END IF;

  SELECT * INTO v_contacto
    FROM crm.contactos c
   WHERE c.inmobiliaria_id = v_inmobiliaria
     AND c.telefono_e164 = crm.normalizar_telefono(p_telefono)
     AND c.deleted_at IS NULL
   FOR UPDATE;

  IF v_contacto.id IS NULL THEN
    RETURN false;
  END IF;

  IF NOT v_contacto.bot_activo AND v_contacto.bot_motivo IS DISTINCT FROM 'relevo' THEN
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
  ELSE
    -- Ya estaba en relevo: la ventana corre con el último mensaje. Sin
    -- aviso nuevo; uno por mensaje enterraría el historial.
    UPDATE crm.contactos
       SET bot_cambiado_at = GREATEST(bot_cambiado_at, v_momento)
     WHERE id = v_contacto.id;
  END IF;

  RETURN true;
END $relevo$;

COMMENT ON FUNCTION crm.registrar_relevo(text, text, timestamptz) IS
  'Contrato con la plataforma: una persona del equipo escribió a este teléfono por esta línea. Calla al bot (motivo relevo) o corre la ventana. Solo líneas donde el bot habla, solo mensajes más recientes que crm.frescura_relevo(), nunca sobre un silencio manual o de escalamiento. Solo service_role.';

-- CREATE OR REPLACE conserva los permisos; se reescriben para que esta
-- migración diga por sí sola quién puede llamarla.
REVOKE ALL ON FUNCTION crm.registrar_relevo(text, text, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION crm.registrar_relevo(text, text, timestamptz) TO service_role;
