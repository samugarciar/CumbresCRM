-- =====================================================================
-- Envíos masivos: lo que no llega se gestiona a mano (26 oct 2026)
--
-- EL CASO QUE LO TRAE
-- Cartera exporta su Excel; la hoja «Envios WhatsApp» trae, por
-- inquilino, el número de WhatsApp (o nada), lo que debe y cuántas
-- facturas tiene vencidas. Se sube al CRM y sale por la línea
-- administrativa con una plantilla aprobada. Lo que decidió Samuel: TODA
-- persona a la que el mensaje no se le pudo mandar, o no le llegó, queda
-- como seguimiento manual de QUIEN LANZÓ el envío. Hasta hoy esa gente
-- solo existía como una fila «No se envió» o «Falló» en el archivo de
-- resultados, y nadie la tenía en su lista.
--
-- QUIÉN ENTRA EN LA GESTIÓN MANUAL (crm.pendientes_gestion_envio)
-- Sale de crm.resultados_envio_masivo, el mismo cálculo que ve cartera;
-- no se repite aquí. Entra:
--  · excluida por sin_telefono, telefono_invalido o faltan_datos: el
--    mensaje no se pudo armar o no había a dónde mandarlo;
--  · fallido: Meta lo rechazó;
--  · sin_confirmar: la plataforma no contestó en 10 minutos (o no hay
--    envío): no se sabe si salió, y reintentarlo podría duplicarlo;
--  · enviado hace más de 24 horas sin pasar a entregado: el teléfono no
--    existe en WhatsApp, está apagado o el número es de otra persona.
-- NO entra:
--  · repetido: la otra fila del mismo teléfono sí sale;
--  · baja: pidió no recibir más mensajes, y llamarla es lo mismo;
--  · frecuencia: ya recibió un envío masivo esta semana;
--  · cancelado: alguien canceló el envío a propósito (lo que no salió no
--    se convierte en trabajo de nadie; si Samuel lo quiere, es una línea).
--
-- COLUMNAS EN LA FILA Y NO UNA TABLA APARTE
--  · Una gestión es de una fila y solo una: la fila ya tiene su id, su
--    inmobiliaria, su RLS y su cerrojo. Una tabla aparte repetiría las
--    tres cosas (políticas, disparador, REVOKE) para guardar tres datos.
--  · El disparador guardián no estorba, ayuda: crm.marcar_gestion_manual
--    es una de «sus funciones», enciende la misma marca de la transacción
--    que crear y lanzar, y toca solo sus tres columnas. Sin la marca,
--    nadie las cambia desde el navegador, igual que el estado.
--  · La purga de los 90 días ya recorre esas filas: la nota («pagó la
--    mitad, llamar el viernes») habla de la deuda de una persona y se
--    borra con lo demás (crm.purgar_envios_masivos, mismo cuerpo + la
--    nota).
--
-- MI DÍA
-- Un renglón «Envío "<nombre>": N personas para gestionar a mano» en el
-- día de quien lanzó el envío (lanzado_por = p_asesor; con p_asesor nulo,
-- sin filtro, como el resto de la función). Se va cuando N llega a 0 o
-- cuando la purga borra los datos del envío. Va en la prioridad 5, con
-- las tareas de hoy («Para hoy»). crm.mi_dia es la de 20261026100003 con
-- esa rama y nada más. La firma no cambia (CREATE OR REPLACE no puede
-- añadir columnas), así que el id del envío viaja en cita_id; la
-- pantalla lo lee solo cuando tipo = 'gestion_envio_masivo'.
--
-- Funciones de pantalla: SECURITY INVOKER (manda la RLS: solo se ve y se
-- marca lo de la inmobiliaria de quien llama), GRANT a authenticated y en
-- la lista blanca de la prueba 27. Idempotente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1 · La gestión, en la fila
-- ---------------------------------------------------------------------
ALTER TABLE crm.envios_masivos_destinatarios
  ADD COLUMN IF NOT EXISTS gestionado_at  timestamptz,
  ADD COLUMN IF NOT EXISTS gestionado_por uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS gestion_nota   text;

ALTER TABLE crm.envios_masivos_destinatarios
  DROP CONSTRAINT IF EXISTS destinatarios_gestion_nota_corta,
  ADD CONSTRAINT destinatarios_gestion_nota_corta
    CHECK (gestion_nota IS NULL OR length(gestion_nota) <= 500),
  DROP CONSTRAINT IF EXISTS destinatarios_gestion_con_fecha,
  ADD CONSTRAINT destinatarios_gestion_con_fecha
    CHECK (gestionado_at IS NOT NULL OR (gestionado_por IS NULL AND gestion_nota IS NULL));

COMMENT ON COLUMN crm.envios_masivos_destinatarios.gestionado_at IS
  'Cuándo alguien del equipo dio por gestionada a mano a esta persona (la llamó, le escribió por otro lado). Solo con crm.marcar_gestion_manual.';
COMMENT ON COLUMN crm.envios_masivos_destinatarios.gestionado_por IS
  'Quién la marcó como gestionada.';
COMMENT ON COLUMN crm.envios_masivos_destinatarios.gestion_nota IS
  'Lo que pasó al gestionarla, hasta 500 caracteres. Habla de una deuda: la purga de los 90 días la borra.';

-- ---------------------------------------------------------------------
-- 2 · Quién necesita gestión manual
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.pendientes_gestion_envio(p_envio_masivo_id uuid)
RETURNS TABLE (
  destinatario_id       uuid,
  fila                  int,
  nombre                text,
  telefono_crudo        text,
  telefono_e164         text,
  contacto_id           uuid,
  datos                 jsonb,
  resultado             text,
  motivo                text,
  motivo_legible        text,
  detalle               text,
  gestionado            boolean,
  gestionado_at         timestamptz,
  gestionado_por        uuid,
  gestionado_por_nombre text,
  gestion_nota          text
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $pge$
  SELECT d.id,
         r.fila,
         d.nombre,
         d.telefono_crudo,
         d.telefono_e164,
         d.contacto_id,
         r.datos,
         r.resultado,
         x.motivo,
         CASE x.motivo
           WHEN 'sin_telefono'      THEN 'Sin número de WhatsApp en el archivo'
           WHEN 'telefono_invalido' THEN 'El número del archivo no es válido'
           WHEN 'faltan_datos'      THEN 'Le faltan datos para la plantilla'
           WHEN 'fallido'           THEN 'WhatsApp no lo entregó'
           WHEN 'sin_confirmar'     THEN 'La plataforma no confirmó el envío'
           WHEN 'sin_entregar'      THEN 'Se envió hace más de 24 horas y no le ha llegado'
         END,
         CASE x.motivo
           WHEN 'faltan_datos' THEN r.detalle
           WHEN 'fallido'      THEN concat_ws(' ', r.error, '(' || r.error_codigo || ')')
         END,
         d.gestionado_at IS NOT NULL,
         d.gestionado_at,
         d.gestionado_por,
         u.nombre_completo,
         d.gestion_nota
    FROM crm.resultados_envio_masivo(p_envio_masivo_id) r
    JOIN crm.envios_masivos_destinatarios d
      ON d.envio_masivo_id = p_envio_masivo_id AND d.fila = r.fila
    LEFT JOIN crm.envios e ON e.id = d.envio_id
    LEFT JOIN crm.v_asesores u ON u.id = d.gestionado_por
   CROSS JOIN LATERAL (
     SELECT CASE
       WHEN r.resultado = 'excluido'
        AND r.motivo IN ('sin_telefono', 'telefono_invalido', 'faltan_datos') THEN r.motivo
       WHEN r.resultado IN ('fallido', 'sin_confirmar') THEN r.resultado
       -- Enviado sin acuse de entrega en 24 horas. Si la plataforma no
       -- anotó cuándo salió, cuenta desde que el despachador lo tomó.
       WHEN r.resultado = 'enviado'
        AND COALESCE(r.enviado_at, e.tomado_at, e.created_at) < now() - interval '24 hours'
         THEN 'sin_entregar'
     END AS motivo
   ) x
   WHERE x.motivo IS NOT NULL
   ORDER BY r.fila;
$pge$;

COMMENT ON FUNCTION crm.pendientes_gestion_envio(uuid) IS
  'Las personas de un envío masivo que hay que gestionar a mano: sin número, número inválido o sin datos; '
  'fallidas en Meta; sin confirmar de la plataforma (10 min); y enviadas sin entregar en 24 h. No entran '
  'repetidas, bajas, frecuencia ni canceladas. Sale de crm.resultados_envio_masivo; dice si ya se gestionó.';

GRANT EXECUTE ON FUNCTION crm.pendientes_gestion_envio(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 3 · Marcar (y desmarcar) a alguien como gestionado
--
-- Cualquier admin o asesor de la inmobiliaria, no solo quien lanzó: el
-- trabajo se puede repartir. La RLS deja fuera la fila de otra
-- inmobiliaria, y para quien llama es como si no existiera.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.marcar_gestion_manual(p_destinatario_id uuid, p_nota text DEFAULT NULL)
RETURNS timestamptz
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = ''
AS $mgm$
DECLARE
  v_nota  text := NULLIF(btrim(p_nota), '');
  v_dest  record;
  v_ahora timestamptz := now();
BEGIN
  IF public.get_my_inmobiliaria() IS NULL
     OR COALESCE(public.get_my_role(), '') NOT IN ('admin', 'asesor') THEN
    RAISE EXCEPTION 'Solo un administrador o un asesor gestiona los envíos masivos'
      USING ERRCODE = '42501';
  END IF;

  IF length(v_nota) > 500 THEN
    RAISE EXCEPTION 'La nota es muy larga: son % caracteres y caben 500', length(v_nota)
      USING ERRCODE = '22023';
  END IF;

  PERFORM set_config('crm.envios_masivos', 'si', true);

  SELECT d.id, d.envio_masivo_id, m.lanzado_at INTO v_dest
    FROM crm.envios_masivos_destinatarios d
    JOIN crm.envios_masivos m ON m.id = d.envio_masivo_id
   WHERE d.id = p_destinatario_id
     FOR UPDATE OF d;
  IF v_dest.id IS NULL THEN
    RAISE EXCEPTION 'Esa fila no existe' USING ERRCODE = '22023';
  END IF;
  IF v_dest.lanzado_at IS NULL THEN
    RAISE EXCEPTION 'Ese envío todavía no se ha lanzado' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM crm.pendientes_gestion_envio(v_dest.envio_masivo_id) p
                  WHERE p.destinatario_id = p_destinatario_id) THEN
    RAISE EXCEPTION 'Esa persona no está en la gestión manual: el mensaje le llegó o sigue en camino'
      USING ERRCODE = '22023';
  END IF;

  -- Marcarla otra vez actualiza la nota: cuenta la última gestión.
  UPDATE crm.envios_masivos_destinatarios
     SET gestionado_at  = v_ahora,
         gestionado_por = (SELECT auth.uid()),
         gestion_nota   = v_nota
   WHERE id = p_destinatario_id;

  RETURN v_ahora;
END $mgm$;

COMMENT ON FUNCTION crm.marcar_gestion_manual(uuid, text) IS
  'Da por gestionada a mano a una persona de un envío masivo lanzado, con una nota opcional (500 caracteres). '
  'Solo si está en crm.pendientes_gestion_envio. Admin o asesor de la misma inmobiliaria.';

-- Deshacer un «gestionado» puesto por error: vuelve a pendiente, sin nota.
CREATE OR REPLACE FUNCTION crm.desmarcar_gestion_manual(p_destinatario_id uuid)
RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = ''
AS $dgm$
DECLARE
  v_id uuid;
BEGIN
  IF public.get_my_inmobiliaria() IS NULL
     OR COALESCE(public.get_my_role(), '') NOT IN ('admin', 'asesor') THEN
    RAISE EXCEPTION 'Solo un administrador o un asesor gestiona los envíos masivos'
      USING ERRCODE = '42501';
  END IF;

  PERFORM set_config('crm.envios_masivos', 'si', true);

  SELECT d.id INTO v_id
    FROM crm.envios_masivos_destinatarios d
   WHERE d.id = p_destinatario_id
     FOR UPDATE;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Esa fila no existe' USING ERRCODE = '22023';
  END IF;

  UPDATE crm.envios_masivos_destinatarios
     SET gestionado_at = NULL, gestionado_por = NULL, gestion_nota = NULL
   WHERE id = p_destinatario_id
     AND gestionado_at IS NOT NULL;
END $dgm$;

COMMENT ON FUNCTION crm.desmarcar_gestion_manual(uuid) IS
  'Deshace un «gestionado» de un envío masivo: la persona vuelve a pendiente y la nota se borra.';

GRANT EXECUTE ON FUNCTION crm.marcar_gestion_manual(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION crm.desmarcar_gestion_manual(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 4 · La purga de los 90 días también borra la nota
--
-- El cuerpo de 20261015190001 con gestion_nota en el SET. De sistema:
-- sigue cerrada (CREATE OR REPLACE conserva los permisos).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.purgar_envios_masivos(
  p_ahora timestamptz DEFAULT now(),
  p_dias  int DEFAULT 90)
RETURNS integer
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $pem$
DECLARE
  v_n int;
BEGIN
  PERFORM set_config('crm.envios_masivos', 'si', true);

  WITH viejos AS (
    UPDATE crm.envios_masivos m
       SET datos_borrados_at = p_ahora
     WHERE m.estado IN ('terminado', 'cancelado')
       AND m.datos_borrados_at IS NULL
       AND COALESCE(m.terminado_at, m.updated_at) < p_ahora - make_interval(days => p_dias)
    RETURNING m.id)
  UPDATE crm.envios_masivos_destinatarios d
     SET datos = NULL, valores = '{}'::jsonb, cuerpo = NULL, gestion_nota = NULL
    FROM viejos v
   WHERE d.envio_masivo_id = v.id;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  RETURN v_n;
END $pem$;

-- ---------------------------------------------------------------------
-- 5 · Mi día: el renglón de quien lanzó el envío
--
-- La versión de 20261026100003 con la rama 5-bis. Nada más cambia.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.mi_dia(p_limite integer DEFAULT 60, p_asesor uuid DEFAULT NULL)
RETURNS TABLE(prioridad smallint, tipo text, titulo text, detalle text, cuando timestamptz,
              contacto_id uuid, nombre text, telefono_e164 text, tarea_id uuid, cita_id uuid)
LANGUAGE sql STABLE SET search_path = ''
AS $mi_dia$
  WITH yo AS (
    -- El día de una admin trae todas las tareas del CRM; el de un asesor,
    -- las suyas y las que no tienen a nadie asignado. Se mira el rol de
    -- p_asesor (el dueño del día), no el de quien llama: una admin que mira
    -- el día de un asesor ve lo que ve él.
    SELECT EXISTS (
      SELECT 1 FROM crm.v_asesores u
       WHERE u.id = p_asesor AND u.rol = 'admin'
    ) AS es_admin
  ),
  todo (prioridad, tipo, titulo, detalle, cuando,
        contacto_id, nombre, telefono_e164, tarea_id, cita_id, asignado_a) AS (
    -- 1 · Escalamiento comercial: pidió una persona y nadie del equipo ha
    --     hecho nada desde entonces. Abrir la ficha no cuenta.
    SELECT 1::smallint, 'escalado'::text,
           'Pidió hablar con una persona'::text,
           COALESCE(c.nombre, c.telefono_e164, 'Sin nombre') || ' escribió y sigue esperando'::text,
           o.escalado_at, c.id, c.nombre, c.telefono_e164,
           NULL::uuid, NULL::uuid, NULL::uuid
    FROM crm.oportunidades o
    JOIN crm.contactos c ON c.id = o.contacto_id AND c.deleted_at IS NULL
    WHERE o.estado = 'abierta'
      AND o.embudo = 'comercial'
      AND o.escalado_at IS NOT NULL
      AND o.escalado_at > now() - crm.ventana_escalamiento()
      AND NOT crm.bot_atendido_desde(c.id, o.escalado_at)

    UNION ALL
    -- 1-bis · Envío fallido
    SELECT 1::smallint, 'envio_fallido',
           'No le llegó el mensaje',
           COALESCE(c.nombre, c.telefono_e164, 'Sin nombre') || ' · ' ||
             COALESCE(e.error, 'WhatsApp lo rechazó'),
           COALESCE(e.fallido_at, e.created_at), c.id, c.nombre, c.telefono_e164,
           NULL, NULL, NULL
    FROM crm.envios e
    JOIN crm.contactos c ON c.id = e.contacto_id AND c.deleted_at IS NULL
    WHERE e.estado = 'fallido'
      AND e.visto_at IS NULL
      AND COALESCE(e.fallido_at, e.created_at) > now() - interval '14 days'

    UNION ALL
    -- 2 · Visitas de hoy (hoy en Bogotá)
    SELECT 2::smallint, 'visita_hoy',
           'Visita ' || to_char(ci.hora_inicio, 'HH24:MI'),
           COALESCE(ci.cliente_nombre, c.nombre, c.telefono_e164, 'Sin nombre') || ' · ' ||
             COALESCE(i.titulo, 'inmueble'),
           (ci.fecha + ci.hora_inicio) AT TIME ZONE 'America/Bogota',
           a.contacto_id, c.nombre, c.telefono_e164, NULL, ci.id, NULL
    FROM public.citas ci
    LEFT JOIN public.inmuebles i ON i.id = ci.inmueble_id
    LEFT JOIN crm.actividades a ON a.cita_id = ci.id AND a.tipo = 'visita_agendada'
    LEFT JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE ci.estado = 'agendada' AND ci.fecha = crm.hoy()

    UNION ALL
    -- 3 · Tareas vencidas (antes de la medianoche de Bogotá)
    SELECT 3::smallint, 'tarea_vencida', t.titulo,
           COALESCE(c.nombre, c.telefono_e164, 'Sin contacto'),
           t.vence_at, t.contacto_id, c.nombre, c.telefono_e164, t.id, NULL, t.asignado_a
    FROM crm.tareas t
    LEFT JOIN crm.contactos c ON c.id = t.contacto_id
    WHERE t.completada_at IS NULL
      AND t.vence_at < crm.inicio_de_hoy()
      AND (p_asesor IS NULL OR t.asignado_a IS NULL OR t.asignado_a = p_asesor
           OR (SELECT es_admin FROM yo))

    UNION ALL
    -- 4 · Visitas que pasaron sin cerrar (antes de hoy en Bogotá)
    SELECT 4::smallint, 'visita_sin_cerrar',
           'Cerrar la visita del ' || to_char(ci.fecha, 'DD/MM'),
           COALESCE(ci.cliente_nombre, c.nombre, c.telefono_e164, 'Sin nombre'),
           (ci.fecha + ci.hora_fin) AT TIME ZONE 'America/Bogota',
           a.contacto_id, c.nombre, c.telefono_e164, NULL, ci.id, NULL
    FROM public.citas ci
    LEFT JOIN crm.actividades a ON a.cita_id = ci.id AND a.tipo = 'visita_agendada'
    LEFT JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE ci.estado = 'agendada'
      AND ci.fecha < crm.hoy()
      AND ci.fecha >= crm.hoy() - 14

    UNION ALL
    -- 5 · Tareas de hoy (entre las dos medianoches de Bogotá)
    SELECT 5::smallint, 'tarea_hoy', t.titulo,
           COALESCE(c.nombre, c.telefono_e164, 'Sin contacto'),
           t.vence_at, t.contacto_id, c.nombre, c.telefono_e164, t.id, NULL, t.asignado_a
    FROM crm.tareas t
    LEFT JOIN crm.contactos c ON c.id = t.contacto_id
    WHERE t.completada_at IS NULL
      AND t.vence_at >= crm.inicio_de_hoy()
      AND t.vence_at <  crm.inicio_de_hoy() + interval '1 day'
      AND (p_asesor IS NULL OR t.asignado_a IS NULL OR t.asignado_a = p_asesor
           OR (SELECT es_admin FROM yo))

    UNION ALL
    -- 5-bis · Envío masivo con gente para gestionar a mano: solo en el
    --     día de quien lo lanzó. Las personas salen de
    --     crm.pendientes_gestion_envio (sin número, número inválido o sin
    --     datos, falló, sin confirmar, sin entregar en 24 h). Se va cuando
    --     no queda ninguna o cuando la purga borra los datos del envío.
    --     El id del envío viaja en cita_id: la firma no cambia.
    SELECT 5::smallint, 'gestion_envio_masivo',
           'Envío "' || m.nombre || '": ' || g.n
             || CASE WHEN g.n = 1 THEN ' persona para gestionar a mano'
                     ELSE ' personas para gestionar a mano' END,
           g.detalle,
           m.lanzado_at, NULL, NULL, NULL, NULL, m.id, NULL
    FROM crm.envios_masivos m
    CROSS JOIN LATERAL (
      SELECT count(*) AS n,
             concat_ws(' · ',
               NULLIF(count(*) FILTER (WHERE p.motivo IN ('sin_telefono', 'telefono_invalido')), 0)
                 || ' sin número válido',
               NULLIF(count(*) FILTER (WHERE p.motivo = 'faltan_datos'), 0)
                 || ' con datos incompletos',
               NULLIF(count(*) FILTER (WHERE p.motivo = 'fallido'), 0)
                 || ' con error de WhatsApp',
               NULLIF(count(*) FILTER (WHERE p.motivo IN ('sin_confirmar', 'sin_entregar')), 0)
                 || ' sin confirmación de entrega') AS detalle
        FROM crm.pendientes_gestion_envio(m.id) p
       WHERE NOT p.gestionado
    ) g
    WHERE m.lanzado_at IS NOT NULL
      AND m.datos_borrados_at IS NULL
      AND (p_asesor IS NULL OR m.lanzado_por = p_asesor)
      AND g.n > 0

    UNION ALL
    -- 6 · Tareas de la plataforma de inventario
    SELECT 6::smallint, 'tarea_plataforma', pt.titulo,
           COALESCE(pt.evento_titulo, 'Plataforma de inventario'),
           pt.created_at, NULL, NULL, NULL, NULL, NULL, NULL
    FROM public.tareas pt
    WHERE pt.estado = 'pendiente'

    UNION ALL
    -- 7 · Bot callado comercial que nadie ha atendido y que no sale ya
    --     arriba como escalamiento reciente.
    SELECT 7::smallint, 'bot_callado',
           'El bot está callado y nadie ha llegado',
           COALESCE(c.nombre, c.telefono_e164, 'Sin nombre') || ' pidió hablar con una persona',
           c.bot_cambiado_at, c.id, c.nombre, c.telefono_e164,
           NULL, NULL, NULL
    FROM crm.contactos c
    WHERE c.deleted_at IS NULL
      AND NOT c.bot_activo
      AND c.bot_motivo = 'escalamiento'
      AND NOT crm.bot_atendido_desde(c.id, c.bot_cambiado_at)
      AND NOT EXISTS (
        SELECT 1 FROM crm.oportunidades o
         WHERE o.contacto_id = c.id
           AND o.estado = 'abierta'
           AND o.embudo = 'comercial'
           AND o.escalado_at > now() - crm.ventana_escalamiento()
           AND NOT crm.bot_atendido_desde(c.id, o.escalado_at))

    UNION ALL
    -- 8 · Estancadas: SOLO comerciales
    SELECT 8::smallint, 'estancada',
           'Lleva demasiado quieta',
           COALESCE(v.nombre, v.telefono_e164, 'Sin nombre') || ' · ' || v.etapa_etiqueta,
           v.ultima_actividad_at, v.contacto_id, v.nombre, v.telefono_e164,
           NULL, NULL, NULL
    FROM crm.v_oportunidades v
    WHERE v.estado = 'abierta'
      AND v.embudo = 'comercial'
      AND v.estancada
  )
  SELECT t.prioridad, t.tipo, t.titulo, t.detalle, t.cuando,
         t.contacto_id, t.nombre, t.telefono_e164, t.tarea_id, t.cita_id
    FROM todo t
    LEFT JOIN crm.oportunidades o
      ON o.contacto_id = t.contacto_id AND o.estado = 'abierta'
     AND o.embudo = 'comercial'
   WHERE p_asesor IS NULL
      OR o.asesor_id IS NULL
      OR o.asesor_id = p_asesor
      -- Una tarea asignada a quien mira (o cualquiera, si es la admin) se
      -- ve aunque la oportunidad del contacto la lleve otro.
      OR (t.tarea_id IS NOT NULL
          AND (t.asignado_a = p_asesor OR (SELECT es_admin FROM yo)))
   ORDER BY t.prioridad ASC, t.cuando ASC NULLS LAST
   LIMIT p_limite;
$mi_dia$;

