-- =====================================================================
-- Fase 4 — "Mi día": que la pantalla diga qué hacer, en orden.
--
-- EL CRM TIENE CINCO PANTALLAS Y NINGUNA DICE POR DÓNDE EMPEZAR
-- Contactos, tablero, coincidencias y la ficha son sitios donde
-- CONSULTAR. Un asesor que abre el CRM por la mañana no quiere consultar:
-- quiere saber qué hacer.
--
-- CASI TODO EL TRABAJO YA ES DERIVABLE, sin inventar tablas:
--   · pidió una persona y nadie ha llegado  → crm.oportunidades.escalado_at
--   · visitas de hoy                        → public.citas
--   · visitas que pasaron sin cerrar        → public.citas
--   · oportunidades estancadas              → crm.v_oportunidades
--   · tareas de la plataforma               → public.tareas (solo lectura)
--
-- Lo único que NO se puede derivar es "llamar a Juan el martes", porque
-- eso no es un hecho: es una decisión. Para eso, y solo para eso, hay
-- tabla nueva.
--
-- POR QUÉ NO SE ESCRIBE EN `public.tareas`
-- Existe y está viva (10 pendientes en producción), pero su CHECK de
-- `entidad_tipo` solo admite captacion/inventario/inmueble/general: la
-- tabla del otro repo nunca contempló contactos ni oportunidades.
-- Escribir ahí obligaría a cambiar su constraint, que es la línea que
-- este proyecto no cruza. Se LEE para que el asesor no tenga dos sitios
-- donde mirar, que es lo que esta pantalla viene a evitar.
-- =====================================================================

CREATE TABLE crm.tareas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  inmobiliaria_id uuid NOT NULL
    REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,
  -- Opcional: caben las que no son sobre nadie ("llamar a la aseguradora").
  contacto_id uuid REFERENCES crm.contactos(id) ON DELETE CASCADE,

  titulo text NOT NULL CHECK (btrim(titulo) <> ''),

  -- Una tarea sin fecha no es una tarea, es una intención. Y sin fecha no
  -- se puede ordenar un día.
  vence_at timestamptz NOT NULL,

  -- NOTA DE DEUDA CONOCIDA: apunta a public.usuarios, como las otras
  -- siete columnas de "quién". El día que el agente sea un actor del CRM
  -- habrá que retrofitear las ocho a la vez. Se deja así a propósito:
  -- una tarea ASIGNADA a un bot no tiene sentido todavía, y abstraer
  -- antes de saber si lo tendrá sería adivinar.
  asignado_a uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,
  creado_por uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,

  completada_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX tareas_del_dia
  ON crm.tareas (inmobiliaria_id, vence_at)
  WHERE completada_at IS NULL;

CREATE INDEX tareas_contacto ON crm.tareas (contacto_id)
  WHERE contacto_id IS NOT NULL;

ALTER TABLE crm.tareas ENABLE ROW LEVEL SECURITY;

-- Todas las de la inmobiliaria se ven: un equipo de cuatro necesita saber
-- qué tiene el otro encima, y esconderlo solo crea trabajo duplicado.
CREATE POLICY tareas_select ON crm.tareas
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());

CREATE POLICY tareas_insert ON crm.tareas
  FOR INSERT TO authenticated
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria());

CREATE POLICY tareas_update ON crm.tareas
  FOR UPDATE TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria())
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria());

CREATE POLICY tareas_delete ON crm.tareas
  FOR DELETE TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());

COMMENT ON TABLE crm.tareas IS
  'Lo que alguien DECIDIÓ hacer y cuándo. Lo que simplemente pasó se deriva y no se guarda aquí.';

-- ---------------------------------------------------------------------
-- El día
--
-- Un solo viaje a la base y una sola lista. Las fuentes son siete pero
-- el asesor no tiene por qué saberlo: lo que necesita es el siguiente
-- renglón, no un cuadro de mandos.
--
-- EL ORDEN ES LA FUNCIÓN. Sin prioridad esto sería otra bandeja más:
--   1  alguien espera a una persona AHORA — el reloj corre y se pierde
--   2  visita de hoy — tiene hora y no se puede aplazar
--   3  tarea vencida — se prometió y no se hizo
--   4  visita pasada sin cerrar — el dato se pierde cada día que pasa
--   5  tarea de hoy
--   6  tarea de la plataforma de inventario
--   7  estancada — importa, pero seguirá ahí mañana
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.mi_dia(p_limite int DEFAULT 60)
RETURNS TABLE (
  prioridad    smallint,
  tipo         text,
  titulo       text,
  detalle      text,
  cuando       timestamptz,
  contacto_id  uuid,
  nombre       text,
  telefono_e164 text,
  tarea_id     uuid,
  cita_id      uuid
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $dia$
  -- Las columnas se nombran aquí: un UNION las deja anónimas y el
  -- ORDER BY de abajo no tendría a qué agarrarse.
  WITH todo (prioridad, tipo, titulo, detalle, cuando,
             contacto_id, nombre, telefono_e164, tarea_id, cita_id) AS (
    -- 1 · Pidió una persona y nadie ha llegado. Lo único de esta lista
    --     que se pierde por no mirarlo a tiempo.
    SELECT 1::smallint, 'escalado'::text,
           'Pidió hablar con una persona'::text,
           c.nombre || ' escribió y sigue esperando'::text,
           o.escalado_at, c.id, c.nombre, c.telefono_e164,
           NULL::uuid, NULL::uuid
    FROM crm.oportunidades o
    JOIN crm.contactos c ON c.id = o.contacto_id AND c.deleted_at IS NULL
    WHERE o.estado = 'abierta'
      AND o.escalado_at IS NOT NULL
      AND o.escalado_at > now() - interval '48 hours'
      AND NOT EXISTS (SELECT 1 FROM crm.lecturas l
                       WHERE l.contacto_id = o.contacto_id
                         AND l.visto_hasta >= o.escalado_at)

    UNION ALL
    -- 2 · Visitas de hoy. Tienen hora: o se atienden o se pierden.
    SELECT 2::smallint, 'visita_hoy',
           'Visita ' || to_char(ci.hora_inicio, 'HH24:MI'),
           COALESCE(ci.cliente_nombre, 'Sin nombre') || ' · ' ||
             COALESCE(i.titulo, 'inmueble'),
           (ci.fecha + ci.hora_inicio) AT TIME ZONE 'America/Bogota',
           a.contacto_id, c.nombre, c.telefono_e164, NULL, ci.id
    FROM public.citas ci
    LEFT JOIN public.inmuebles i ON i.id = ci.inmueble_id
    LEFT JOIN crm.actividades a ON a.cita_id = ci.id AND a.tipo = 'visita_agendada'
    LEFT JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE ci.estado = 'agendada' AND ci.fecha = current_date

    UNION ALL
    -- 3 · Tareas vencidas. Se prometieron y no se hicieron.
    SELECT 3::smallint, 'tarea_vencida', t.titulo,
           COALESCE(c.nombre, 'Sin contacto'),
           t.vence_at, t.contacto_id, c.nombre, c.telefono_e164, t.id, NULL
    FROM crm.tareas t
    LEFT JOIN crm.contactos c ON c.id = t.contacto_id
    WHERE t.completada_at IS NULL AND t.vence_at < date_trunc('day', now())

    UNION ALL
    -- 4 · Visitas que pasaron sin cerrar. En producción llevaban 527
    --     citas y CERO marcadas: el dato se pierde cada día que pasa.
    SELECT 4::smallint, 'visita_sin_cerrar',
           'Cerrar la visita del ' || to_char(ci.fecha, 'DD/MM'),
           COALESCE(ci.cliente_nombre, 'Sin nombre'),
           (ci.fecha + ci.hora_fin) AT TIME ZONE 'America/Bogota',
           a.contacto_id, c.nombre, c.telefono_e164, NULL, ci.id
    FROM public.citas ci
    LEFT JOIN crm.actividades a ON a.cita_id = ci.id AND a.tipo = 'visita_agendada'
    LEFT JOIN crm.contactos c ON c.id = a.contacto_id
    WHERE ci.estado = 'agendada'
      AND ci.fecha < current_date
      AND ci.fecha >= current_date - 14   -- más atrás ya es historia

    UNION ALL
    -- 5 · Tareas de hoy.
    SELECT 5::smallint, 'tarea_hoy', t.titulo,
           COALESCE(c.nombre, 'Sin contacto'),
           t.vence_at, t.contacto_id, c.nombre, c.telefono_e164, t.id, NULL
    FROM crm.tareas t
    LEFT JOIN crm.contactos c ON c.id = t.contacto_id
    WHERE t.completada_at IS NULL
      AND t.vence_at >= date_trunc('day', now())
      AND t.vence_at <  date_trunc('day', now()) + interval '1 day'

    UNION ALL
    -- 6 · Tareas de la plataforma de inventario. Se LEEN, no se tocan:
    --     son de otro repo. Pero el asesor no debería tener dos sitios
    --     donde mirar, que es justo lo que esta pantalla viene a evitar.
    SELECT 6::smallint, 'tarea_plataforma', pt.titulo,
           COALESCE(pt.evento_titulo, 'Plataforma de inventario'),
           pt.created_at, NULL, NULL, NULL, NULL, NULL
    FROM public.tareas pt
    WHERE pt.estado = 'pendiente'

    UNION ALL
    -- 7 · Estancadas. Importan, pero seguirán ahí mañana: van al final a
    --     propósito, para que no tapen lo que sí se pierde hoy.
    SELECT 7::smallint, 'estancada',
           'Lleva demasiado quieta',
           v.nombre || ' · ' || v.etapa_etiqueta,
           v.ultima_actividad_at, v.contacto_id, v.nombre, v.telefono_e164,
           NULL, NULL
    FROM crm.v_oportunidades v
    WHERE v.estado = 'abierta' AND v.estancada
  )
  SELECT * FROM todo
  ORDER BY prioridad, cuando NULLS LAST
  LIMIT p_limite;
$dia$;

GRANT EXECUTE ON FUNCTION crm.mi_dia(int) TO authenticated;

-- ---------------------------------------------------------------------
-- Terminar una tarea
--
-- SECURITY INVOKER: la RLS decide. Se marca con fecha en vez de borrar
-- porque "qué se hizo ayer" es una pregunta que alguien va a hacer.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.completar_tarea(p_tarea_id uuid)
RETURNS void
LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $ct$
  UPDATE crm.tareas
     SET completada_at = now()
   WHERE id = p_tarea_id AND completada_at IS NULL;
$ct$;

GRANT EXECUTE ON FUNCTION crm.completar_tarea(uuid) TO authenticated;
