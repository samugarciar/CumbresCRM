-- =====================================================================
-- Parar el bucle, y que lo que se pierde deje de perderse callado.
--
-- Los dos únicos arreglos de la auditoría del 18 sep que NO pueden
-- esperar al rediseño. El criterio para separarlos del resto: esperar
-- con los demás cuesta trabajo, y el trabajo se hace después al mismo
-- precio; esperar con estos dos cuesta HISTORIA, y la historia no se
-- recompra.
--
-- Ninguno toca el modelo. No hay nada aquí que el rediseño de las fases
-- 6 y 7 tenga que deshacer.
--
-- ─────────────────────────────────────────────────────────────────────
-- 1 · EL BUCLE DE LAS NUEVE
--
-- Medido en producción. La peor víctima, un solo contacto:
--     creada 14/09 20:31 · cerrada 15/09 09:00
--     creada 15/09 09:00 · cerrada 16/09 09:00
--     creada 16/09 09:00 · cerrada 17/09 09:00
--     creada 17/09 09:00 · cerrada 18/09 09:00
--     creada 18/09 09:00 · abierta
-- Cierre y apertura en el MISMO SEGUNDO, cada día. En total: 1.895
-- oportunidades para 1.350 contactos, 162 contactos con más de una, 607
-- pérdidas marcadas «no_responde» que nadie perdió, y 411 reaperturas
-- ocurridas en menos de diez minutos tras su cierre.
--
-- El mecanismo NO es el que parece. `cerrar_fantasmas` (0 9 * * *) solo
-- escribe en oportunidades y transiciones, así que no dispara nada. Quien
-- reabre es `recalcular_pipeline` (*/5), que cae en el mismo minuto:
-- toma su lista de oportunidades abiertas, y cuando llega a un contacto
-- cuyo cierre ya se confirmó, `recalcular_oportunidad` no encuentra
-- ninguna abierta y —servicial— abre otra.
--
-- Por eso el arreglo no es mover el cron. Mover el cron deja la carrera
-- viva: basta con que una pasada larga se solape con el cierre. El
-- arreglo es que UNA PASADA DE MANTENIMIENTO NO PUEDA ABRIR NADA.
-- Abrir una oportunidad es responder a un hecho nuevo, y los hechos
-- nuevos llegan por el trigger de crm.actividades.
--
-- El horario se separa igualmente, como segunda línea: cuesta nada.
--
-- LO QUE ESTO NO HACE: limpiar las 607 pérdidas falsas ni las
-- oportunidades duplicadas que ya existen. Eso es cirugía sobre datos y
-- necesita su propia decisión — pero a partir de aquí deja de crecer.
--
-- ─────────────────────────────────────────────────────────────────────
-- 2 · LAS CITAS QUE SE PIERDEN CALLADAS
--
-- Ver el comentario dentro de proyectar_cita(). Cinco citas reales que
-- nunca llegaron al CRM, sin un solo registro de fallo.
-- =====================================================================

CREATE OR REPLACE FUNCTION crm.recalcular_oportunidad(
  p_contacto_id uuid,
  p_abrir       boolean DEFAULT true)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $recalcular$
DECLARE
  v_op       crm.oportunidades%ROWTYPE;
  v_orden    smallint;
  v_nueva    text;
  v_movio    boolean := false;
BEGIN
  SELECT * INTO v_op FROM crm.oportunidades o
   WHERE o.contacto_id = p_contacto_id AND o.estado = 'abierta';

  IF v_op.id IS NULL THEN
    -- AQUÍ ESTABA EL BUCLE. Sin esta salida, la pasada periódica de las
    -- 9:00 encontraba cerrada la oportunidad que el cierre por silencio
    -- acababa de cerrar —los dos crones caen en el mismo minuto— y
    -- abría otra en el acto. Al día siguiente, otra vez.
    -- Abrir una oportunidad es responder a un HECHO NUEVO, y de eso se
    -- encarga el trigger de crm.actividades. Una pasada de
    -- mantenimiento no tiene ningún hecho nuevo que contar.
    IF NOT p_abrir THEN RETURN false; END IF;
    PERFORM crm.abrir_oportunidad(p_contacto_id);
    SELECT * INTO v_op FROM crm.oportunidades o
     WHERE o.contacto_id = p_contacto_id AND o.estado = 'abierta';
    IF v_op.id IS NULL THEN RETURN false; END IF;
    v_movio := true;
  END IF;

  v_orden := crm.orden_por_evidencia(p_contacto_id);

  -- SOLO HACIA ADELANTE. Sin este GREATEST, alguien que ya visitó y
  -- luego escribe un mensaje retrocedería a "contactado" y el tablero
  -- dejaría de significar nada.
  SELECT e.codigo INTO v_nueva FROM crm.etapas e
   WHERE e.orden = GREATEST(
     v_orden,
     (SELECT e2.orden FROM crm.etapas e2 WHERE e2.codigo = v_op.etapa));

  IF v_nueva IS DISTINCT FROM v_op.etapa THEN
    UPDATE crm.oportunidades
       SET etapa = v_nueva, etapa_at = now(), updated_at = now()
     WHERE id = v_op.id;

    INSERT INTO crm.transiciones
      (inmobiliaria_id, oportunidad_id, etapa_desde, etapa_hasta, estado_hasta, origen)
    VALUES (v_op.inmobiliaria_id, v_op.id, v_op.etapa, v_nueva, 'abierta', 'sistema');

    v_movio := true;
  END IF;

  -- EL ESCALAMIENTO NO SE CALCULA AQUÍ, Y ES DELIBERADO.
  -- Esta función corre en el trigger de CADA actividad, o sea en cada
  -- mensaje de WhatsApp que entra. El escalamiento vive en
  -- public.agente_comercial_uso, que no es nuestra: no tiene índice por
  -- conversacion_id y el puente hacia el contacto obliga a comparar
  -- m.id::text con metadata->>'origen_id', que no puede usar la clave
  -- primaria. Medido en producción con EXPLAIN ANALYZE: 614 ms, dos
  -- escaneos secuenciales completos. Meter eso en el camino de cada
  -- mensaje entrante sería pagar medio segundo por mensaje para siempre.
  -- Se hace de una sola pasada en crm.sincronizar_escalamientos().
  RETURN v_movio;
END $recalcular$;

-- ---------------------------------------------------------------------
-- La pasada periódica, que ahora solo avanza
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.recalcular_pipeline()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $todo$
DECLARE
  v_contacto uuid;
  v_movidas  integer := 0;
BEGIN
  FOR v_contacto IN
    SELECT o.contacto_id FROM crm.oportunidades o WHERE o.estado = 'abierta'
  LOOP
    BEGIN
      -- p_abrir => false: esta pasada AVANZA etapas, nunca abre.
      IF crm.recalcular_oportunidad(v_contacto, false) THEN
        v_movidas := v_movidas + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;   -- una oportunidad rota no puede detener a las otras 1.262
    END;
  END LOOP;

  -- Una sola vez para todas, por lo caro que sale (ver 10-bis).
  BEGIN
    PERFORM crm.sincronizar_escalamientos();
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN v_movidas;
END $todo$;

REVOKE ALL ON FUNCTION crm.recalcular_oportunidad(uuid, boolean) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION crm.recalcular_pipeline() FROM public, anon, authenticated;

-- La firma vieja de un solo argumento deja de existir: con las dos, una
-- llamada por nombre se vuelve ambigua y Postgres la rechaza en tiempo
-- de ejecución, que es el peor momento para enterarse.
DROP FUNCTION IF EXISTS crm.recalcular_oportunidad(uuid);

-- ---------------------------------------------------------------------
-- Segunda línea: que los dos crones no compartan minuto
-- ---------------------------------------------------------------------
DO $agenda$
BEGIN
  PERFORM cron.schedule(
    'crm_cerrar_fantasmas', '7 9 * * *',
    $trabajo$SELECT crm.cerrar_fantasmas(30);$trabajo$);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron no disponible: %', SQLERRM;
END $agenda$;

-- ---------------------------------------------------------------------
-- La proyección de citas, que ahora grita
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.proyectar_cita()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_contacto uuid;
  v_ids      jsonb := '[]'::jsonb;
  v_tel      text;
  v_tipo     text;
BEGIN
  BEGIN
    v_tel := crm.normalizar_telefono(NEW.cliente_telefono);

    IF v_tel IS NOT NULL THEN
      v_ids := v_ids || jsonb_build_array(
        jsonb_build_object('tipo', 'telefono_e164', 'valor', v_tel));
    END IF;
    IF NEW.cliente_email IS NOT NULL AND NEW.cliente_email <> '' THEN
      v_ids := v_ids || jsonb_build_array(
        jsonb_build_object('tipo', 'email', 'valor', lower(trim(NEW.cliente_email))));
    END IF;

    v_contacto := crm.resolver_contacto(
      NEW.inmobiliaria_id, v_ids, NEW.cliente_nombre, 'cita',
      'cliente', NEW.cliente_telefono);

    IF v_contacto IS NULL THEN
      -- ANTES: RETURN NULL a secas. Como no lanzaba excepción, jamás
      -- llegaba al manejador de abajo y crm.eventos se quedaba en cero:
      -- la cita desaparecía y el panel de salud decía que todo iba bien.
      -- Medido el 18 sep: 5 citas perdidas así, la última de ayer. Las
      -- cinco traen basura donde va el teléfono — una guarda el texto
      -- del propio prompt del bot, "NO lo tenemos, pídeselo al cliente".
      PERFORM crm.registrar_fallo(
        NEW.inmobiliaria_id, 'cita', 'citas', NEW.id::text,
        jsonb_build_object(
          'motivo', 'no se pudo resolver el contacto',
          'cliente_telefono', NEW.cliente_telefono,
          'cliente_nombre', NEW.cliente_nombre,
          'fecha', NEW.fecha),
        'Sin identidad utilizable: el teléfono no normaliza y no hay correo');
      RETURN NULL;
    END IF;

    v_tipo := CASE NEW.estado
                WHEN 'completada' THEN 'visita_realizada'
                WHEN 'cancelada'  THEN 'visita_cancelada'
                ELSE 'visita_agendada'
              END;

    INSERT INTO crm.actividades (
      inmobiliaria_id, tipo, origen, contacto_id, inmueble_id, cita_id,
      ocurrido_at, metadata)
    VALUES (
      NEW.inmobiliaria_id, v_tipo, 'sistema', v_contacto,
      NEW.inmueble_id, NEW.id,
      CASE WHEN TG_OP = 'INSERT' THEN NEW.created_at
           ELSE now() END,
      jsonb_build_object(
        'origen_tabla', 'citas',
        -- El desenlace es un hecho distinto del agendamiento, así que
        -- lleva su propia llave y ambos conviven en el timeline.
        'origen_id', NEW.id::text ||
          CASE WHEN v_tipo = 'visita_agendada' THEN '' ELSE ':' || NEW.estado END,
        'fecha', NEW.fecha, 'hora', NEW.hora_inicio))
    ON CONFLICT DO NOTHING;

    UPDATE crm.contactos
       SET ultima_actividad_at = GREATEST(COALESCE(ultima_actividad_at, now()), now())
     WHERE id = v_contacto;

  EXCEPTION WHEN OTHERS THEN
    PERFORM crm.registrar_fallo(
      NEW.inmobiliaria_id, 'cita', 'citas', NEW.id::text,
      jsonb_build_object('estado', NEW.estado), SQLERRM);
  END;

  RETURN NULL;
END $$;
