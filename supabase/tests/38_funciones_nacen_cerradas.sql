-- =====================================================================
-- Las funciones nuevas nacen cerradas (decisión de Samuel, 1 oct).
--
-- Se crean funciones de verdad dentro de la transacción —como las
-- crearía una migración— y se mira quién puede ejecutarlas. Comprobar
-- solo el catálogo de privilegios por defecto no bastaría: lo que
-- importa es lo que le pasa a la próxima función.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(8);

CREATE FUNCTION crm.prueba_nace_cerrada() RETURNS int LANGUAGE sql AS 'SELECT 1';
CREATE FUNCTION public.prueba_nace_en_public() RETURNS int LANGUAGE sql AS 'SELECT 1';

SELECT ok(
  NOT has_function_privilege('authenticated', 'crm.prueba_nace_cerrada()', 'EXECUTE'),
  'Una función nueva de crm NO la puede ejecutar un usuario con sesión hasta que alguien lo decida'
);

SELECT ok(
  NOT has_function_privilege('anon', 'crm.prueba_nace_cerrada()', 'EXECUTE'),
  'Ni un anónimo'
);

SELECT ok(
  has_function_privilege('service_role', 'crm.prueba_nace_cerrada()', 'EXECUTE'),
  'La plataforma sí, por el privilegio de esquema de crm'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.prueba_nace_en_public()', 'EXECUTE')
  AND has_function_privilege('anon', 'public.prueba_nace_en_public()', 'EXECUTE')
  AND has_function_privilege('service_role', 'public.prueba_nace_en_public()', 'EXECUTE'),
  'En public nada cambia para anon, authenticated y service_role: public se los da explícitamente'
);

SELECT ok(
  NOT has_function_privilege('bi_reader', 'public.prueba_nace_en_public()', 'EXECUTE'),
  'Lo único que cambia en public: bi_reader ya no hereda las funciones nuevas por PUBLIC'
);

SELECT ok(
  has_function_privilege('authenticated', 'crm.mi_dia(int, uuid)', 'EXECUTE'),
  'Las funciones que ya existían no cambian: Mi día sigue abierta para la pantalla'
);

-- La convención nueva: una función de pantalla lleva su GRANT.
GRANT EXECUTE ON FUNCTION crm.prueba_nace_cerrada() TO authenticated;

SELECT ok(
  has_function_privilege('authenticated', 'crm.prueba_nace_cerrada()', 'EXECUTE'),
  'Con su GRANT explícito, la pantalla la puede llamar'
);

SELECT ok(
  NOT has_function_privilege('anon', 'crm.prueba_nace_cerrada()', 'EXECUTE'),
  'Y el GRANT a authenticated no se la abre a un anónimo'
);

SELECT * FROM finish();
ROLLBACK;
