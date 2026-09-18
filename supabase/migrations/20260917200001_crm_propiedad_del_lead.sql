-- =====================================================================
-- De quién es un lead.
--
-- LA DECISIÓN (Samuel, 17 sep 2026)
-- Ser dueño es RESPONSABILIDAD, no visibilidad. Todos siguen viendo
-- todo y las 46 políticas RLS no se tocan; lo que cambia es que «Mi día»
-- puede ordenar por persona y que la ficha puede avisar de que otro ya
-- está en esa conversación.
--
-- POR QUÉ NO SE ASIGNAN LOS 1.296 HUÉRFANOS
-- Se buscó de dónde deducirlo y NO HAY NADA. Medido en producción:
--   · ningún contacto tiene asesor_id           (0 de 1.350)
--   · public.citas no tiene columna de asesor   (solo confirmada_por)
--   · notas escritas por un humano              0
-- Repartirlos por round-robin o por el asesor del inmueble sería
-- inventar un hecho, y este proyecto ya decidió que ante la duda no se
-- adivina: un teléfono que no normaliza se guarda crudo, y una visita
-- que nadie confirmó se marca como presunta.
--
-- Así que el dueño NO se reparte: se reclama. El primero que hace algo
-- deliberado por ese lead se queda con él, y el resto se puede asignar a
-- mano. En un equipo de dos asesores y una admin, repartir 1.296 leads
-- que nadie ha tocado no habría creado responsabilidad, solo etiquetas.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Reclamar lo que no tiene dueño
--
-- Se llama desde triggers en vez de desde cada camino de la aplicación,
-- porque la lista de "actos deliberados" va a crecer —mandar una
-- plantilla, contestar en el chat— y una función que hay que acordarse
-- de llamar es una función que un día no se llama.
--
-- NUNCA le quita el lead a nadie: solo actúa si asesor_id es NULL. Que
-- un asesor conteste en la ficha de otro es normal en este negocio, y
-- que eso le transfiera la responsabilidad en silencio sería peor que
-- no tener responsables.
-- ---------------------------------------------------------------------
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
     AND asesor_id IS NULL
     AND p_usuario IS NOT NULL;
$rec$;

COMMENT ON FUNCTION crm.reclamar_si_huerfana(uuid, uuid) IS
  'El primero que hace algo deliberado por un lead sin dueño se queda con él. Nunca se lo quita a nadie.';

-- Una nota es el acto deliberado por excelencia: alguien se sentó a
-- escribir qué pasó. El bot deja creado_por NULL, así que no reclama.
CREATE OR REPLACE FUNCTION crm.reclamar_al_anotar()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $ra$
BEGIN
  IF NEW.creado_por IS NOT NULL AND NEW.contacto_id IS NOT NULL THEN
    BEGIN
      PERFORM crm.reclamar_si_huerfana(NEW.contacto_id, NEW.creado_por);
    EXCEPTION WHEN OTHERS THEN
      NULL;   -- reclamar un lead jamás puede tumbar la escritura real
    END;
  END IF;
  RETURN NULL;
END $ra$;

CREATE TRIGGER crm_reclamar_al_anotar
  AFTER INSERT ON crm.actividades
  FOR EACH ROW EXECUTE FUNCTION crm.reclamar_al_anotar();

-- Mover a alguien de etapa es decir "yo lo estoy llevando".
CREATE OR REPLACE FUNCTION crm.reclamar_al_mover()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $rm$
DECLARE
  v_contacto uuid;
BEGIN
  IF NEW.origen = 'humano' AND NEW.usuario_id IS NOT NULL THEN
    BEGIN
      SELECT o.contacto_id INTO v_contacto
        FROM crm.oportunidades o WHERE o.id = NEW.oportunidad_id;
      PERFORM crm.reclamar_si_huerfana(v_contacto, NEW.usuario_id);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;
  RETURN NULL;
END $rm$;

CREATE TRIGGER crm_reclamar_al_mover
  AFTER INSERT ON crm.transiciones
  FOR EACH ROW EXECUTE FUNCTION crm.reclamar_al_mover();

-- Ponerse una tarea sobre alguien es comprometerse con ese alguien.
CREATE OR REPLACE FUNCTION crm.reclamar_al_tarear()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $rt$
BEGIN
  IF NEW.contacto_id IS NOT NULL THEN
    BEGIN
      PERFORM crm.reclamar_si_huerfana(
        NEW.contacto_id, COALESCE(NEW.asignado_a, NEW.creado_por));
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;
  RETURN NULL;
END $rt$;

CREATE TRIGGER crm_reclamar_al_tarear
  AFTER INSERT ON crm.tareas
  FOR EACH ROW EXECUTE FUNCTION crm.reclamar_al_tarear();

-- ---------------------------------------------------------------------
-- Asignar a mano, incluso quitándoselo a otro
--
-- Deja rastro en el historial. Cambiar de responsable sin que conste es
-- exactamente el tipo de cosa que después nadie consigue explicar.
-- ---------------------------------------------------------------------
-- p_asesor_id lleva DEFAULT NULL para que omitirlo signifique "quitarle
-- el responsable". Además hace que el tipo generado para TypeScript sea
-- opcional en vez de obligatorio, y así el cliente no tiene que mandar un
-- null explícito donde el tipo dice que va un uuid.
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
   WHERE o.contacto_id = p_contacto_id AND o.estado = 'abierta';

  IF v_inmobiliaria IS NULL THEN RETURN false; END IF;
  IF v_antes IS NOT DISTINCT FROM p_asesor_id THEN RETURN true; END IF;

  UPDATE crm.oportunidades
     SET asesor_id = p_asesor_id, updated_at = now()
   WHERE contacto_id = p_contacto_id AND estado = 'abierta';

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

COMMENT ON FUNCTION crm.asignar_lead(uuid, uuid) IS
  'Cambia el responsable de la oportunidad abierta de un contacto y lo deja escrito en el historial.';

GRANT EXECUTE ON FUNCTION crm.asignar_lead(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- Quién lleva este lead, para poder avisar en la ficha
--
-- Devuelve NULL cuando no hay dueño, que es el caso mayoritario hoy.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.responsable_de(p_contacto_id uuid)
RETURNS TABLE (asesor_id uuid, nombre text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $resp$
  SELECT o.asesor_id, u.nombre_completo
    FROM crm.oportunidades o
    LEFT JOIN public.usuarios u ON u.id = o.asesor_id
   WHERE o.contacto_id = p_contacto_id AND o.estado = 'abierta'
   LIMIT 1;
$resp$;

GRANT EXECUTE ON FUNCTION crm.responsable_de(uuid) TO authenticated;

-- Para que «Mi día» filtre sin barrer la tabla.
CREATE INDEX oportunidades_asesor_abiertas
  ON crm.oportunidades (inmobiliaria_id, asesor_id)
  WHERE estado = 'abierta';
