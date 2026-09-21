-- =====================================================================
-- Varios embudos, y varias líneas de WhatsApp.
--
-- LO QUE PIDIÓ SAMUEL (21 sep 2026)
-- Tres embudos en paralelo —comercial, administrativa y captación—, cada
-- uno con su propia línea de WhatsApp, y que la misma persona pueda estar
-- en más de uno a la vez. El bot solo atiende la comercial.
--
-- POR QUÉ ESTO NO ES UNA FUNCIONALIDAD MÁS
-- Es el rediseño que la auditoría del 18 sep marcó como REHACER, llegado
-- por la puerta del negocio en vez de por la de la deuda. Tres cosas lo
-- impedían y las tres se tocan aquí:
--   · crm.etapas no tenía dimensión de embudo, y su UNIQUE(orden) era
--     GLOBAL: no cabía un "paso 2" en comercial y otro en administrativa.
--   · oportunidades.etapa apuntaba a una tabla única de peldaños.
--   · oportunidades_una_abierta permitía UNA oportunidad abierta por
--     persona, punto. Un inquilino que además pregunta por otro
--     apartamento no cabía — el mismo bloqueo que impide que un
--     propietario tenga también una oportunidad de arriendo.
--
-- LA FORMA ELEGIDA, Y LA QUE SE DESCARTÓ
-- `etapas.codigo` SIGUE siendo la clave primaria, o sea que los códigos
-- son únicos entre todos los embudos. La alternativa era una clave
-- compuesta (embudo, codigo), que es más pura pero obliga a rehacer tres
-- llaves foráneas y a tocar las once funciones que hoy resuelven una
-- etapa por su código — sobre el pipeline que acaba de salir de un fallo
-- serio. La coherencia no se pierde: `oportunidades` lleva una foránea
-- COMPUESTA (embudo, etapa) que hace imposible poner una etapa de un
-- embudo en una oportunidad de otro.
--
-- Precio asumido: los peldaños de captación no pueden llamarse igual que
-- los de comercial. Se les dio nombre propio, que además dice mejor lo
-- que son: en captación no se "califica" a una persona, se verifica un
-- inmueble.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Los embudos
-- ---------------------------------------------------------------------
CREATE TABLE crm.embudos (
  codigo   text PRIMARY KEY,
  etiqueta text NOT NULL,
  orden    smallint NOT NULL UNIQUE,

  -- Si el agente comercial puede contestar en la línea de este embudo.
  -- Decisión de Samuel: solo en comercial. Lo administrativo es cartera,
  -- contratos y mantenimiento, donde una respuesta inventada cuesta
  -- dinero o confianza; y en captación se negocia con un propietario.
  bot_atiende boolean NOT NULL DEFAULT false,

  activo   boolean NOT NULL DEFAULT true
);

INSERT INTO crm.embudos (codigo, etiqueta, orden, bot_atiende) VALUES
  ('comercial',      'Comercial',      1, true),
  ('administrativa', 'Administrativa', 2, false),
  ('captacion',      'Captación',      3, false);

COMMENT ON TABLE crm.embudos IS
  'Los embudos que corren en paralelo. Cada uno tiene sus propios peldaños y su propia línea de WhatsApp.';

ALTER TABLE crm.embudos ENABLE ROW LEVEL SECURITY;

-- Catálogo global, como crm.etapas: se lee, no se escribe desde la app.
CREATE POLICY embudos_select ON crm.embudos
  FOR SELECT TO authenticated USING (true);

-- ---------------------------------------------------------------------
-- 2. Los peldaños, ahora con dueño
--
-- Las seis etapas que ya existen son del embudo comercial, y el DEFAULT
-- las deja donde están sin tocar una sola fila.
-- ---------------------------------------------------------------------
ALTER TABLE crm.etapas
  ADD COLUMN embudo text NOT NULL DEFAULT 'comercial'
    REFERENCES crm.embudos(codigo);

-- El orden era único en toda la tabla: con tres embudos, cada uno
-- necesita su propio 1, 2, 3.
ALTER TABLE crm.etapas DROP CONSTRAINT IF EXISTS etapas_orden_key;
ALTER TABLE crm.etapas ADD CONSTRAINT etapas_orden_por_embudo
  UNIQUE (embudo, orden);

-- Destino de la foránea compuesta de oportunidades. Redundante con la
-- clave primaria, y ahí está el punto: es lo que permite que Postgres
-- garantice que la etapa pertenece al embudo, sin cambiar la primaria.
ALTER TABLE crm.etapas ADD CONSTRAINT etapas_embudo_codigo
  UNIQUE (embudo, codigo);

COMMENT ON TABLE crm.etapas IS
  'Los peldaños de cada embudo. Ganada/Perdida no están aquí: son estado de la oportunidad. Los códigos son únicos entre embudos.';

-- ---------------------------------------------------------------------
-- 3. Captación, que ya existía fuera del CRM
--
-- `public.captacion_prospectos` lleva 83 prospectos con un embudo propio
-- de 8 estados. Se respeta su recorrido en vez de inventar otro, con dos
-- ajustes:
--   · `captado` y `descartado` NO son peldaños aquí: son `estado` de la
--     oportunidad (ganada / perdida), como en comercial.
--   · los nombres cambian donde chocaban con comercial, y de paso dicen
--     mejor lo que pasa: en captación se verifica un INMUEBLE, no se
--     califica a una persona.
-- ---------------------------------------------------------------------
INSERT INTO crm.etapas (codigo, orden, etiqueta, dias_pudricion, automatica, embudo) VALUES
  ('prospecto',            1, 'Prospecto',              3,  true,  'captacion'),
  ('inmueble_verificado',  2, 'Inmueble verificado',    5,  false, 'captacion'),
  ('por_aprobar',          3, 'Por aprobar',            3,  false, 'captacion'),
  ('propietario_contactado', 4, 'Propietario contactado', 5, false, 'captacion'),
  ('negociando',           5, 'Negociando',             10, false, 'captacion'),
  ('visita_captacion',     6, 'Visita al inmueble',     7,  false, 'captacion');

-- ---------------------------------------------------------------------
-- 4. Las oportunidades saben a qué embudo pertenecen
--
-- La foránea COMPUESTA es la que impide el error que de verdad importa:
-- una oportunidad de captación con una etapa de comercial. Sin ella, el
-- tablero enseñaría tarjetas en columnas que no existen.
-- ---------------------------------------------------------------------
ALTER TABLE crm.oportunidades
  ADD COLUMN embudo text NOT NULL DEFAULT 'comercial'
    REFERENCES crm.embudos(codigo);

ALTER TABLE crm.oportunidades
  ADD CONSTRAINT oportunidades_etapa_del_embudo
    FOREIGN KEY (embudo, etapa) REFERENCES crm.etapas(embudo, codigo);

COMMENT ON COLUMN crm.oportunidades.embudo IS
  'A qué embudo pertenece. Las 1.982 que existían son comerciales: es lo único que había.';

-- ---------------------------------------------------------------------
-- 5. UNA ABIERTA POR EMBUDO, no una en total
--
-- Es el cambio que Samuel pidió explícitamente, y el que desbloquea el
-- caso real: un inquilino con contrato vigente que pregunta por otro
-- apartamento. Antes había que cerrar lo uno para atender lo otro.
--
-- Sigue siendo parcial: permite varias históricas por embudo —alguien
-- arrienda hoy y compra en dos años— pero solo una viva a la vez en cada
-- uno.
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS crm.oportunidades_una_abierta;

CREATE UNIQUE INDEX oportunidades_una_abierta
  ON crm.oportunidades (inmobiliaria_id, contacto_id, embudo)
  WHERE estado = 'abierta';

-- El tablero ahora se pide por embudo, así que el índice lo lleva delante.
DROP INDEX IF EXISTS crm.oportunidades_tablero;

CREATE INDEX oportunidades_tablero
  ON crm.oportunidades (inmobiliaria_id, embudo, etapa, etapa_at DESC)
  WHERE estado = 'abierta';

-- ---------------------------------------------------------------------
-- 6. Las líneas de WhatsApp
--
-- POR QUÉ AQUÍ Y NO EN `public.inmobiliarias`
-- El 21 sep puse `wa_phone_number_id` en `inmobiliarias`, o sea UN número
-- por inmobiliaria. Estaba mal para este caso: son varios números por
-- inmobiliaria, cada uno alimentando un embudo distinto. Se corrige aquí,
-- que es donde vive el concepto de embudo; la columna de `public` se
-- retira en la migración hermana del otro repo. No se perdió nada: nunca
-- tuvo una fila.
--
-- Meta verificado: un WABA admite DOS números al empezar y VEINTE cuando
-- el negocio se verifica o se alcanza un límite de mensajería de 2.000.
-- Cada número lleva su propio nombre para mostrar, su propia calificación
-- de calidad y su propio límite — así que una línea castigada no arrastra
-- a las otras. Para tres líneas hay que verificar el negocio.
-- ---------------------------------------------------------------------
CREATE TABLE crm.lineas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  inmobiliaria_id uuid NOT NULL
    REFERENCES public.inmobiliarias(id) ON DELETE CASCADE,

  embudo text NOT NULL REFERENCES crm.embudos(codigo),

  -- Así llega identificado el número en cada webhook de Meta. No es el
  -- teléfono: es el id que Meta le asigna.
  wa_phone_number_id text,

  -- El número en E.164, solo para que un humano sepa cuál es cuál.
  telefono_e164 text,

  nombre text NOT NULL,
  activa boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Un phone_number_id identifica a UNA línea en todo el sistema: es la
-- llave por la que el webhook decide de quién es un mensaje entrante.
CREATE UNIQUE INDEX lineas_wa_phone_number_id
  ON crm.lineas (wa_phone_number_id) WHERE wa_phone_number_id IS NOT NULL;

-- Un embudo, una línea activa. Dos líneas activas para el mismo embudo
-- dejarían sin respuesta la pregunta "¿por cuál le escribo?".
CREATE UNIQUE INDEX lineas_una_activa_por_embudo
  ON crm.lineas (inmobiliaria_id, embudo) WHERE activa;

ALTER TABLE crm.lineas ENABLE ROW LEVEL SECURITY;

CREATE POLICY lineas_select ON crm.lineas
  FOR SELECT TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria());

-- Configurar una línea es conectar el canal de la inmobiliaria entera.
CREATE POLICY lineas_escribir ON crm.lineas
  FOR ALL TO authenticated
  USING (inmobiliaria_id = public.get_my_inmobiliaria()
         AND public.get_my_role() = 'admin')
  WITH CHECK (inmobiliaria_id = public.get_my_inmobiliaria()
              AND public.get_my_role() = 'admin');

CREATE TRIGGER lineas_updated_at
  BEFORE UPDATE ON crm.lineas
  FOR EACH ROW EXECUTE FUNCTION crm.tocar_updated_at();

COMMENT ON TABLE crm.lineas IS
  'Cada número de WhatsApp y el embudo que alimenta. El webhook de la plataforma resuelve por aquí de quién es un mensaje entrante.';

-- ---------------------------------------------------------------------
-- 7. El contrato con el webhook de la plataforma
--
-- El otro repo recibe el webhook de Meta y necesita traducir un
-- phone_number_id a "de qué inmobiliaria es, a qué embudo va, y si el bot
-- puede contestar ahí". Se resuelve en una sola llamada porque corre en
-- el camino de CADA mensaje entrante.
--
-- Pensada como API del agente igual que crm.bot_puede_responder: firma
-- estable, SECURITY DEFINER, documentada.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.linea_por_numero(p_wa_phone_number_id text)
RETURNS TABLE (
  inmobiliaria_id uuid,
  embudo          text,
  nombre          text,
  bot_atiende     boolean
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $lin$
  SELECT l.inmobiliaria_id, l.embudo, l.nombre, e.bot_atiende
    FROM crm.lineas l
    JOIN crm.embudos e ON e.codigo = l.embudo
   WHERE l.wa_phone_number_id = p_wa_phone_number_id
     AND l.activa
   LIMIT 1;
$lin$;

COMMENT ON FUNCTION crm.linea_por_numero(text) IS
  'Contrato con el webhook de Meta: de un phone_number_id devuelve la inmobiliaria, el embudo al que alimenta y si el bot puede contestar ahí.';

GRANT EXECUTE ON FUNCTION crm.linea_por_numero(text) TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- 8. Lo que sigue apuntando solo a comercial, y es deliberado
--
-- `abrir_oportunidad`, `recalcular_oportunidad`, `orden_por_evidencia`,
-- `cerrar_fantasmas` y el tablero siguen razonando sobre el embudo
-- comercial, porque sus reglas son comerciales: "escribió por WhatsApp
-- luego está contactado", "tuvo una visita luego avanzó". En
-- administrativa y en captación esos hechos significan otra cosa.
--
-- Nada de eso cambia de comportamiento con esta migración: las 1.982
-- oportunidades existentes son comerciales y el DEFAULT las deja donde
-- estaban. Lo que se añade es el sitio donde vivirán las otras.
-- ---------------------------------------------------------------------


-- =====================================================================
-- 9. Las funciones que razonan sobre "LA" oportunidad abierta
--
-- Hasta hoy, "la oportunidad abierta de un contacto" era una sola cosa y
-- once funciones lo daban por supuesto. Con tres embudos puede haber
-- tres, y un `SELECT ... INTO` sobre tres filas se queda con cualquiera.
--
-- Todas se acotan a 'comercial', y no es un parche: sus reglas SON
-- comerciales. "Escribió por WhatsApp luego está contactado", "lleva 30
-- días callado luego es un fantasma", "escaló luego quiere un asesor" —
-- ninguna de esas frases significa lo mismo en un trámite administrativo
-- o negociando con un propietario. Cada embudo traerá las suyas.
--
-- Efecto sobre el comportamiento de hoy: NINGUNO. Las 1.982 oportunidades
-- que existen son comerciales. Lo que cambia es que dejan de ser las
-- únicas posibles.
-- =====================================================================

-- Se TIRA la de un solo argumento antes de crear la de dos. Añadir un
-- parámetro con DEFAULT no reemplaza: SOBRECARGA, y entonces
-- `abrir_oportunidad(x)` se vuelve ambigua y Postgres la rechaza en
-- tiempo de ejecución. Es el mismo error que dejó el cron de
-- reactivar_bots cuatro días muerto.
DROP FUNCTION IF EXISTS crm.abrir_oportunidad(uuid);

CREATE OR REPLACE FUNCTION crm.abrir_oportunidad(
  p_contacto_id uuid,
  p_embudo      text DEFAULT 'comercial')
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $abrir$
DECLARE
  v_id  uuid;
  v_org uuid;
  v_ase uuid;
  v_primera text;
BEGIN
  -- Una abierta POR EMBUDO: un inquilino puede tener a la vez un caso
  -- administrativo y una búsqueda comercial.
  SELECT o.id INTO v_id
    FROM crm.oportunidades o
   WHERE o.contacto_id = p_contacto_id AND o.estado = 'abierta'
     AND o.embudo = p_embudo;
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  -- El primer peldaño lo dice el embudo, no una constante: comercial
  -- empieza en 'nuevo' y captación en 'prospecto'.
  SELECT e.codigo INTO v_primera FROM crm.etapas e
   WHERE e.embudo = p_embudo ORDER BY e.orden LIMIT 1;
  IF v_primera IS NULL THEN
    RETURN NULL;   -- embudo sin peldaños: no hay dónde ponerla.
  END IF;

  SELECT c.inmobiliaria_id, c.asesor_id INTO v_org, v_ase
    FROM crm.contactos c
   WHERE c.id = p_contacto_id AND c.deleted_at IS NULL;

  IF v_org IS NULL THEN
    RETURN NULL;   -- no existe o está borrado: nada que abrir.
  END IF;

  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, asesor_id, embudo, etapa)
  VALUES (v_org, p_contacto_id, v_ase, p_embudo, v_primera)
  -- Carrera entre dos mensajes simultáneos del mismo contacto: el índice
  -- único la resuelve y aquí simplemente no se duplica.
  ON CONFLICT (inmobiliaria_id, contacto_id, embudo) WHERE estado = 'abierta'
  DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT o.id INTO v_id FROM crm.oportunidades o
     WHERE o.contacto_id = p_contacto_id AND o.estado = 'abierta'
       AND o.embudo = p_embudo;
    RETURN v_id;
  END IF;

  INSERT INTO crm.transiciones
    (inmobiliaria_id, oportunidad_id, etapa_desde, etapa_hasta, estado_hasta, origen)
  VALUES (v_org, v_id, NULL, v_primera, 'abierta', 'sistema');

  RETURN v_id;
END $abrir$;

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
  -- SOLO COMERCIAL, y es deliberado: las reglas de esta función son
  -- comerciales ("escribió por WhatsApp luego está contactado", "tuvo una
  -- visita luego avanzó"). En administrativa y en captación esos mismos
  -- hechos significan otra cosa, y cada embudo tendrá la suya.
  SELECT * INTO v_op FROM crm.oportunidades o
   WHERE o.contacto_id = p_contacto_id AND o.estado = 'abierta'
     AND o.embudo = 'comercial';

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
     WHERE o.contacto_id = p_contacto_id AND o.estado = 'abierta'
       AND o.embudo = 'comercial';
    IF v_op.id IS NULL THEN RETURN false; END IF;
    v_movio := true;
  END IF;

  v_orden := crm.orden_por_evidencia(p_contacto_id);

  -- SOLO HACIA ADELANTE. Sin este GREATEST, alguien que ya visitó y
  -- luego escribe un mensaje retrocedería a "contactado" y el tablero
  -- dejaría de significar nada.
  SELECT e.codigo INTO v_nueva FROM crm.etapas e
   WHERE e.embudo = 'comercial' AND e.orden = GREATEST(
     v_orden,
     (SELECT e2.orden FROM crm.etapas e2
        WHERE e2.embudo = 'comercial' AND e2.codigo = v_op.etapa));

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

CREATE OR REPLACE FUNCTION crm.recalcular_pipeline()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $todo$
DECLARE
  v_contacto uuid;
  v_movidas  integer := 0;
BEGIN
  FOR v_contacto IN
    SELECT o.contacto_id FROM crm.oportunidades o
     WHERE o.estado = 'abierta' AND o.embudo = 'comercial'
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

CREATE OR REPLACE FUNCTION crm.cerrar_fantasmas(p_dias int DEFAULT 30)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $fantasmas$
DECLARE
  v_n integer := 0;
  v_op record;
BEGIN
  FOR v_op IN
    SELECT o.id, o.inmobiliaria_id, o.etapa, o.contacto_id
      FROM crm.oportunidades o
      JOIN crm.contactos c ON c.id = o.contacto_id
     WHERE o.estado = 'abierta'
       -- El silencio de 30 días es una regla COMERCIAL. Un caso
       -- administrativo callado no es un fantasma: es un trámite parado.
       AND o.embudo = 'comercial'
       AND c.deleted_at IS NULL
       -- Silencio de verdad: ningún hecho de ningún tipo. Una nota, una
       -- visita o un movimiento de etapa cuentan como vida.
       AND COALESCE(c.ultima_actividad_at, o.created_at)
             < now() - make_interval(days => p_dias)
       -- NO se pregunta por `etapa_at`, y es deliberado: el backfill del
       -- 14 sep puso ese reloj en `now()` para las 1.275 oportunidades a
       -- la vez, así que durante un mes habría protegido justo a los 670
       -- fantasmas que esta función viene a cerrar. Un reloj que una
       -- migración puede reiniciar en masa no sirve para decidir nada.
       --
       -- La pregunta de verdad es si una PERSONA ha tocado esto, y eso lo
       -- sabe el historial. Las transiciones del backfill y del avance
       -- automático llevan origen 'sistema'/'backfill' y no cuentan.
       AND NOT EXISTS (
         SELECT 1 FROM crm.transiciones t
          WHERE t.oportunidad_id = o.id
            AND t.origen = 'humano'
            AND t.ocurrido_at > now() - make_interval(days => p_dias)
       )
       -- Si el último que habló fue el cliente, NO se cierra: eso no es
       -- un fantasma, es alguien esperando respuesta nuestra. Cerrarlo
       -- como "no responde" sería echarle a él la culpa de nuestro
       -- silencio.
       AND NOT EXISTS (
         SELECT 1 FROM crm.actividades a
          WHERE a.contacto_id = o.contacto_id
            AND a.tipo = 'mensaje_entrante'
            AND a.ocurrido_at > COALESCE((
              SELECT max(a2.ocurrido_at) FROM crm.actividades a2
               WHERE a2.contacto_id = o.contacto_id
                 AND a2.tipo = 'mensaje_saliente'
            ), '-infinity'::timestamptz)
       )
       -- Y nadie con una visita por delante es un fantasma.
       AND NOT EXISTS (
         SELECT 1 FROM crm.actividades a
           JOIN public.citas ci ON ci.id = a.cita_id
          WHERE a.contacto_id = o.contacto_id
            AND ci.estado = 'agendada'
            AND ci.fecha >= current_date
       )
  LOOP
    BEGIN
      UPDATE crm.oportunidades
         SET estado         = 'perdida',
             motivo_perdida = 'no_responde',
             cerrada_at     = now(),
             -- NULL a propósito: es la huella de que esto lo cerró una
             -- regla y no una persona. Misma convención que
             -- citas.completada_por en el cierre masivo del 14 sep.
             cerrada_por    = NULL,
             updated_at     = now()
       WHERE id = v_op.id;

      INSERT INTO crm.transiciones
        (inmobiliaria_id, oportunidad_id, etapa_desde, etapa_hasta,
         estado_hasta, origen, motivo)
      VALUES (v_op.inmobiliaria_id, v_op.id, v_op.etapa, NULL,
              'perdida', 'sistema',
              format('sin respuesta en %s días', p_dias));

      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      NULL;   -- una oportunidad rota no puede detener a las otras 669
    END;
  END LOOP;

  RETURN v_n;
END $fantasmas$;

CREATE OR REPLACE FUNCTION crm.reabrir_oportunidad(p_oportunidad_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $reabrir$
DECLARE
  v_op crm.oportunidades%ROWTYPE;
BEGIN
  SELECT * INTO v_op FROM crm.oportunidades o WHERE o.id = p_oportunidad_id;
  IF v_op.id IS NULL THEN
    RAISE EXCEPTION 'No existe esa oportunidad, o no es tuya';
  END IF;
  IF v_op.estado = 'abierta' THEN
    RETURN;   -- ya estaba abierta; reabrir de más no hace daño
  END IF;

  -- La regla de "una abierta por persona" sigue mandando: si mientras
  -- tanto nació otra, esta se queda cerrada y se dice por qué.
  IF EXISTS (
    SELECT 1 FROM crm.oportunidades o
     WHERE o.contacto_id = v_op.contacto_id AND o.estado = 'abierta'
       AND o.embudo = v_op.embudo
  ) THEN
    RAISE EXCEPTION 'Esa persona ya tiene una oportunidad abierta. Usa esa.';
  END IF;

  UPDATE crm.oportunidades
     SET estado         = 'abierta',
         motivo_perdida = NULL,
         cerrada_at     = NULL,
         cerrada_por    = NULL,
         etapa_at       = now(),
         updated_at     = now()
   WHERE id = p_oportunidad_id;

  INSERT INTO crm.transiciones
    (inmobiliaria_id, oportunidad_id, etapa_desde, etapa_hasta,
     estado_hasta, origen, motivo, usuario_id)
  VALUES (v_op.inmobiliaria_id, p_oportunidad_id, NULL, v_op.etapa,
          'abierta', 'humano', 'reabierta', (SELECT auth.uid()));
END $reabrir$;

CREATE OR REPLACE FUNCTION crm.pipeline_al_llegar_requerimiento()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $pipe$
BEGIN
  -- SOLO recalcula si YA hay una oportunidad abierta. Nunca abre una.
  --
  -- La primera versión llamaba a recalcular_oportunidad() a secas, que
  -- abre la oportunidad si no existe — y eso resucitaba a los fantasmas:
  -- rehacer el backfill de requerimientos habría reabierto las 174
  -- oportunidades que el cron cierra cada noche.
  --
  -- La distinción que lo explica: `crm.actividades` registra lo que PASÓ;
  -- `crm.requerimientos` describe lo que alguien QUIERE. Solo lo primero
  -- abre un negocio. Que una persona a la que cerramos en julio tenga
  -- guardado qué buscaba no significa que haya vuelto: significa que
  -- sabemos a quién llamar cuando entre lo suyo, que es justo para lo que
  -- sirve la bandeja de reactivación.
  IF EXISTS (
    SELECT 1 FROM crm.oportunidades o
     WHERE o.contacto_id = NEW.contacto_id AND o.estado = 'abierta'
       AND o.embudo = 'comercial'
  ) THEN
    BEGIN
      PERFORM crm.recalcular_oportunidad(NEW.contacto_id);
    EXCEPTION WHEN OTHERS THEN
      NULL;   -- un requerimiento se guarda aunque el pipeline falle
    END;
  END IF;
  RETURN NULL;
END $pipe$;

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
       -- Escalar es pedir un asesor comercial: el bot solo atiende ahí.
       AND o.embudo = 'comercial'
       AND o.escalado_at IS DISTINCT FROM pr.escalado_at
    RETURNING o.contacto_id, pr.escalado_at
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
  RETURN v_n;
END $escal$;

CREATE OR REPLACE FUNCTION crm.reclamar_si_huerfana(
  p_contacto_id uuid,
  p_usuario     uuid)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = ''
AS $rec$
  UPDATE crm.oportunidades
     SET asesor_id = p_usuario, updated_at = now()
   WHERE contacto_id = p_contacto_id
     AND estado = 'abierta'
     -- Reclamar es hacerse cargo del negocio COMERCIAL. Los otros
     -- embudos tendrán su propia forma de repartir responsables.
     AND embudo = 'comercial'
     AND asesor_id IS NULL
     AND p_usuario IS NOT NULL;
$rec$;

CREATE OR REPLACE FUNCTION crm.asignar_lead(
  p_contacto_id uuid,
  p_asesor_id   uuid DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $asig$
DECLARE
  v_inmobiliaria uuid;
  v_antes uuid;
  v_nombre text;
BEGIN
  SELECT o.inmobiliaria_id, o.asesor_id INTO v_inmobiliaria, v_antes
    FROM crm.oportunidades o
   WHERE o.contacto_id = p_contacto_id AND o.estado = 'abierta'
     AND o.embudo = 'comercial';

  IF v_inmobiliaria IS NULL THEN RETURN false; END IF;
  IF v_antes IS NOT DISTINCT FROM p_asesor_id THEN RETURN true; END IF;

  UPDATE crm.oportunidades
     SET asesor_id = p_asesor_id, updated_at = now()
   WHERE contacto_id = p_contacto_id AND estado = 'abierta'
     AND embudo = 'comercial';

  SELECT u.nombre_completo INTO v_nombre
    FROM public.usuarios u WHERE u.id = p_asesor_id;

  INSERT INTO crm.actividades
    (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, creado_por)
  VALUES (v_inmobiliaria, 'sistema', 'humano', p_contacto_id,
          CASE WHEN p_asesor_id IS NULL
            THEN 'Este lead se quedó sin responsable.'
            ELSE 'Ahora es responsabilidad de ' || COALESCE(v_nombre, 'otro asesor') || '.'
          END,
          auth.uid());
  RETURN true;
END $asig$;

CREATE OR REPLACE FUNCTION crm.responsable_de(p_contacto_id uuid)
RETURNS TABLE (asesor_id uuid, nombre text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $resp$
  SELECT o.asesor_id, u.nombre_completo
    FROM crm.oportunidades o
    LEFT JOIN public.usuarios u ON u.id = o.asesor_id
   WHERE o.contacto_id = p_contacto_id AND o.estado = 'abierta'
     AND o.embudo = 'comercial'
   LIMIT 1;
$resp$;


CREATE OR REPLACE FUNCTION crm.mi_dia(
  p_limite int  DEFAULT 60,
  p_asesor uuid DEFAULT NULL)
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
      AND o.embudo = 'comercial'
      AND o.escalado_at IS NOT NULL
      AND o.escalado_at > now() - crm.ventana_escalamiento()
      AND NOT EXISTS (SELECT 1 FROM crm.lecturas l
                       WHERE l.contacto_id = o.contacto_id
                         AND l.visto_hasta >= o.escalado_at)

    UNION ALL
    -- 1-bis · Un mensaje que NO llegó. Va con la máxima prioridad porque
    --         es el único caso en que el asesor cree que hizo su trabajo y
    --         no lo hizo: el mensaje salió de la pantalla y se quedó en el
    --         camino. Nadie lo descubre solo.
    SELECT 1::smallint, 'envio_fallido',
           'No le llegó el mensaje',
           COALESCE(c.nombre, 'Sin nombre') || ' · ' ||
             COALESCE(e.error, 'WhatsApp lo rechazó'),
           COALESCE(e.fallido_at, e.created_at), c.id, c.nombre, c.telefono_e164,
           NULL, NULL
    FROM crm.envios e
    JOIN crm.contactos c ON c.id = e.contacto_id AND c.deleted_at IS NULL
    WHERE e.estado = 'fallido'
      AND e.visto_at IS NULL
      AND COALESCE(e.fallido_at, e.created_at) > now() - interval '14 days'

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
    -- 7 · El bot lleva días callado y nadie ha atendido a la persona.
    --     Esta es la red de seguridad de la caducidad: el bot vuelve solo
    --     a los 3 días, y esto está para que un humano llegue antes.
    --
    --     Las primeras 48 horas ya salen arriba como «escalado» mientras
    --     nadie abra la ficha, así que esas se excluyen: decir dos veces
    --     lo mismo en la misma pantalla es cómo se pierde la confianza en
    --     una lista de tareas.
    --
    --     La antigüedad no va en el título: `cuando` la pinta sola como
    --     «hace 2 días», igual que en el resto de la pantalla.
    SELECT 7::smallint, 'bot_callado',
           'El bot está callado y nadie ha llegado',
           COALESCE(c.nombre, 'Sin nombre') || ' pidió hablar con una persona',
           c.bot_cambiado_at, c.id, c.nombre, c.telefono_e164,
           NULL, NULL
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
           AND NOT EXISTS (SELECT 1 FROM crm.lecturas l
                            WHERE l.contacto_id = c.id
                              AND l.visto_hasta >= o.escalado_at))

    UNION ALL
    -- 8 · Estancadas. Importan, pero seguirán ahí mañana: van al final a
    --     propósito, para que no tapen lo que sí se pierde hoy.
    SELECT 8::smallint, 'estancada',
           'Lleva demasiado quieta',
           v.nombre || ' · ' || v.etapa_etiqueta,
           v.ultima_actividad_at, v.contacto_id, v.nombre, v.telefono_e164,
           NULL, NULL
    FROM crm.v_oportunidades v
    WHERE v.estado = 'abierta' AND v.estancada
  )
  -- MÍO + DE NADIE, nunca «solo lo mío».
  --
  -- Hoy 1.296 de 1.296 oportunidades abiertas no tienen responsable: un
  -- filtro estricto le dejaría el día vacío a todo el mundo. Y aunque se
  -- llenaran, lo huérfano tiene que verlo alguien o no lo ve nadie —
  -- que es justo el agujero que esta pantalla vino a tapar.
  --
  -- Lo que SÍ desaparece es lo que ya tiene otro dueño. Eso es lo único
  -- que hacía falta para que dos asesores no le escriban a la misma
  -- persona el mismo día.
  SELECT t.prioridad, t.tipo, t.titulo, t.detalle, t.cuando,
         t.contacto_id, t.nombre, t.telefono_e164, t.tarea_id, t.cita_id
    FROM todo t
    LEFT JOIN crm.oportunidades o
      ON o.contacto_id = t.contacto_id AND o.estado = 'abierta'
     AND o.embudo = 'comercial'
   WHERE p_asesor IS NULL
      OR t.contacto_id IS NULL        -- tareas de la plataforma, sin lead
      OR o.asesor_id IS NULL          -- huérfano: lo ve todo el mundo
      OR o.asesor_id = p_asesor
  ORDER BY t.prioridad, t.cuando NULLS LAST
  LIMIT p_limite;
$dia$;
