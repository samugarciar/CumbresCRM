-- =====================================================================
-- Fase 2-A — El pipeline comercial en la base.
--
-- POR QUÉ EL EMBUDO NO SE COPIA DE KOMMO
-- Las "etapas" de Kommo no son un embudo. `BELLO` y `MEDELLIN` son
-- municipios y `Escalado a asesor` es un estado operativo. Una etapa
-- tiene una pregunta de salida — "¿qué tiene que pasar para que esto
-- salga de aquí?" — y "Bello" no la tiene. Copiarlas daría un tablero
-- incapaz de medir conversión, que es para lo único que sirve un
-- embudo. Lo útil de esas etapas se rescata como ATRIBUTOS: `zona` y
-- `escalado_at`.
--
-- QUÉ SE DERIVA Y QUÉ SE DECIDE
-- Cuatro peldaños salen solos de hechos que ya tenemos (nuevo,
-- contactado, visita agendada, visita realizada). `calificado` y
-- `en_estudio` son juicio humano, y cerrar exige motivo. Un embudo que
-- se mueve solo hasta el final es un embudo que nadie mira.
--
-- EL AVANCE AUTOMÁTICO SOLO VA HACIA ADELANTE
-- Si alguien ya tuvo visita y escribe un mensaje, no vuelve a
-- "contactado". Sin esa regla el tablero se convierte en ruido.
--
-- NI UN TRIGGER NUEVO SOBRE `public`
-- Todo se cuelga de crm.actividades, que ya es nuestra, y de un trabajo
-- de pg_cron para lo que depende del paso del tiempo. El esquema del
-- otro repo no se toca.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Las etapas
--
-- Tabla de consulta, no "campos configurables": el tablero necesita
-- orden y etiqueta, y la pudrición se configura POR ETAPA (un negocio
-- recién contactado se pudre en días; uno en estudio, en semanas).
-- Cambiar esto es una migración de una línea, que es más barato que
-- construir una pantalla de administración para un equipo de cuatro.
--
-- Ganada y Perdida NO son etapas: son `estado` de la oportunidad. Si
-- fueran etapas, el índice único de "una abierta por persona" no podría
-- distinguir lo vivo de lo cerrado.
-- ---------------------------------------------------------------------
CREATE TABLE crm.etapas (
  codigo         text PRIMARY KEY,
  orden          smallint NOT NULL UNIQUE,
  etiqueta       text NOT NULL,
  -- Días sin actividad real tras los cuales la tarjeta se marca como
  -- estancada. NULL = no se pudre.
  dias_pudricion smallint,
  -- Si el peldaño lo pone el sistema o una persona. Documenta la
  -- intención; no se usa para restringir nada.
  automatica     boolean NOT NULL DEFAULT false
);

INSERT INTO crm.etapas (codigo, orden, etiqueta, dias_pudricion, automatica) VALUES
  ('nuevo',            1, 'Nuevo',            1,    true),
  ('contactado',       2, 'Contactado',       3,    true),
  ('calificado',       3, 'Calificado',       5,    false),
  ('visita_agendada',  4, 'Visita agendada',  7,    true),
  ('visita_realizada', 5, 'Visita realizada', 3,    true),
  ('en_estudio',       6, 'En estudio',       10,   false);

COMMENT ON TABLE crm.etapas IS
  'Los peldaños del embudo comercial. Ganada/Perdida no están aquí: son estado de la oportunidad.';

-- ---------------------------------------------------------------------
-- 2. Las oportunidades
-- ---------------------------------------------------------------------
CREATE TABLE crm.oportunidades (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  inmobiliaria_id uuid NOT NULL
    REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,
  contacto_id uuid NOT NULL
    REFERENCES crm.contactos(id) ON DELETE CASCADE,

  etapa text NOT NULL DEFAULT 'nuevo'
    REFERENCES crm.etapas(codigo),

  estado text NOT NULL DEFAULT 'abierta'
    CHECK (estado IN ('abierta', 'ganada', 'perdida')),

  -- ---------------------------------------------------------------
  -- Lo que en Kommo eran columnas y aquí son atributos
  -- ---------------------------------------------------------------
  -- 'BELLO' y 'MEDELLIN' eran etapas en Kommo. Son municipios: se
  -- filtran, no se recorren.
  zona text,

  -- Cuándo el bot pidió por primera vez que entrara una persona. No es
  -- un estado pegajoso: el bot sigue trabajando después (en producción,
  -- 185 de 264 conversaciones escaladas siguieron, 11,5 turnos de
  -- media). Es una PETICIÓN DE ATENCIÓN con fecha, y cruzada con
  -- crm.lecturas responde la pregunta que ningún CRM del mercado
  -- responde: "pidió un humano hace 40 minutos y nadie ha abierto esto".
  escalado_at timestamptz,

  asesor_id uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,

  -- ---------------------------------------------------------------
  -- Cierre
  -- ---------------------------------------------------------------
  -- Perder sin motivo es perder el dato: el motivo es la única materia
  -- prima para saber si el problema es el precio, la zona o nosotros.
  motivo_perdida text CHECK (motivo_perdida IN (
    'precio', 'zona', 'disponibilidad', 'requisitos',
    'no_responde', 'arrendo_con_otro', 'duplicado', 'otro'
  )),
  -- Qué inmueble se cerró. Además de medir, deja el vínculo
  -- persona↔inmueble que la bandeja de reactivación necesitará.
  inmueble_id uuid REFERENCES public.inmuebles(id) ON DELETE SET NULL,
  cerrada_at timestamptz,
  cerrada_por uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,

  -- ---------------------------------------------------------------
  -- Relojes
  -- ---------------------------------------------------------------
  -- Cuándo entró a la etapa ACTUAL. Es el reloj de la pudrición, y es
  -- distinto de created_at: una oportunidad puede llevar tres meses
  -- viva y dos días en su etapa.
  etapa_at   timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Cerrar exige decir por qué, y estar abierta exige no tenerlo.
  CONSTRAINT oportunidades_cierre_coherente CHECK (
    (estado = 'abierta'  AND cerrada_at IS NULL AND motivo_perdida IS NULL)
    OR (estado = 'ganada'  AND cerrada_at IS NOT NULL AND motivo_perdida IS NULL)
    OR (estado = 'perdida' AND cerrada_at IS NOT NULL AND motivo_perdida IS NOT NULL)
  )
);

-- LA REGLA DE NEGOCIO DE SAMUEL: una sola oportunidad VIVA por persona.
-- Parcial a propósito: permite varias históricas — alguien arrienda hoy
-- y compra en dos años — pero solo una abierta a la vez.
CREATE UNIQUE INDEX oportunidades_una_abierta
  ON crm.oportunidades (inmobiliaria_id, contacto_id)
  WHERE estado = 'abierta';

-- El tablero lee por etapa dentro de una inmobiliaria, ordenando por el
-- reloj de la etapa.
CREATE INDEX oportunidades_tablero
  ON crm.oportunidades (inmobiliaria_id, etapa, etapa_at DESC)
  WHERE estado = 'abierta';

CREATE INDEX oportunidades_contacto ON crm.oportunidades (contacto_id);

-- Para la alerta de "pidió un humano y nadie ha llegado".
CREATE INDEX oportunidades_escaladas
  ON crm.oportunidades (inmobiliaria_id, escalado_at DESC)
  WHERE estado = 'abierta' AND escalado_at IS NOT NULL;

ALTER TABLE crm.oportunidades ENABLE ROW LEVEL SECURITY;

CREATE POLICY oportunidades_select ON crm.oportunidades
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());

CREATE POLICY oportunidades_insert ON crm.oportunidades
  FOR INSERT TO authenticated
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria());

CREATE POLICY oportunidades_update ON crm.oportunidades
  FOR UPDATE TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria())
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria());

CREATE POLICY oportunidades_delete ON crm.oportunidades
  FOR DELETE TO authenticated
  USING (
    inmobiliaria_id = public.get_my_inmobiliaria()
    AND public.get_my_role() = 'admin'
  );

COMMENT ON TABLE crm.oportunidades IS
  'El negocio en curso con una persona. Una abierta por persona; las cerradas se acumulan como historia.';

-- ---------------------------------------------------------------------
-- 3. Las transiciones
--
-- El historial que hoy NO EXISTE en ninguna parte. Sin esto no hay
-- conversión medible: se sabría dónde está cada cosa, pero no cuántas
-- pasaron de agendar a visitar, que es la pregunta del negocio.
--
-- El embudo empieza el día que empecemos a registrarlo; por eso esta
-- tabla nace con la fase y no "cuando haga falta".
-- ---------------------------------------------------------------------
CREATE TABLE crm.transiciones (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

  inmobiliaria_id uuid NOT NULL
    REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,
  oportunidad_id uuid NOT NULL
    REFERENCES crm.oportunidades(id) ON DELETE CASCADE,

  -- NULL en la primera: no venía de ninguna parte.
  etapa_desde text REFERENCES crm.etapas(codigo),
  etapa_hasta text REFERENCES crm.etapas(codigo),
  estado_hasta text,

  -- Quién la movió: una persona, una regla del sistema, o el backfill.
  origen text NOT NULL DEFAULT 'sistema'
    CHECK (origen IN ('humano', 'sistema', 'backfill')),
  motivo text,

  usuario_id uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,
  ocurrido_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX transiciones_oportunidad
  ON crm.transiciones (oportunidad_id, ocurrido_at DESC);

CREATE INDEX transiciones_embudo
  ON crm.transiciones (inmobiliaria_id, etapa_hasta, ocurrido_at);

ALTER TABLE crm.transiciones ENABLE ROW LEVEL SECURITY;

CREATE POLICY transiciones_select ON crm.transiciones
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());

-- Quien puede mover una tarjeta puede escribir la línea de historia que
-- corresponde: mover_etapa() y cerrar_oportunidad() son SECURITY INVOKER
-- a propósito, para que sea la RLS —y no un IF dentro de una función—
-- quien decida si esta persona puede tocar esta oportunidad.
CREATE POLICY transiciones_insert ON crm.transiciones
  FOR INSERT TO authenticated
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria());

-- Y NO HAY política de UPDATE ni de DELETE. Es deliberado: la historia
-- se añade, no se corrige. Un embudo cuyo pasado se puede reescribir no
-- sirve para medir nada.

COMMENT ON TABLE crm.transiciones IS
  'Cada movimiento de etapa, con quién y por qué. Es la materia prima de la conversión.';

-- ---------------------------------------------------------------------
-- 4. Abrir la oportunidad de un contacto
--
-- Idempotente: si ya hay una abierta, la devuelve. Llamarla de más no
-- hace daño, que es lo que permite colgarla de un trigger.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.abrir_oportunidad(p_contacto_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $abrir$
DECLARE
  v_id  uuid;
  v_org uuid;
  v_ase uuid;
BEGIN
  SELECT o.id INTO v_id
    FROM crm.oportunidades o
   WHERE o.contacto_id = p_contacto_id AND o.estado = 'abierta';
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  SELECT c.inmobiliaria_id, c.asesor_id INTO v_org, v_ase
    FROM crm.contactos c
   WHERE c.id = p_contacto_id AND c.deleted_at IS NULL;

  IF v_org IS NULL THEN
    RETURN NULL;   -- no existe o está borrado: nada que abrir.
  END IF;

  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, asesor_id)
  VALUES (v_org, p_contacto_id, v_ase)
  -- Carrera entre dos mensajes simultáneos del mismo contacto: el índice
  -- único la resuelve y aquí simplemente no se duplica.
  ON CONFLICT (inmobiliaria_id, contacto_id) WHERE estado = 'abierta'
  DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT o.id INTO v_id FROM crm.oportunidades o
     WHERE o.contacto_id = p_contacto_id AND o.estado = 'abierta';
    RETURN v_id;
  END IF;

  INSERT INTO crm.transiciones
    (inmobiliaria_id, oportunidad_id, etapa_desde, etapa_hasta, estado_hasta, origen)
  VALUES (v_org, v_id, NULL, 'nuevo', 'abierta', 'sistema');

  RETURN v_id;
END $abrir$;

-- ---------------------------------------------------------------------
-- 5. La etapa que merece un contacto según los hechos
--
-- Devuelve el orden del peldaño más alto que los hechos SOSTIENEN. No
-- decide nada por sí sola: quien la usa aplica el "solo hacia adelante".
--
-- `calificado` (3) y `en_estudio` (6) nunca salen de aquí: son juicio.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.orden_por_evidencia(p_contacto_id uuid)
RETURNS smallint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $evidencia$
  SELECT GREATEST(
    1::smallint,   -- nuevo: existir ya es el primer peldaño
    COALESCE(MAX(CASE
      WHEN a.tipo = 'visita_realizada' THEN 5
      WHEN a.tipo = 'visita_agendada'  THEN 4
      WHEN a.tipo IN ('mensaje_entrante', 'mensaje_saliente',
                      'llamada', 'solicitud_apertura') THEN 2
      ELSE 1
    END), 1)::smallint,
    -- La visita PRESUNTA: estaba confirmada, la fecha ya pasó y nadie la
    -- canceló. En cuatro meses de producción no se ha marcado ni una
    -- sola cita como completada (527 citas, 0 completadas), así que sin
    -- esta presunción el peldaño más importante del embudo estaría
    -- siempre vacío. Se presume, pero queda registrado como presunto:
    -- ver crm.v_oportunidades.visita_realizada_origen.
    COALESCE((
      SELECT 5::smallint
        FROM crm.actividades a2
        JOIN public.citas ci ON ci.id = a2.cita_id
       WHERE a2.contacto_id = p_contacto_id
         AND a2.cita_id IS NOT NULL
         AND ci.confirmada_at IS NOT NULL
         AND ci.estado = 'agendada'
         AND ci.fecha < current_date
       LIMIT 1
    ), 1)::smallint
  )
  FROM crm.actividades a
  WHERE a.contacto_id = p_contacto_id;
$evidencia$;

-- ---------------------------------------------------------------------
-- 6. Recalcular una oportunidad
--
-- Idempotente y solo hacia adelante. Devuelve true si movió algo.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.recalcular_oportunidad(p_contacto_id uuid)
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
-- 7. El trigger — sobre NUESTRA tabla
--
-- Se cuelga de crm.actividades, no de public. Con el patrón a prueba de
-- fallos del resto del CRM: si el pipeline se rompe, la actividad se
-- guarda igual. Perder un mensaje del cliente por un error calculando
-- una etapa sería el peor intercambio posible.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.pipeline_al_llegar_actividad()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $pipe$
BEGIN
  IF NEW.contacto_id IS NOT NULL THEN
    BEGIN
      PERFORM crm.recalcular_oportunidad(NEW.contacto_id);
    EXCEPTION WHEN OTHERS THEN
      BEGIN
        PERFORM crm.registrar_fallo(
          NEW.inmobiliaria_id, 'pipeline', 'crm.actividades', NEW.id::text,
          jsonb_build_object('contacto_id', NEW.contacto_id), SQLERRM);
      EXCEPTION WHEN OTHERS THEN
        NULL;   -- ni siquiera el registro del fallo puede tumbar la inserción
      END;
    END;
  END IF;
  RETURN NULL;
END $pipe$;

CREATE TRIGGER crm_pipeline_actividad
  AFTER INSERT ON crm.actividades
  FOR EACH ROW EXECUTE FUNCTION crm.pipeline_al_llegar_actividad();

-- ---------------------------------------------------------------------
-- 8. Mover a mano
--
-- SECURITY INVOKER: la RLS decide si esta persona puede tocar esta
-- oportunidad. Permite ir hacia atrás — un humano corrigiendo un error
-- del sistema es exactamente el caso de uso, y por eso existe el
-- historial.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.mover_etapa(
  p_oportunidad_id uuid,
  p_etapa          text,
  p_motivo         text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $mover$
DECLARE
  v_op crm.oportunidades%ROWTYPE;
BEGIN
  SELECT * INTO v_op FROM crm.oportunidades o WHERE o.id = p_oportunidad_id;
  IF v_op.id IS NULL THEN
    RAISE EXCEPTION 'No existe esa oportunidad, o no es tuya';
  END IF;
  IF v_op.estado <> 'abierta' THEN
    RAISE EXCEPTION 'La oportunidad ya está cerrada como %', v_op.estado;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM crm.etapas e WHERE e.codigo = p_etapa) THEN
    RAISE EXCEPTION 'Etapa desconocida: %', p_etapa;
  END IF;
  IF p_etapa = v_op.etapa THEN
    RETURN;   -- soltar la tarjeta en su propia columna no es un movimiento
  END IF;

  UPDATE crm.oportunidades
     SET etapa = p_etapa, etapa_at = now(), updated_at = now()
   WHERE id = p_oportunidad_id;

  INSERT INTO crm.transiciones
    (inmobiliaria_id, oportunidad_id, etapa_desde, etapa_hasta,
     estado_hasta, origen, motivo, usuario_id)
  VALUES (v_op.inmobiliaria_id, p_oportunidad_id, v_op.etapa, p_etapa,
          'abierta', 'humano', p_motivo, (SELECT auth.uid()));
END $mover$;

-- ---------------------------------------------------------------------
-- 9. Cerrar
--
-- Ganada exige decir QUÉ inmueble: además de medir, deja el vínculo
-- persona↔inmueble. Perdida exige MOTIVO, que es el único dato que
-- explica por qué el embudo se estrecha donde se estrecha.
--
-- Al cerrar NO se abre otra: la siguiente nace sola con la próxima
-- actividad, y así una persona que vuelve a escribir en marzo no
-- contamina las cifras de septiembre.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.cerrar_oportunidad(
  p_oportunidad_id uuid,
  p_estado         text,
  p_motivo_perdida text DEFAULT NULL,
  p_inmueble_id    uuid DEFAULT NULL,
  p_nota           text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $cerrar$
DECLARE
  v_op crm.oportunidades%ROWTYPE;
BEGIN
  SELECT * INTO v_op FROM crm.oportunidades o WHERE o.id = p_oportunidad_id;
  IF v_op.id IS NULL THEN
    RAISE EXCEPTION 'No existe esa oportunidad, o no es tuya';
  END IF;
  IF v_op.estado <> 'abierta' THEN
    RAISE EXCEPTION 'Ya estaba cerrada como %', v_op.estado;
  END IF;
  IF p_estado NOT IN ('ganada', 'perdida') THEN
    RAISE EXCEPTION 'Cerrar es ganada o perdida, no %', p_estado;
  END IF;
  IF p_estado = 'perdida' AND p_motivo_perdida IS NULL THEN
    RAISE EXCEPTION 'Perder sin motivo es perder el dato: hace falta el motivo';
  END IF;

  UPDATE crm.oportunidades
     SET estado         = p_estado,
         motivo_perdida = CASE WHEN p_estado = 'perdida' THEN p_motivo_perdida END,
         inmueble_id    = COALESCE(p_inmueble_id, inmueble_id),
         cerrada_at     = now(),
         cerrada_por    = (SELECT auth.uid()),
         updated_at     = now()
   WHERE id = p_oportunidad_id;

  INSERT INTO crm.transiciones
    (inmobiliaria_id, oportunidad_id, etapa_desde, etapa_hasta,
     estado_hasta, origen, motivo, usuario_id)
  VALUES (v_op.inmobiliaria_id, p_oportunidad_id, v_op.etapa, NULL,
          p_estado, 'humano',
          COALESCE(p_nota, p_motivo_perdida), (SELECT auth.uid()));
END $cerrar$;

-- ---------------------------------------------------------------------
-- 10. La vista del tablero
--
-- security_invoker: la RLS de crm.oportunidades manda.
-- ---------------------------------------------------------------------
CREATE VIEW crm.v_oportunidades WITH (security_invoker = true) AS
  SELECT
    o.id,
    o.inmobiliaria_id,
    o.contacto_id,
    o.etapa,
    e.etiqueta       AS etapa_etiqueta,
    e.orden          AS etapa_orden,
    o.estado,
    o.zona,
    o.escalado_at,
    o.asesor_id,
    o.motivo_perdida,
    o.inmueble_id,
    o.cerrada_at,
    o.etapa_at,
    o.created_at,

    -- El nombre ya viene elegido: crm.mejor_nombre() lo mantiene al día
    -- en la propia tabla cada vez que llega uno mejor.
    c.nombre,
    c.telefono_e164,
    c.ultima_actividad_at,

    -- Estancada: días en la etapa por encima de lo que esa etapa
    -- tolera. El reloj se reinicia con actividad REAL, no con el
    -- movimiento de la tarjeta, que es la trampa clásica.
    (o.estado = 'abierta'
     AND e.dias_pudricion IS NOT NULL
     AND COALESCE(c.ultima_actividad_at, o.etapa_at)
           < now() - make_interval(days => e.dias_pudricion)) AS estancada,

    -- De dónde sale que la visita se realizó. TRES valores, no dos, y la
    -- diferencia importa para no mentir en un informe de conversión:
    --
    --   confirmada  una persona la marcó. completada_por dice quién.
    --   retroactiva se marcó en bloque el 14 sep 2026 para llenar el
    --               embudo: 488 citas que llevaban meses abiertas sin
    --               que nadie las cerrara. completada_por quedó en NULL
    --               a propósito, y ese NULL es la única huella de que
    --               nadie vio ocurrir esa visita.
    --   presunta    no hay cita marcada: se deduce de que estaba
    --               confirmada, la fecha pasó y no se canceló.
    --
    -- Solo la primera es un hecho observado. Las otras dos son
    -- reconstrucciones, y quien saque porcentajes de conversión tiene
    -- que poder separarlas.
    CASE
      WHEN o.etapa <> 'visita_realizada' THEN NULL
      WHEN EXISTS (SELECT 1 FROM crm.actividades a
                     JOIN public.citas ci ON ci.id = a.cita_id
                    WHERE a.contacto_id = o.contacto_id
                      AND a.tipo = 'visita_realizada'
                      AND ci.completada_por IS NOT NULL) THEN 'confirmada'
      WHEN EXISTS (SELECT 1 FROM crm.actividades a
                    WHERE a.contacto_id = o.contacto_id
                      AND a.tipo = 'visita_realizada') THEN 'retroactiva'
      ELSE 'presunta'
    END AS visita_realizada_origen
  FROM crm.oportunidades o
  JOIN crm.etapas e    ON e.codigo = o.etapa
  JOIN crm.contactos c ON c.id = o.contacto_id
  WHERE c.deleted_at IS NULL;

COMMENT ON VIEW crm.v_oportunidades IS
  'El tablero: cada oportunidad con su etapa, su nombre, si está estancada y si la visita es presunta.';

-- ---------------------------------------------------------------------
-- 10-bis. El escalamiento, de una sola pasada
--
-- POR QUÉ ESTO NO ESTÁ EN EL TRIGGER
-- El puente desde public.agente_comercial_uso hasta un contacto cuesta
-- 614 ms medidos en producción con EXPLAIN ANALYZE, porque hay que
-- escanear entera una tabla que no es nuestra (sin índice por
-- conversacion_id) y otra por una comparación de texto que no puede
-- usar la clave primaria.
--
-- Medido, las tres cifras que justifican la separación:
--   614 ms   por contacto, dentro del trigger de cada mensaje  ❌
--   555 ms   para los 1.263 de una pasada, en segundo plano    ✅
--   0,119 ms lo que quedó en el trigger (solo la etapa)        ✅
--
-- El gasto total de CPU es parecido; lo que cambia es que deja de
-- colgar del camino por el que entra cada WhatsApp. Si algún día 555 ms
-- cada cinco minutos llegara a pesar, el arreglo es una marca de agua
-- sobre agente_comercial_uso.created_at, no optimizar esta consulta.
--
-- No se añade el índice que faltaría: agente_comercial_uso es del otro
-- repo, y tocar su esquema desde aquí sería cruzar la línea que separa
-- los dos proyectos.
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
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_n FROM tocadas;
  RETURN v_n;
END $escal$;

-- ---------------------------------------------------------------------
-- 11. Poner al día todo el pipeline
--
-- Dos cosas dependen del PASO DEL TIEMPO y no de que ocurra un hecho:
-- la visita presunta (la fecha de la cita simplemente pasa) y el
-- escalamiento (se escribe en public, donde no ponemos triggers).
-- Por eso hay un trabajo periódico además del trigger.
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
      IF crm.recalcular_oportunidad(v_contacto) THEN
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

-- ---------------------------------------------------------------------
-- 12. El backfill
--
-- Abre una oportunidad por cada contacto vivo y la coloca donde los
-- hechos dicen. Las transiciones que crea van marcadas como 'backfill'
-- para que nadie confunda historia reconstruida con historia observada:
-- todas llevan la fecha de hoy, porque la fecha real del movimiento no
-- existe en ninguna parte.
--
-- La ZONA se recupera de las "etapas" de Kommo, que es lo que de verdad
-- eran: en producción, 451 conversaciones BELLO y 180 MEDELLIN.
--
-- Idempotente: correrlo dos veces no duplica nada.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.backfill_pipeline()
RETURNS TABLE (oportunidades_creadas integer, con_zona integer, escaladas integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $backfill$
DECLARE
  v_creadas integer := 0;
  v_contacto uuid;
BEGIN
  FOR v_contacto IN
    SELECT c.id FROM crm.contactos c
     WHERE c.deleted_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM crm.oportunidades o
                        WHERE o.contacto_id = c.id AND o.estado = 'abierta')
  LOOP
    IF crm.abrir_oportunidad(v_contacto) IS NOT NULL THEN
      v_creadas := v_creadas + 1;
    END IF;
  END LOOP;

  -- Colocar cada una donde los hechos la sostienen.
  PERFORM crm.recalcular_pipeline();

  -- La zona, desde el vocabulario de Kommo. Se toma la MÁS RECIENTE:
  -- si alguien preguntó por Bello y luego por Medellín, manda la última.
  WITH conv_contacto AS (
    SELECT DISTINCT m.conversacion_id, a.contacto_id
      FROM public.agente_comercial_mensajes m
      JOIN crm.actividades a
        ON a.metadata->>'origen_tabla' = 'agente_comercial_mensajes'
       AND a.metadata->>'origen_id' = m.id::text
     WHERE a.contacto_id IS NOT NULL
  ), zona AS (
    SELECT DISTINCT ON (cc.contacto_id)
           cc.contacto_id,
           initcap(lower(u.etapa)) AS zona
      FROM public.agente_comercial_uso u
      JOIN conv_contacto cc USING (conversacion_id)
     WHERE u.etapa IN ('BELLO', 'MEDELLIN')
     ORDER BY cc.contacto_id, u.created_at DESC
  )
  UPDATE crm.oportunidades o
     SET zona = z.zona, updated_at = now()
    FROM zona z
   WHERE o.contacto_id = z.contacto_id
     AND o.estado = 'abierta'
     AND o.zona IS DISTINCT FROM z.zona;

  RETURN QUERY
    SELECT v_creadas,
           (SELECT count(*)::integer FROM crm.oportunidades
             WHERE estado = 'abierta' AND zona IS NOT NULL),
           (SELECT count(*)::integer FROM crm.oportunidades
             WHERE estado = 'abierta' AND escalado_at IS NOT NULL);
END $backfill$;

-- ---------------------------------------------------------------------
-- 13. Permisos
-- ---------------------------------------------------------------------
GRANT SELECT ON crm.etapas, crm.v_oportunidades TO authenticated;

GRANT EXECUTE ON FUNCTION crm.mover_etapa(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION crm.cerrar_oportunidad(uuid, text, text, uuid, text) TO authenticated;

-- Las de mantenimiento NO se exponen: las llama el trigger o pg_cron,
-- ambos con permisos propios. Un asesor no tiene por qué poder
-- recalcular el pipeline de toda la inmobiliaria.
REVOKE ALL ON FUNCTION crm.recalcular_pipeline()      FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION crm.backfill_pipeline()        FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION crm.abrir_oportunidad(uuid)    FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION crm.recalcular_oportunidad(uuid) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION crm.orden_por_evidencia(uuid)  FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION crm.sincronizar_escalamientos() FROM public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 14. El trabajo periódico
--
-- Cada cinco minutos: la alerta que esto alimenta —"el bot pidió un
-- humano y nadie ha llegado"— se mide en minutos, así que diez sería
-- demasiado grueso. La pasada completa cuesta bastante menos de un
-- segundo, de modo que cinco minutos no le pesa a nadie.
-- ---------------------------------------------------------------------
DO $cron$
BEGIN
  PERFORM cron.schedule(
    'crm_recalcular_pipeline', '*/5 * * * *',
    $trabajo$SELECT crm.recalcular_pipeline();$trabajo$);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron no disponible; habrá que agendar crm.recalcular_pipeline() a mano: %', SQLERRM;
END $cron$;
