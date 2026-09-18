-- =====================================================================
-- Escribirle a alguien desde el CRM: la regla, antes que el canal.
--
-- LO QUE SE CONSTRUYE Y LO QUE NO
-- El canal propio es la fase 5-B y depende de sacar el número de Kommo.
-- Lo que SÍ se puede terminar hoy es todo lo demás: la caja de escribir,
-- el estado de la ventana, y —esto es lo que importa— **la regla de las
-- 24 horas impuesta donde no se puede saltar**.
--
-- POR QUÉ NO BASTA CON DESHABILITAR EL BOTÓN
-- Un botón apagado es una sugerencia. Este proyecto ya decidió lo mismo
-- con las variables de las plantillas: «la garantía va en la base y no en
-- el formulario, porque un formulario se puede saltar». Aquí es peor,
-- porque saltárselo no da un error visible: Meta contesta 131047, el
-- mensaje no se entrega, y **el cliente no recibe nada mientras el asesor
-- cree que sí**.
--
-- Así que cuando llegue el transporte, lo único que habrá que añadir es
-- la llamada HTTP. La decisión de si se puede escribir ya estará tomada
-- aquí, y estará probada.
-- =====================================================================

-- ---------------------------------------------------------------------
-- ¿Se le puede escribir texto libre a esta persona, ahora mismo?
--
-- Se apoya en crm.ventana_whatsapp() en vez de recalcular el plazo: si
-- un día Meta cambia las 24 horas, se cambia en un sitio. Duplicar la
-- regla es cómo se arregla en una capa y se queda mal en la otra — ya
-- pasó en este proyecto con el umbral de la alerta.
--
-- NULL (nunca nos escribió) cuenta como NO: sin un mensaje suyo no hay
-- ventana que abrir, y es justo el caso de los 308 contactos que llegaron
-- por una cita sin haber escrito nunca.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.puede_escribir_libre(p_contacto_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $pel$
  SELECT COALESCE(crm.ventana_whatsapp(p_contacto_id) > now(), false);
$pel$;

COMMENT ON FUNCTION crm.puede_escribir_libre(uuid) IS
  'Si la ventana de 24 h de WhatsApp sigue abierta para esta persona. Fuera de ella solo caben plantillas aprobadas por Meta.';

GRANT EXECUTE ON FUNCTION crm.puede_escribir_libre(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- Encolar un mensaje para que salga
--
-- Escribe en crm.envios con estado 'pendiente', que significa
-- exactamente lo que dice: aceptado por el CRM, todavía no entregado a
-- Meta. No miente en ninguna dirección.
--
-- ⚠️ ESTA FUNCIÓN NO MANDA NADA. Hoy nadie la llama desde la interfaz, a
-- propósito: una cola que nadie vacía es peor que no tener cola — el
-- asesor pulsaría enviar, vería «encolado», y el cliente no recibiría
-- nada nunca. Se construye ahora porque su FORMA no depende del
-- transporte, y porque es donde vive la regla que sí se puede probar hoy.
-- El día que exista el canal, lo que se añade es quien vacíe la cola.
--
-- LA REGLA, Y ES LO ÚNICO IMPORTANTE DE AQUÍ:
-- texto libre fuera de la ventana REVIENTA. Con plantilla aprobada, pasa.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.encolar_envio(
  p_contacto_id  uuid,
  p_cuerpo       text,
  p_plantilla_id uuid DEFAULT NULL,
  p_inmueble_id  uuid DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $enc$
DECLARE
  v_inmobiliaria uuid;
  v_aprobada boolean := false;
  v_id uuid;
BEGIN
  SELECT c.inmobiliaria_id INTO v_inmobiliaria
    FROM crm.contactos c
   WHERE c.id = p_contacto_id AND c.deleted_at IS NULL;

  IF v_inmobiliaria IS NULL THEN
    RAISE EXCEPTION 'Ese contacto no existe o no es tuyo';
  END IF;

  IF btrim(COALESCE(p_cuerpo, '')) = '' THEN
    RAISE EXCEPTION 'No se puede mandar un mensaje vacío';
  END IF;

  -- Una plantilla sirve fuera de la ventana SOLO si Meta la aprobó. Una
  -- en borrador es texto libre con otro nombre.
  IF p_plantilla_id IS NOT NULL THEN
    SELECT (p.estado_meta = 'aprobada') INTO v_aprobada
      FROM crm.plantillas p WHERE p.id = p_plantilla_id AND p.activa;
    v_aprobada := COALESCE(v_aprobada, false);
  END IF;

  IF NOT crm.puede_escribir_libre(p_contacto_id) AND NOT v_aprobada THEN
    RAISE EXCEPTION 'Fuera de la ventana de 24 h solo se puede enviar una plantilla aprobada por Meta'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO crm.envios
    (inmobiliaria_id, contacto_id, plantilla_id, inmueble_id,
     cuerpo, canal, estado, enviado_por)
  VALUES (v_inmobiliaria, p_contacto_id, p_plantilla_id, p_inmueble_id,
          p_cuerpo, 'meta', 'pendiente', auth.uid())
  RETURNING id INTO v_id;

  RETURN v_id;
END $enc$;

COMMENT ON FUNCTION crm.encolar_envio(uuid, text, uuid, uuid) IS
  'Encola un mensaje en crm.envios. RECHAZA texto libre fuera de la ventana de 24 h. No entrega nada: el transporte es la fase 5-B.';

GRANT EXECUTE ON FUNCTION crm.encolar_envio(uuid, text, uuid, uuid) TO authenticated;
