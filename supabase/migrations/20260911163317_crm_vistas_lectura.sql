-- =====================================================================
-- Vistas de solo lectura hacia `public`.
--
-- El CRM necesita el catálogo, el equipo y las visitas, pero no debe
-- consultar las tablas del otro repo directamente. Con estas vistas, el
-- día que CumbresStateInventory cambie una columna, lo que se rompe es
-- una vista —en un solo sitio, con un nombre— y no cuarenta consultas
-- repartidas por la aplicación.
--
-- `security_invoker = true` es lo que hace que esto sea seguro: la vista
-- se evalúa con los permisos y la RLS de QUIEN CONSULTA, no de quien la
-- creó. Sin esa opción, una vista sería un agujero por el que un asesor
-- vería inmuebles de otra inmobiliaria.
-- =====================================================================

-- ---------------------------------------------------------------------
CREATE VIEW crm.v_asesores WITH (security_invoker = true) AS
  SELECT
    u.id,
    u.inmobiliaria_id,
    u.nombre_completo,
    u.email,
    u.telefono,
    u.rol
  FROM public.usuarios u;

COMMENT ON VIEW crm.v_asesores IS
  'Equipo comercial, leído de public.usuarios con la RLS de quien consulta.';

-- ---------------------------------------------------------------------
CREATE VIEW crm.v_inmuebles WITH (security_invoker = true) AS
  SELECT
    i.id,
    i.inmobiliaria_id,
    i.titulo,
    i.direccion,
    i.unidad,
    i.ciudad,
    i.barrio,
    i.habitaciones,
    i.banos,
    i.precio,
    i.tipo_transaccion,
    i.tipo_inmueble,
    -- `estado` ya es el efectivo: coalesce(estado_override, estado_erp).
    -- El CRM consume el efectivo y no replica esa regla, que es del otro
    -- repo. Si algún día cambia, cambia aquí y no en toda la aplicación.
    i.estado,
    COALESCE(i.asesor_id_override, i.asesor_id) AS asesor_id,
    i.imagenes,
    i.arrendasoft_id,
    i.created_at
  FROM public.inmuebles i;

COMMENT ON VIEW crm.v_inmuebles IS
  'Catálogo. `estado` es el efectivo del otro repo; `asesor_id` ya resuelve el override.';

-- ---------------------------------------------------------------------
CREATE VIEW crm.v_citas WITH (security_invoker = true) AS
  SELECT
    c.id,
    c.inmobiliaria_id,
    c.inmueble_id,
    c.fecha,
    c.hora_inicio,
    c.hora_fin,
    c.cliente_nombre,
    c.cliente_telefono,
    c.cliente_email,
    -- La columna que convierte esta vista en el puente hacia el contacto:
    -- misma normalización que usa crm.contactos, así el join es directo.
    crm.normalizar_telefono(c.cliente_telefono) AS telefono_e164,
    c.estado,
    c.origen,
    c.alcance,
    c.unidad,
    c.confirmada_at,
    c.created_at
  FROM public.citas c;

COMMENT ON VIEW crm.v_citas IS
  'Visitas agendadas, con el teléfono ya normalizado para poder unirlas a crm.contactos.';

-- ---------------------------------------------------------------------
GRANT SELECT ON crm.v_asesores, crm.v_inmuebles, crm.v_citas TO authenticated;
