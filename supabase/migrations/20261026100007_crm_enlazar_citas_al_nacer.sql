-- =====================================================================
-- Las citas que ya tenía una persona se enlazan cuando entra al CRM
-- (26 oct 2026)
--
-- LO QUE PASABA
-- Con solo_lineas_oficiales (20261016120001), una cita o una solicitud de
-- apertura solo entra al CRM si la persona YA está ahí: el agente agenda
-- por la 324 (Kommo) a gente que el CRM todavía no conoce. Cuando esa
-- persona escribe después por la línea oficial y nace su contacto, sus
-- citas no aparecen en su ficha ni en Mi día con su nombre: la proyección
-- de la cita ya pasó y no vuelve a correr. En producción, el 25 oct: 19
-- citas futuras de 17 teléfonos con conversación del agente.
--
-- LA PIEZA
-- Un trigger AFTER INSERT en crm.identidades, solo para telefono_e164:
-- cuando una persona gana su teléfono en el CRM, se proyectan las citas
-- AGENDADAS de hoy en adelante (crm.hoy(), día de Bogotá) y las
-- solicitudes de apertura PENDIENTES de ese teléfono en esa inmobiliaria.
-- Misma fila que deja crm.proyectar_cita / crm.proyectar_solicitud, con
-- el mismo origen (origen_tabla, origen_id) y ON CONFLICT DO NOTHING: si ya
-- estaba enlazada, no se duplica. Solo lee public y escribe crm. Envuelto
-- en EXCEPTION WHEN OTHERS con crm.registrar_fallo: si algo falla, el
-- contacto nace igual.
--
-- Idempotente.
-- =====================================================================

CREATE OR REPLACE FUNCTION crm.enlazar_citas_al_nacer()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $enlazar$
BEGIN
  IF NEW.tipo <> 'telefono_e164' OR NEW.contacto_id IS NULL THEN
    RETURN NULL;
  END IF;

  BEGIN
    -- Las visitas que tiene por delante.
    INSERT INTO crm.actividades (
      inmobiliaria_id, tipo, origen, contacto_id, inmueble_id, cita_id,
      ocurrido_at, metadata)
    SELECT ci.inmobiliaria_id, 'visita_agendada', 'sistema', NEW.contacto_id,
           ci.inmueble_id, ci.id, ci.created_at,
           jsonb_build_object(
             'origen_tabla', 'citas',
             'origen_id', ci.id::text,
             'fecha', ci.fecha, 'hora', ci.hora_inicio,
             'enlazada_al_nacer', true)
      FROM public.citas ci
     WHERE ci.inmobiliaria_id = NEW.inmobiliaria_id
       AND ci.estado = 'agendada'
       AND ci.fecha >= crm.hoy()
       AND crm.normalizar_telefono(ci.cliente_telefono) = NEW.valor
    ON CONFLICT DO NOTHING;

    -- Y los horarios que pidió y siguen sin respuesta.
    INSERT INTO crm.actividades (
      inmobiliaria_id, tipo, origen, contacto_id, inmueble_id,
      ocurrido_at, metadata)
    SELECT s.inmobiliaria_id, 'solicitud_apertura', 'sistema', NEW.contacto_id,
           s.inmueble_id, s.created_at,
           jsonb_build_object(
             'origen_tabla', 'solicitudes_apertura',
             'origen_id', s.id::text,
             'fecha_pedida', s.fecha,
             'hora_pedida', s.hora_inicio,
             'estado', s.estado,
             'enlazada_al_nacer', true)
      FROM public.solicitudes_apertura s
     WHERE s.inmobiliaria_id = NEW.inmobiliaria_id
       AND s.estado = 'pendiente'
       AND crm.normalizar_telefono(s.cliente_telefono) = NEW.valor
    ON CONFLICT DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    PERFORM crm.registrar_fallo(
      NEW.inmobiliaria_id, 'cita', 'identidades', NEW.contacto_id::text,
      jsonb_build_object('motivo', 'enlazar citas al nacer', 'telefono', NEW.valor),
      SQLERRM);
  END;

  RETURN NULL;
END $enlazar$;

COMMENT ON FUNCTION crm.enlazar_citas_al_nacer() IS
  'Trigger de crm.identidades: cuando alguien gana su teléfono en el CRM, le enlaza sus citas agendadas '
  'desde hoy (Bogotá) y sus solicitudes de apertura pendientes. Idempotente por origen; nunca tumba el insert.';

REVOKE ALL ON FUNCTION crm.enlazar_citas_al_nacer() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION crm.enlazar_citas_al_nacer() TO service_role;

DROP TRIGGER IF EXISTS crm_enlazar_citas_al_nacer ON crm.identidades;
CREATE TRIGGER crm_enlazar_citas_al_nacer
  AFTER INSERT ON crm.identidades
  FOR EACH ROW
  WHEN (NEW.tipo = 'telefono_e164')
  EXECUTE FUNCTION crm.enlazar_citas_al_nacer();
