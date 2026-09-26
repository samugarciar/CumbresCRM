-- =====================================================================
-- La coexistencia: la línea conectada a Meta, su token, y el relevo.
--
-- Lo que más importa de este archivo no es que las funciones funcionen,
-- sino lo que NO se puede hacer:
--   · que alguien logueado —ni siquiera un admin— lea el token de Meta.
--     El esquema crm regala EXECUTE a authenticated en toda función
--     nueva; si alguien quita un REVOKE, esto se cae;
--   · que el historial que Meta reproduce al conectar calle al bot;
--   · que el relevo le pase por encima a un silencio manual o a uno por
--     escalamiento, que tienen reglas propias aprobadas.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(60);

DELETE FROM crm.lineas;
DELETE FROM crm.contactos;

-- =====================================================================
-- 1 · Conectar una línea, y dónde queda su token
-- =====================================================================
SELECT ok(
  crm.conectar_linea('11111111-1111-1111-1111-111111111111', 'comercial',
                     'waba-alfa', '100000000000001', 'coexistencia',
                     'EAAG-token-uno', '+573001230001') IS NOT NULL,
  'El registro integrado deja la línea comercial conectada'
);

SELECT is(
  (SELECT waba_id || '/' || modo || '/' || (conectada_at IS NOT NULL)
          || '/' || (token_secreto_id IS NOT NULL)
     FROM crm.lineas WHERE wa_phone_number_id = '100000000000001'),
  'waba-alfa/coexistencia/true/true',
  'La línea sabe su WABA, su modo, cuándo se conectó y dónde está su token'
);

SELECT is(
  (SELECT nombre FROM crm.lineas WHERE wa_phone_number_id = '100000000000001'),
  'Comercial',
  'Sin nombre, toma el del embudo: nadie tiene que inventarlo durante el registro'
);

SELECT is(
  (SELECT count(*)::int FROM crm.lineas l
    WHERE to_jsonb(l)::text LIKE '%EAAG-token-uno%'),
  0,
  'El token NO está en ninguna columna de crm.lineas: vive cifrado en Vault'
);

SET LOCAL ROLE service_role;

SELECT is(
  (SELECT token FROM crm.credencial_linea('100000000000001')),
  'EAAG-token-uno',
  'La plataforma, con service_role, recupera el token por el phone_number_id'
);

RESET ROLE;

-- --- Reconectar ------------------------------------------------------
SELECT is(
  crm.conectar_linea('11111111-1111-1111-1111-111111111111', 'comercial',
                     'waba-alfa', '100000000000001', 'coexistencia',
                     'EAAG-token-dos'),
  (SELECT id FROM crm.lineas WHERE wa_phone_number_id = '100000000000001'),
  'Reconectar no crea otra línea: actualiza la que hay'
);

SELECT is(
  (SELECT token FROM crm.credencial_linea('100000000000001')),
  'EAAG-token-dos',
  'Y el token nuevo reemplaza al viejo'
);

SELECT is(
  (SELECT count(*)::int FROM vault.secrets s
     JOIN crm.lineas l ON s.name = 'crm_linea_' || l.id::text
    WHERE l.wa_phone_number_id = '100000000000001'),
  1,
  'Un solo secreto por línea: reconectar no deja tokens viejos vivos en Vault'
);

SELECT is(
  (SELECT telefono_e164 FROM crm.lineas WHERE wa_phone_number_id = '100000000000001'),
  '+573001230001',
  'Reconectar sin teléfono no borra el que ya estaba'
);

-- --- Una línea conectada tiene todas sus piezas ----------------------
SELECT throws_ok(
  $$UPDATE crm.lineas SET waba_id = NULL WHERE wa_phone_number_id = '100000000000001'$$,
  '23514',
  NULL,
  'Una línea conectada sin WABA no cabe: a medio conectar parece que funciona'
);

SELECT throws_ok(
  $$SELECT crm.conectar_linea('11111111-1111-1111-1111-111111111111', 'captacion',
                              'w', '100000000000009', 'webhook_de_kommo', 't')$$,
  '22023',
  NULL,
  'Un modo inventado se rechaza: coexistencia o cloud_api'
);

SELECT throws_ok(
  $$SELECT crm.conectar_linea('11111111-1111-1111-1111-111111111111', 'captacion',
                              'w', '100000000000009', 'cloud_api', '  ')$$,
  '22023',
  NULL,
  'Sin token no hay línea: un intercambio de código fallido no deja una conexión fantasma'
);

-- =====================================================================
-- 2 · Nadie fuera del servidor toca un token
-- =====================================================================
SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$SELECT * FROM crm.credencial_linea('100000000000001')$$,
  '42501',
  NULL,
  'Ni un ADMIN logueado puede pedir el token: el esquema regala EXECUTE a toda función nueva, y aquí se le quitó'
);

SELECT throws_ok(
  $$SELECT crm.conectar_linea('11111111-1111-1111-1111-111111111111', 'comercial',
                              'x', '1', 'coexistencia', 't')$$,
  '42501',
  NULL,
  'Ni conectar una línea desde el navegador: el token entra solo por el servidor de la plataforma'
);

SELECT throws_ok(
  $$SELECT decrypted_secret FROM vault.decrypted_secrets$$,
  '42501',
  NULL,
  'Y Vault está cerrado para authenticated: no hay atajo alrededor de la función'
);

SELECT throws_ok(
  $$SELECT crm.registrar_relevo('100000000000001', '573005550001')$$,
  '42501',
  NULL,
  'El relevo lo anota la plataforma, no el navegador: si no, cualquiera callaría al bot en cualquier lead'
);

SELECT throws_ok(
  $$SELECT crm.registrar_estado_linea('100000000000001', 'suscripcion_verificada')$$,
  '42501',
  NULL,
  'Ni marcar una suscripción como verificada, que es la alarma que más importa que no mienta'
);

SELECT is(
  (SELECT modo FROM crm.lineas WHERE wa_phone_number_id = '100000000000001'),
  'coexistencia',
  'Lo que el admin SÍ ve es el estado de la conexión: para eso está la pantalla de líneas'
);

RESET ROLE;

SELECT ok(
  NOT has_function_privilege('anon', 'crm.credencial_linea(text)', 'execute'),
  'Y anon tampoco, claro'
);

-- =====================================================================
-- 3 · La sincronización de la coexistencia
-- =====================================================================
SELECT is(
  (SELECT crm.estado_sincronizacion(l) FROM crm.lineas l
    WHERE wa_phone_number_id = '100000000000001'),
  'pendiente',
  'Recién conectada: quedan 24 horas para pedir contactos e historial'
);

SELECT ok(
  crm.registrar_estado_linea('100000000000001', 'contactos_solicitados')
  AND crm.registrar_estado_linea('100000000000001', 'historial_solicitado'),
  'La plataforma anota que pidió los contactos y el historial'
);

SELECT is(
  (SELECT crm.estado_sincronizacion(l) FROM crm.lineas l
    WHERE wa_phone_number_id = '100000000000001'),
  'en_curso',
  'Pedidos los dos, la sincronización está en curso'
);

SELECT ok(
  crm.registrar_estado_linea('100000000000001', 'historial_progreso', 60)
  AND crm.registrar_estado_linea('100000000000001', 'historial_progreso', 30),
  'Llegan dos lotes, el segundo con menos progreso que el primero'
);

SELECT is(
  (SELECT historial_progreso::int FROM crm.lineas WHERE wa_phone_number_id = '100000000000001'),
  60,
  'Los lotes llegan desordenados: el progreso solo sube'
);

SELECT ok(
  crm.registrar_estado_linea('100000000000001', 'historial_progreso', 100),
  'Llega el último lote'
);

SELECT is(
  (SELECT crm.estado_sincronizacion(l) || '/' || (l.historial_completado_at IS NOT NULL)
     FROM crm.lineas l WHERE wa_phone_number_id = '100000000000001'),
  'completo/true',
  'Al 100 % consta en la base que el historial quedó sincronizado, y cuándo'
);

-- --- La reconexión empieza un ciclo nuevo -----------------------------
-- En sentencia aparte: dentro de un WHERE, la función correría una vez
-- por fila examinada, y el estado se leería de la instantánea de antes.
SELECT ok(
  crm.conectar_linea('11111111-1111-1111-1111-111111111111', 'comercial',
                     'waba-alfa', '100000000000001', 'coexistencia',
                     'EAAG-token-tres') IS NOT NULL,
  'Se reconecta la línea comercial ya sincronizada'
);

SELECT is(
  (SELECT crm.estado_sincronizacion(l) FROM crm.lineas l
    WHERE wa_phone_number_id = '100000000000001'),
  'pendiente',
  'Reconectar empieza un ciclo nuevo: Meta obliga a sincronizar otra vez, y lo anterior deja de valer'
);

-- --- Solo API: las reglas de la coexistencia no aplican ---------------
SELECT ok(
  crm.conectar_linea('11111111-1111-1111-1111-111111111111', 'captacion',
                     'waba-alfa', '100000000000003', 'cloud_api',
                     'EAAG-token-captacion') IS NOT NULL,
  'Una línea solo de API también se conecta'
);

SELECT is(
  (SELECT crm.estado_sincronizacion(l) FROM crm.lineas l
    WHERE wa_phone_number_id = '100000000000003'),
  'no_aplica',
  'Y sin app en el celular no hay historial que traer: no queda como pendiente para siempre'
);

-- --- El negocio tiene el historial apagado ---------------------------
-- Dos sentencias y no un AND: SQL no garantiza el orden de evaluación, y
-- el error no tiene dónde anotarse si la línea todavía no existe.
SELECT ok(
  crm.conectar_linea('11111111-1111-1111-1111-111111111111', 'administrativa',
                     'waba-alfa', '100000000000002', 'coexistencia',
                     'EAAG-token-administrativa') IS NOT NULL,
  'Se conecta la línea administrativa, también en coexistencia'
);

SELECT ok(
  crm.registrar_estado_linea('100000000000002', 'historial_error', NULL, 2593109,
    'History sync is turned off by the business from the WhatsApp Business App'),
  'Y al pedir su historial llega el error 2593109'
);

SELECT is(
  (SELECT crm.estado_sincronizacion(l) FROM crm.lineas l
    WHERE wa_phone_number_id = '100000000000002'),
  'rechazado',
  'Queda como rechazado, no como fallido: lo apagó el negocio en su app, y reintentar no sirve'
);

-- --- El plazo de 24 horas --------------------------------------------
SELECT ok(
  crm.conectar_linea('22222222-2222-2222-2222-222222222222', 'comercial',
                     'waba-beta', '200000000000001', 'coexistencia',
                     'EAAG-token-beta') IS NOT NULL,
  'Beta conecta su línea comercial'
);

UPDATE crm.lineas SET conectada_at = now() - interval '25 hours'
 WHERE wa_phone_number_id = '200000000000001';

SELECT is(
  (SELECT crm.estado_sincronizacion(l) FROM crm.lineas l
    WHERE wa_phone_number_id = '200000000000001'),
  'vencido',
  'Pasaron 24 horas sin pedir la sincronización: la base lo dice sola, sin que nadie tenga que acordarse de mirar'
);

-- --- Lo que la función no acepta -------------------------------------
SELECT throws_ok(
  $$SELECT crm.registrar_estado_linea('100000000000001', 'historial_casi_listo')$$,
  '22023',
  NULL,
  'Un evento inventado se rechaza en vez de anotarse en ningún sitio'
);

SELECT ok(
  NOT crm.registrar_estado_linea('999999999999999', 'historial_solicitado'),
  'Un número sin línea no anota nada, y lo dice'
);

-- =====================================================================
-- 4 · El relevo
--
-- Sara tiene el bot encendido. Los demás están callados por cada uno de
-- los motivos posibles, para ver que el relevo solo toca lo suyo.
-- =====================================================================
INSERT INTO crm.contactos
  (id, inmobiliaria_id, nombre, telefono_e164, bot_activo, bot_motivo, bot_cambiado_at)
VALUES
  ('c0260001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Sara Gómez', '+573005550001', true, NULL, NULL),
  ('c0260002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'Me encargo yo', '+573005550002', false, 'manual', now() - interval '1 hour'),
  ('c0260003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
   'Pidió una persona', '+573005550003', false, 'escalamiento', now() - interval '1 hour'),
  ('c0260004-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111',
   'Hace siete horas', '+573005550004', false, 'relevo', now() - interval '7 hours'),
  ('c0260005-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111',
   'Hace una hora', '+573005550005', false, 'relevo', now() - interval '1 hour');

-- --- Solo en la línea donde el bot habla ------------------------------
SELECT ok(
  NOT crm.registrar_relevo('100000000000002', '573005550001'),
  'Alguien de administrativa le escribe a Sara: el relevo no aplica, ahí el bot no habla'
);

SELECT ok(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573005550001'),
  'Y el bot le sigue respondiendo en comercial: atender su contrato no es atender su búsqueda'
);

-- --- El historial no calla a nadie -----------------------------------
SELECT ok(
  NOT crm.registrar_relevo('100000000000001', '573005550001', now() - interval '7 hours'),
  'Un mensaje humano de hace siete horas no calla nada: es lo que Meta reproduce al conectar'
);

SELECT ok(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573005550001'),
  'Sin esa guarda, conectar la línea comercial callaría al bot en cientos de conversaciones de golpe'
);

-- --- Una persona escribe ---------------------------------------------
-- Meta manda el teléfono sin el +: la función normaliza igual que el
-- resto del CRM.
SELECT ok(
  crm.registrar_relevo('100000000000001', '573005550001', now() - interval '2 hours'),
  'Alguien del equipo le escribe a Sara desde el celular'
);

SELECT ok(
  NOT crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573005550001'),
  'Y el bot se calla en esa conversación: no le contesta encima a una persona, delante del cliente'
);

SELECT is(
  (SELECT bot_motivo FROM crm.contactos WHERE id = 'c0260001-0000-0000-0000-000000000001'),
  'relevo',
  'Con motivo propio: ni manual, que no caduca, ni escalamiento, que vuelve a los 3 días'
);

SELECT is(
  (SELECT count(*)::int FROM crm.actividades
    WHERE contacto_id = 'c0260001-0000-0000-0000-000000000001' AND tipo = 'sistema'),
  1,
  'Y queda escrito en el historial por qué se calló'
);

-- --- La ventana corre con el último mensaje ---------------------------
SELECT ok(
  crm.registrar_relevo('100000000000001', '573005550001', now() - interval '1 hour'),
  'Otro mensaje del equipo, una hora después'
);

SELECT is(
  (SELECT bot_cambiado_at FROM crm.contactos WHERE id = 'c0260001-0000-0000-0000-000000000001'),
  now() - interval '1 hour',
  'La ventana corre: las 6 horas se cuentan desde el ÚLTIMO mensaje humano'
);

SELECT is(
  (SELECT count(*)::int FROM crm.actividades
    WHERE contacto_id = 'c0260001-0000-0000-0000-000000000001' AND tipo = 'sistema'),
  1,
  'Sin un aviso nuevo por mensaje, que enterraría el historial'
);

SELECT is(
  crm.bot_vuelve_at('c0260001-0000-0000-0000-000000000001'),
  now() - interval '1 hour' + interval '6 hours',
  'La ficha sabe cuándo vuelve el bot si nadie más escribe'
);

-- --- Los otros silencios mandan --------------------------------------
SELECT ok(
  NOT crm.registrar_relevo('100000000000001', '573005550002')
  AND NOT crm.registrar_relevo('100000000000001', '573005550003'),
  'Sobre un silencio manual o de escalamiento, el relevo no hace nada'
);

SELECT is(
  (SELECT string_agg(bot_motivo, ',' ORDER BY telefono_e164) FROM crm.contactos
    WHERE id IN ('c0260002-0000-0000-0000-000000000002',
                 'c0260003-0000-0000-0000-000000000003')),
  'manual,escalamiento',
  'Cada uno conserva su regla: si el manual pasara a relevo, el bot volvería a las 6 horas a espaldas de quien dijo "yo me encargo"'
);

SELECT is(
  crm.bot_vuelve_at('c0260002-0000-0000-0000-000000000002'),
  NULL,
  'Y el manual no tiene hora de vuelta'
);

SELECT ok(
  NOT crm.registrar_relevo('100000000000001', '573009999999'),
  'Un teléfono sin contacto no calla nada: se falla hacia "el bot responde"'
);

-- --- La vuelta, sola o a mano ----------------------------------------
SELECT is(
  crm.reactivar_relevos(),
  1,
  'Vuelve exactamente uno: el que lleva siete horas sin mensajes del equipo'
);

SELECT ok(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573005550004')
  AND NOT crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573005550005')
  AND NOT crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573005550002'),
  'El de hace siete horas ya tiene bot; el de hace una hora sigue en manos del equipo; el manual, callado'
);

SELECT is(
  (SELECT cuerpo FROM crm.actividades
    WHERE contacto_id = 'c0260004-0000-0000-0000-000000000004' AND tipo = 'sistema'),
  'El bot vuelve a responderle: pasaron 6 horas sin que nadie del equipo le escribiera.',
  'Que vuelva queda escrito, con la cifra sacada de la perilla y no escrita a mano'
);

SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT ok(
  crm.cambiar_bot('c0260005-0000-0000-0000-000000000005', true),
  'El otro camino de vuelta: un asesor lo enciende a mano, sin esperar las 6 horas'
);

RESET ROLE;

SELECT ok(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573005550005'),
  'Y el bot le responde de inmediato'
);

SELECT is(
  (SELECT schedule FROM cron.job WHERE jobname = 'crm_reactivar_relevos'),
  '*/5 * * * *',
  'La vuelta corre cada 5 minutos (y la prueba 19 ejecuta el comando agendado de verdad)'
);

-- =====================================================================
-- 5 · Borrar una línea borra su token
-- =====================================================================
DELETE FROM crm.lineas WHERE wa_phone_number_id = '100000000000003';

SELECT is(
  (SELECT count(*)::int FROM vault.secrets s
    WHERE s.name LIKE 'crm_linea_%'
      AND NOT EXISTS (SELECT 1 FROM crm.lineas l WHERE l.token_secreto_id = s.id)),
  0,
  'Un token que sobrevive a su línea es una credencial viva que nadie sabe que existe: no queda ninguno'
);

SELECT * FROM finish();
ROLLBACK;
