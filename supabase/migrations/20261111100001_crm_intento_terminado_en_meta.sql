-- =====================================================================
-- Un resultado más en el registro de intentos: «terminado_en_meta».
--
-- EL CASO (11 nov 2026)
-- Un compañero conectó el 320 por coexistencia desde /whatsapp. La
-- ventana de Meta terminó («Tu cuenta está conectada a Inmobiliaria
-- Cumbres»), pero la plataforma nunca recibió el código: la ventana no le
-- devolvió el control a la página. En crm.intentos_incorporacion no quedó
-- NADA, porque la plataforma solo anotaba cuando llegaba la respuesta de
-- FB.login. Quedamos sin saber qué número ni qué cuenta había conectado
-- Meta, justo lo que esta tabla existe para no perder (decisión 28).
--
-- QUÉ CAMBIA
-- Meta avisa por postMessage cuando el flujo termina (FINISH…), con el
-- waba_id y el phone_number_id, aparte de la respuesta de FB.login. Desde
-- ahora la página lo anota apenas llega, como 'terminado_en_meta': Meta
-- dice que terminó, la plataforma todavía no tiene el permiso. Si después
-- llega el código, se anota además el 'exito' (o el 'error') de siempre:
-- son dos hechos distintos y quedan las dos filas.
--
-- Como un 'cancelado', no exige error; `error` guarda lo que mandó la
-- ventana (si fue coexistencia y el portafolio del cliente).
-- =====================================================================

ALTER TABLE crm.intentos_incorporacion
  DROP CONSTRAINT intentos_incorporacion_resultado_check;

ALTER TABLE crm.intentos_incorporacion
  ADD CONSTRAINT intentos_incorporacion_resultado_check
  CHECK (resultado IN ('exito', 'error', 'cancelado', 'terminado_en_meta'));

COMMENT ON COLUMN crm.intentos_incorporacion.resultado IS
  'exito: la línea quedó guardada · error: falló, con el error de Meta · cancelado: se cerró la ventana · '
  'terminado_en_meta: Meta avisó que terminó, pero la plataforma aún no recibe el código';
