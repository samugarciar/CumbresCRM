-- =====================================================================
-- Quién puede llamar qué.
--
-- La auditoría del 18 sep lo encontró así: las pruebas cubrían la lógica
-- de las funciones, nunca quién podía llamarlas. Había una sola aserción
-- de privilegios en toda la suite. Esta prueba hace esa pregunta de una
-- vez para todo el esquema.
--
-- LA LISTA BLANCA ES EL CONTRATO
-- Postgres da EXECUTE a PUBLIC en toda función nueva, y el privilegio por
-- defecto del esquema no puede quitárselo (lo explica
-- 20260926170001_crm_cerrar_funciones_de_sistema.sql). O sea: TODA
-- función nueva de crm nace ejecutable por authenticated, y esta prueba
-- se cae hasta que alguien decida quién la llama.
--
-- Si se cae por una función que no está en la lista:
--   · ¿La llama la app con la sesión del usuario? Tiene que ser SECURITY
--     INVOKER, y se añade abajo, en su grupo.
--   · ¿Es de sistema (cron, trigger, plataforma)? En su migración:
--       REVOKE ALL ON FUNCTION crm.x(...) FROM PUBLIC, anon, authenticated;
--   · Añadirla a la lista sin mirar qué hace no arregla nada: solo
--     silencia la alarma.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(18);

CREATE TEMP TABLE lista_blanca (firma text PRIMARY KEY) ON COMMIT DROP;

INSERT INTO lista_blanca (firma) VALUES
  -- Las pantallas: lo que la app llama con .rpc() y la sesión del usuario
  ('crm.asignar_lead(uuid, uuid)'),
  ('crm.bandeja_contactos(text, text, boolean, timestamptz, uuid, int)'),
  ('crm.bot_vuelve_at(uuid)'),
  ('crm.cambiar_bot(uuid, boolean)'),
  ('crm.cerrar_oportunidad(uuid, text, text, uuid, text)'),
  ('crm.coincidencias(smallint, int, int, uuid, smallint)'),
  ('crm.completar_tarea(uuid)'),
  ('crm.encolar_envio(uuid, text, uuid, uuid)'),
  ('crm.inmuebles_para(uuid, smallint, int, boolean)'),
  ('crm.marcar_leido(uuid)'),
  ('crm.marcar_opt_out(uuid, text)'),
  ('crm.mi_dia(int, uuid)'),
  ('crm.mover_etapa(uuid, text, text)'),
  ('crm.reactivables(int, int, int)'),
  ('crm.reactivables_total(int)'),
  ('crm.render_plantilla(uuid, uuid, uuid, text)'),
  ('crm.responsable_de(uuid)'),
  ('crm.resumen_contacto(uuid)'),
  ('crm.tablero(int, text, uuid, boolean, text)'),
  ('crm.variables_disponibles()'),
  ('crm.ventana_whatsapp(uuid)'),
  ('crm.zonas()'),

  -- Lo que esas pantallas llaman por dentro. Corre con el rol de quien
  -- llama: cerrarlo rompe la pantalla, aunque la app no lo nombre nunca
  ('crm.bot_atendido_desde(uuid, timestamptz)'),
  ('crm.frescura(timestamptz)'),
  ('crm.igual_zona(text, text)'),
  ('crm.normaliza_zonas(text[])'),
  ('crm.puede_escribir_libre(uuid)'),
  ('crm.publico_marketing(int, int)'),
  ('crm.puntaje(text, text[], text[], text, numeric, smallint, text, text, text, text, numeric, int, text)'),
  ('crm.ventana_escalamiento()'),
  ('crm.ventana_relevo()'),
  ('crm.ventana_silencio_escalamiento()'),

  -- Lo que Postgres evalúa con el rol del usuario sin que nadie lo llame
  ('crm.variables_desconocidas(text)'),       -- el CHECK de crm.plantillas
  ('crm.normalizar_telefono(text)'),          -- la vista crm.v_citas
  ('crm.estado_sincronizacion(crm.lineas)'),  -- columna calculada de crm.lineas

  -- Puras: entra texto, sale texto, no leen ninguna tabla
  ('crm.calidad_nombre(text)'),
  ('crm.mejor_nombre(text, text)'),
  ('crm.identidades_de_conversacion(text, text, text)'),

  -- SECURITY INVOKER sin pantalla todavía: manda la RLS
  ('crm.marcar_envio_visto(uuid)'),
  ('crm.reabrir_oportunidad(uuid)'),
  ('crm.tiempo_en_estado(text)');

-- Un lead de BETA, escalado hace una hora: el bot está callado a
-- propósito, porque la persona pidió hablar con alguien.
INSERT INTO crm.contactos
  (id, inmobiliaria_id, nombre, telefono_e164,
   bot_activo, bot_motivo, bot_cambiado_at)
VALUES ('bbbb0027-0000-0000-0000-000000000001',
        '22222222-2222-2222-2222-222222222222',
        'Lead escalado de Beta', '+573009270001',
        false, 'escalamiento', now() - interval '1 hour');

-- Y uno de ALFA, para editarlo desde su propia sesión.
INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164)
VALUES ('aaaa0027-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'Contacto de Alfa', '+573009270002');

-- =====================================================================
-- 1 · La lista blanca
-- =====================================================================
SELECT is_empty(
  $$SELECT p.oid::regprocedure::text
      FROM pg_proc p
     WHERE p.pronamespace = 'crm'::regnamespace
       AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
       AND p.oid NOT IN (SELECT to_regprocedure(firma)::oid FROM lista_blanca
                          WHERE to_regprocedure(firma) IS NOT NULL)$$,
  'Toda función de crm que authenticated puede ejecutar está en la lista blanca: una nueva sin decidir tumba esta prueba'
);

SELECT is_empty(
  $$SELECT firma FROM lista_blanca
     WHERE to_regprocedure(firma) IS NULL
        OR NOT has_function_privilege('authenticated', to_regprocedure(firma), 'EXECUTE')$$,
  'Y nada de la lista quedó cerrado por error ni con la firma mal escrita: cada pantalla puede llamar lo suyo'
);

SELECT is_empty(
  $$SELECT p.oid::regprocedure::text
      FROM pg_proc p
     WHERE p.pronamespace = 'crm'::regnamespace
       AND p.prosecdef
       AND has_function_privilege('authenticated', p.oid, 'EXECUTE')$$,
  'Ninguna función SECURITY DEFINER es ejecutable por authenticated: saltarse la RLS no se hace desde el navegador'
);

-- grantee 0 es PUBLIC.
SELECT is_empty(
  $$SELECT pg_get_userbyid(d.defaclrole)
      FROM pg_default_acl d, aclexplode(d.defaclacl) a
     WHERE d.defaclnamespace = 'crm'::regnamespace
       AND d.defaclobjtype = 'f'
       AND (a.grantee = 'authenticated'::regrole OR a.grantee = 0)$$,
  'El privilegio por defecto del esquema ya no le regala EXECUTE a authenticated'
);

-- =====================================================================
-- 2 · Lo cerrado, llamado de verdad desde una sesión de Alfa
--
-- Se llama igual que lo haría PostgREST: con el rol y el JWT de un
-- usuario. Una aserción sobre el catálogo dice qué DEBERÍA pasar; esto
-- dice qué pasa.
-- =====================================================================
SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$SELECT crm.reactivar_bots()$$,
  '42501',
  NULL,
  'La función del cron no se llama desde una sesión: despertaría el bot en los leads escalados de TODAS las inmobiliarias'
);

SELECT throws_ok(
  $$SELECT crm.resolver_contacto('22222222-2222-2222-2222-222222222222',
                                 '[{"tipo":"telefono_e164","valor":"+573009270003"}]',
                                 'Sembrado desde Alfa')$$,
  '42501',
  NULL,
  'Ni crear personas en el CRM de otra inmobiliaria pasándole su id'
);

SELECT throws_ok(
  $$SELECT crm.bot_puede_responder('22222222-2222-2222-2222-222222222222', '+573009270001')$$,
  '42501',
  NULL,
  'El contrato del agente es de la plataforma: desde el navegador no se pregunta por los leads de otro'
);

SELECT throws_ok(
  $$SELECT * FROM crm.linea_por_numero('100000000000001')$$,
  '42501',
  NULL,
  'Ni se traduce un número de WhatsApp a su inmobiliaria'
);

SELECT throws_ok(
  $$SELECT crm.registrar_estado_envio('wamid.inventado', 'fallido')$$,
  '42501',
  NULL,
  'Ni se marca como fallido un envío ajeno: los acuses los anota el webhook de Meta'
);

RESET ROLE;

SELECT is(
  (SELECT bot_activo FROM crm.contactos
    WHERE id = 'bbbb0027-0000-0000-0000-000000000001'),
  false,
  'Y el lead escalado de Beta sigue con el bot callado, que es lo que pidió'
);

-- =====================================================================
-- 3 · Las pantallas siguen funcionando
--
-- La lista blanca dice que authenticated PUEDE llamar cada función, pero
-- no que la función llegue viva al final: una INVOKER que por dentro
-- llama a una función cerrada revienta igual. Así cayó clientes_para,
-- que se apoyaba en puntaje_match.
--
-- Se llama cada función abierta con NULL en todos sus argumentos y se
-- deshace cada llamada. Con NULL, lo esperable es que se queje de otra
-- cosa; la única queja que importa aquí es la de permisos. En una
-- función SQL, Postgres comprueba EXECUTE de todo lo que llama al
-- arrancar, aunque no haya filas. En una plpgsql, solo en la rama que
-- llega a correr.
-- =====================================================================
SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $prueba$
    DO $bloque$
    DECLARE
      f       record;
      v_rotas text[] := '{}';
    BEGIN
      FOR f IN
        SELECT p.oid::regprocedure AS firma,
               format('SELECT * FROM %s(%s)', p.oid::regproc,
                      (SELECT string_agg('NULL::' || format_type(t.tipo, NULL), ', '
                                         ORDER BY t.n)
                         FROM unnest(p.proargtypes::oid[]) WITH ORDINALITY AS t(tipo, n))
               ) AS llamada
          FROM pg_proc p
         WHERE p.pronamespace = 'crm'::regnamespace
           AND p.prorettype <> 'trigger'::regtype
           AND has_function_privilege(p.oid, 'EXECUTE')
      LOOP
        BEGIN
          EXECUTE f.llamada;
          RAISE EXCEPTION 'deshacer';   -- que ninguna llamada deje rastro
        EXCEPTION
          WHEN insufficient_privilege THEN
            v_rotas := v_rotas || (f.firma::text || ': ' || SQLERRM);
          WHEN OTHERS THEN
            NULL;
        END;
      END LOOP;

      IF cardinality(v_rotas) > 0 THEN
        RAISE EXCEPTION 'Abiertas pero rotas por permisos: %',
          array_to_string(v_rotas, '; ');
      END IF;
    END $bloque$;
  $prueba$,
  'Ninguna función abierta revienta por permisos al llamarla como un usuario de verdad'
);

-- Un trigger no pide EXECUTE a quien lo dispara: tocar_updated_at ya no
-- la puede ejecutar authenticated y aun así pisa la fecha que se le pasa.
UPDATE crm.contactos
   SET updated_at = '2000-01-01'
 WHERE id = 'aaaa0027-0000-0000-0000-000000000001';

RESET ROLE;

SELECT ok(
  (SELECT updated_at FROM crm.contactos
    WHERE id = 'aaaa0027-0000-0000-0000-000000000001') > '2000-01-02',
  'Los triggers se siguen disparando para authenticated aunque su función esté cerrada'
);

-- =====================================================================
-- 4 · Los de siempre siguen pudiendo
-- =====================================================================
SELECT is_empty(
  $$SELECT p.oid::regprocedure::text
      FROM pg_proc p
     WHERE p.pronamespace = 'crm'::regnamespace
       AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE')$$,
  'service_role conserva todo: es el servidor de la plataforma'
);

-- Los crones corren como el rol que tengan registrado en cron.job. Se
-- lee de ahí, y no se da por hecho que sea postgres.
SELECT is_empty(
  $$SELECT j.jobname || ' (' || j.username || ')'
      FROM cron.job j
     WHERE j.jobname LIKE 'crm%'
       AND j.command ~ 'crm\.[a-z_]+\('
       AND NOT EXISTS (
         SELECT 1 FROM pg_proc p
          WHERE p.pronamespace = 'crm'::regnamespace
            AND p.proname = substring(j.command FROM 'crm\.([a-z_]+)\(')
            AND has_function_privilege(j.username, p.oid, 'EXECUTE'))$$,
  'Cada cron del CRM puede ejecutar lo que tiene agendado, con el rol con el que corre'
);

-- Los tres contratos de la plataforma, llamados como los llama ella.
SET LOCAL ROLE service_role;

SELECT is(
  crm.bot_puede_responder('11111111-1111-1111-1111-111111111111', '+573009279999'),
  true,
  'La plataforma sigue preguntando si el bot puede contestar: un teléfono desconocido es sí'
);

SELECT is_empty(
  $$SELECT * FROM crm.linea_por_numero('000000000000000')$$,
  'Y sigue traduciendo números de WhatsApp: uno sin línea no devuelve nada, en vez de un error de permisos'
);

SELECT is(
  crm.registrar_estado_envio('wamid.que-nadie-mando', 'entregado'),
  false,
  'Y sigue anotando los acuses de Meta: uno de un mensaje desconocido no toca nada'
);

RESET ROLE;

SELECT ok(
  NOT has_schema_privilege('anon', 'crm', 'USAGE'),
  'anon no alcanza el esquema: lo que siga concedido a PUBLIC no le llega'
);

SELECT * FROM finish();
ROLLBACK;
