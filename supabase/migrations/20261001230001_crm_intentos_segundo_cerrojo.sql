-- =====================================================================
-- crm.intentos_incorporacion: el segundo cerrojo.
--
-- LO QUE SE VIO EN PRODUCCIÓN EL 1 OCT, AL COMPROBAR LO APLICADO
-- `authenticated` conservaba INSERT, UPDATE y DELETE sobre la tabla: los
-- regalan los privilegios por defecto del esquema a toda tabla nueva.
-- Nadie podía escribir —solo hay política de lectura y la RLS lo
-- bloquea, la prueba 30 lo comprueba—, pero era UN cerrojo. crm.etapas y
-- la cuarentena tienen dos: sin permiso y sin política.
--
-- Y SE CIERRA TAMBIÉN A service_role
-- service_role se salta la RLS, así que para él el permiso era el único
-- cerrojo y estaba abierto: la plataforma podía insertar directamente y
-- saltarse crm.registrar_intento_incorporacion(), que es donde se retira
-- cualquier token que se cuele en el error. La función corre como su
-- dueño y no necesita que service_role tenga permisos sobre la tabla.
-- Con esto, la ÚNICA forma de anotar un intento es la función.
-- =====================================================================

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON crm.intentos_incorporacion FROM PUBLIC, anon, authenticated, service_role;

-- Leer sigue igual: la inmobiliaria por RLS, la plataforma entera.
GRANT SELECT ON crm.intentos_incorporacion TO authenticated, service_role;
