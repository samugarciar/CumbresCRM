-- =====================================================================
-- Las funciones de sistema dejan de estar abiertas a cualquiera que se
-- loguee.
--
-- EL FALLO
-- `20260911163314_crm_esquema.sql` puso EXECUTE para authenticated en
-- los privilegios por defecto del esquema. Toda función nueva de crm
-- nacía ejecutable por cualquier usuario logueado, y por PostgREST,
-- porque crm está expuesto. Las de pantalla no preocupan: son SECURITY
-- INVOKER y manda la RLS. Las SECURITY DEFINER sí: reciben la
-- inmobiliaria o el contacto por parámetro y se saltan la RLS.
--
-- Reproducido en local el 26 sep: una sesión de Alfa, que no ve ni una
-- fila de Beta, llamó a `crm.reactivar_bots(0)` y le devolvió la voz al
-- bot en un lead ESCALADO de Beta. Sin conocer un solo id.
--
-- POR QUÉ AHORA Y NO "ANTES DE LA SEGUNDA INMOBILIARIA"
-- La auditoría del 18 sep lo dio por inofensivo mientras hubiera un solo
-- inquilino. Pero la plataforma deja /registro-inmobiliaria abierto sin
-- sesión: la segunda inmobiliaria la puede crear cualquiera, en este
-- mismo proyecto, cuando quiera.
--
-- EL PROBLEMA ERA LA LISTA, NO SU CONTENIDO
-- Hasta hoy cada migración cerraba lo suyo con un REVOKE, y bastaba con
-- olvidarse una vez. Ejemplo de manual: `crm_pipeline` cerró
-- `crm.abrir_oportunidad(uuid)`; cuando `crm_embudos` la rehízo como
-- `(uuid, text)`, la firma nueva nació abierta y nadie lo notó. La red de
-- ahora no es esta migración sino la prueba 27: toda función que
-- authenticated pueda ejecutar y no esté en su lista blanca la tumba.
--
-- LO QUE ESTA MIGRACIÓN NO PUEDE HACER, Y POR QUÉ
-- El arreglo de fondo que apuntó la auditoría era "cambiar el privilegio
-- por defecto del esquema". Se hace (§1), pero SOLO no cierra lo nuevo:
-- Postgres concede EXECUTE a PUBLIC en toda función nueva por un
-- privilegio por defecto GLOBAL, y el de esquema solo SUMA al global,
-- nunca resta. `ALTER DEFAULT PRIVILEGES IN SCHEMA crm REVOKE EXECUTE ON
-- FUNCTIONS FROM PUBLIC` se acepta sin error y no hace nada. Medido: una
-- función creada después sigue naciendo con `=X/postgres`, y
-- authenticated la ejecuta a través de PUBLIC.
--
-- Cerrarlo de raíz exige la forma global (`FOR ROLE postgres`, sin
-- IN SCHEMA). Esa también cambia lo que nace en `public`, que es del
-- otro repo, así que no la toma una migración del CRM: queda como
-- decisión de Samuel. Mientras tanto, la red es la prueba 27.
--
-- Toda función NUEVA de crm, por tanto:
--   · de pantalla (la llama la app con la sesión del usuario):
--     SECURITY INVOKER, y a la lista blanca de la prueba 27;
--   · de sistema (cron, trigger, plataforma):
--     REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon, authenticated;
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1 · El privilegio por defecto deja de regalar EXECUTE a authenticated
--
-- Con esto, un `REVOKE ... FROM PUBLIC` basta para cerrar una función
-- nueva; antes también había que acordarse de authenticated. service_role
-- lo conserva: es el servidor de la plataforma.
-- ---------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES IN SCHEMA crm
  REVOKE EXECUTE ON FUNCTIONS FROM authenticated;

-- ---------------------------------------------------------------------
-- 2 · Las SECURITY DEFINER que seguían abiertas
--
-- Ninguna la llama la app con la sesión del usuario: todas las `.rpc()`
-- de la app van a funciones SECURITY INVOKER. Quién las llama de verdad:
--
--   · los crones, como postgres, que es el dueño y no pierde nada;
--   · otras funciones DEFINER y los triggers de proyección, que corren
--     como el dueño;
--   · la plataforma (CumbresStateInventory), siempre con service_role:
--     el webhook de Meta y el agente comercial, verificado en su código.
-- ---------------------------------------------------------------------

-- Crones
REVOKE ALL ON FUNCTION crm.reintentar_eventos(int)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.reactivar_bots(int)
  FROM PUBLIC, anon, authenticated;

-- La cadena de identidad y de fallos de la proyección. resolver_contacto
-- crea contactos en la inmobiliaria que se le pase: abierta, cualquiera
-- podía sembrar personas en el CRM de otro.
REVOKE ALL ON FUNCTION crm.resolver_contacto(uuid, jsonb, text, text, text, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.registrar_fallo(uuid, text, text, text, jsonb, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.backfill(uuid)
  FROM PUBLIC, anon, authenticated;

-- El pipeline y el dueño del lead, que se mueven por triggers
REVOKE ALL ON FUNCTION crm.abrir_oportunidad(uuid, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.reclamar_si_huerfana(uuid, uuid)
  FROM PUBLIC, anon, authenticated;

-- Recuperaciones puntuales: la del consentimiento la corrió su propia
-- migración; la de teléfonos se corre a mano
REVOKE ALL ON FUNCTION crm.backfill_consentimiento()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.recuperar_telefonos_desde_herramientas(uuid)
  FROM PUBLIC, anon, authenticated;

-- Los contratos con la plataforma. Se les concede EXECUTE a service_role
-- de forma EXPLÍCITA, aunque ya lo tuvieran por defecto: son lo único de
-- aquí que se cae en producción si alguien lo quita, y así queda escrito.
REVOKE ALL ON FUNCTION crm.bot_puede_responder(uuid, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.linea_por_numero(text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.registrar_estado_envio(text, text, int, text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION crm.bot_puede_responder(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION crm.linea_por_numero(text) TO service_role;
GRANT EXECUTE ON FUNCTION crm.registrar_estado_envio(text, text, int, text) TO service_role;

-- ---------------------------------------------------------------------
-- 3 · El cruce que puntúa contra TODO el catálogo, y la función que lo usa
--
-- Abierta, puntaje_match puntuaba requerimientos de cualquier
-- inmobiliaria. Pasarla a INVOKER no sería un arreglo equivalente: la RLS
-- de public.inmuebles solo le deja ver a un asesor los inmuebles que
-- tiene asignados, y sus puntajes cambiarían. Por eso se cierra y no se
-- convierte.
--
-- clientes_para es INVOKER, pero se apoya en las dos de abajo y deja de
-- funcionar para authenticated en cuanto se cierran. Se cierra con ellas
-- en vez de dejarla en la lista blanca rota. Ninguna pantalla la llamó
-- nunca, ni la plataforma. Si una pantalla la necesita, primero hay que
-- decidir qué inmuebles ajenos puede puntuar un asesor. Esa decisión no
-- puede quedar escondida en una función DEFINER.
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION crm.puntaje_match(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.especificidad(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.clientes_para(uuid, smallint)
  FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4 · Las funciones de trigger
--
-- Una función de trigger no se puede invocar a mano ("trigger functions
-- can only be called as triggers"), así que no eran una puerta. Se
-- cierran para que la lista de lo que authenticated puede ejecutar sea
-- exactamente la de las pantallas, sin ruido.
--
-- Cerrarlas NO apaga la proyección: Postgres no comprueba EXECUTE sobre
-- la función cuando el trigger se dispara, solo al crearlo. Verificado en
-- local con los permisos ya quitados: un mensaje insertado como
-- service_role se proyectó entero, y una edición hecha como authenticated
-- disparó tocar_updated_at. La prueba 20 lo ejerce además de punta a
-- punta: una nota escrita como asesor reclama el lead a través de
-- reclamar_al_anotar → reclamar_si_huerfana, ambas cerradas.
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION crm.proyectar_mensaje()                FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.proyectar_cita()                   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.proyectar_solicitud()              FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.pipeline_al_llegar_actividad()     FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.pipeline_al_llegar_requerimiento() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.reclamar_al_anotar()               FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.reclamar_al_mover()                FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.reclamar_al_tarear()               FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.consentir_al_escribirnos()         FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.sincronizar_telefono_principal()   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION crm.tocar_updated_at()                 FROM PUBLIC, anon, authenticated;
