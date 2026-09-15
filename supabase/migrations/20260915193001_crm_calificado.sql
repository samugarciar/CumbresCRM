-- =====================================================================
-- "Calificado" deja de estar vacía.
--
-- EL PROBLEMA, VISTO EN EL TABLERO
-- Contactado 852 · Calificado 0 · Visita agendada 12 · Visita realizada 419.
-- Los leads saltaban de Contactado a Visita agendada, o a perdidos.
--
-- Una etapa por la que nadie pasa es una etapa rota, y ésta no lo estaba
-- por sobrar: **nunca definimos cómo se entra**. Se dejó manual, y una
-- etapa manual sin una razón clara para pulsar el botón se queda vacía
-- para siempre. La pregunta de salida sí estaba clara —se agenda una
-- visita—; la de entrada no existía.
--
-- Y "Contactado" no era un grupo, eran tres:
--     461 de 852 habían dicho qué buscan
--     634 habían tenido conversación de verdad (3+ mensajes suyos)
--     112 escribieron UNA vez y desaparecieron
-- El tablero los pintaba iguales, y por eso no había por dónde empezar.
--
-- LA DEFINICIÓN, DECIDIDA POR SAMUEL: calificado = DIJO QUÉ BUSCA.
-- No es la calificación clásica del arriendo —capacidad de pago,
-- documentos, codeudor— porque de eso no hay ni un dato en esta base:
-- ocurre en el ERP y en la cabeza del asesor. Es lo que sí podemos
-- detectar, y separa a quien se puede trabajar de quien escribió "hola".
--
-- Si con el uso resulta demasiado laxo, el umbral es UNA línea: exigir
-- una especificidad mínima en vez de la mera existencia del requerimiento.
-- =====================================================================

UPDATE crm.etapas
   SET automatica = true
 WHERE codigo = 'calificado';

COMMENT ON TABLE crm.etapas IS
  'Los peldaños del embudo. Ganada/Perdida no están aquí: son estado. "En estudio" está declarada y vacía a propósito — el estudio de documentos ocurre en el ERP y no hay dato que la alimente todavía.';

-- ---------------------------------------------------------------------
-- La evidencia, con el peldaño que faltaba
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.orden_por_evidencia(p_contacto_id uuid)
RETURNS smallint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $evidencia$
  SELECT GREATEST(
    1::smallint,   -- nuevo: existir ya es el primer peldaño

    COALESCE((
      SELECT MAX(CASE
        WHEN a.tipo = 'visita_realizada' THEN 5
        WHEN a.tipo = 'visita_agendada'  THEN 4
        WHEN a.tipo IN ('mensaje_entrante', 'mensaje_saliente',
                        'llamada', 'solicitud_apertura') THEN 2
        ELSE 1
      END) FROM crm.actividades a WHERE a.contacto_id = p_contacto_id
    ), 1)::smallint,

    -- CALIFICADO (3): dijo qué busca. Es la diferencia entre "alguien
    -- escribió" y "sabemos qué necesita", y es lo único que se puede
    -- trabajar sin volver a preguntar.
    COALESCE((
      SELECT 3::smallint FROM crm.requerimientos r
       WHERE r.contacto_id = p_contacto_id AND r.activo LIMIT 1
    ), 1)::smallint,

    -- La visita PRESUNTA: estaba confirmada, la fecha pasó y nadie la
    -- canceló.
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
  );
$evidencia$;

-- ---------------------------------------------------------------------
-- Y que decir qué buscas MUEVA la tarjeta en el momento
--
-- Sin esto, el requerimiento nace y la etapa se queda quieta hasta que
-- pase el recálculo de los cinco minutos. Es nuestra tabla, así que el
-- trigger va donde debe ir.
-- ---------------------------------------------------------------------
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
  ) THEN
    BEGIN
      PERFORM crm.recalcular_oportunidad(NEW.contacto_id);
    EXCEPTION WHEN OTHERS THEN
      NULL;   -- un requerimiento se guarda aunque el pipeline falle
    END;
  END IF;
  RETURN NULL;
END $pipe$;

CREATE TRIGGER crm_pipeline_requerimiento
  AFTER INSERT OR UPDATE OF activo ON crm.requerimientos
  FOR EACH ROW EXECUTE FUNCTION crm.pipeline_al_llegar_requerimiento();
