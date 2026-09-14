-- =====================================================================
-- La lectura del tablero.
--
-- Lo que se mide: que cada columna traiga las primeras N pero diga
-- cuántas hay de verdad, que lo que espera a una persona salga ARRIBA,
-- que "esperando" deje de serlo en cuanto alguien abre la ficha, y que
-- nada de esto se filtre entre inmobiliarias.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(19);

DELETE FROM crm.contactos;

-- Cinco personas en la misma etapa, para poder probar el límite.
INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164)
SELECT ('ff0000' || lpad(i::text, 2, '0') || '-0000-0000-0000-00000000000' || i)::uuid,
       '11111111-1111-1111-1111-111111111111',
       'Persona ' || i,
       '+57300111000' || i
FROM generate_series(1, 5) i;

INSERT INTO crm.actividades
  (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, metadata)
SELECT '11111111-1111-1111-1111-111111111111', 'mensaje_entrante', 'humano',
       c.id, 'Hola', now() - (i || ' hours')::interval,
       jsonb_build_object('origen_tabla', 't', 'origen_id', 'tab' || i)
FROM generate_series(1, 5) i
JOIN crm.contactos c
  ON c.id = ('ff0000' || lpad(i::text, 2, '0') || '-0000-0000-0000-00000000000' || i)::uuid;

-- La persona 3 escaló hace media hora y nadie la ha mirado.
UPDATE crm.oportunidades
   SET escalado_at = now() - interval '30 minutes'
 WHERE contacto_id = 'ff000003-0000-0000-0000-000000000003';

-- La persona 4 escaló hace CINCO DÍAS y tampoco la ha mirado nadie. En
-- producción el 82% de los escalamientos son así: viejos y desatendidos.
-- Si eso se pinta de rojo, el rojo deja de significar nada.
UPDATE crm.oportunidades
   SET escalado_at = now() - interval '5 days'
 WHERE contacto_id = 'ff000004-0000-0000-0000-000000000004';

-- La persona 5 tiene zona; sirve para el filtro.
UPDATE crm.oportunidades SET zona = 'Bello'
 WHERE contacto_id = 'ff000005-0000-0000-0000-000000000005';

SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

-- --- El límite por columna -------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM crm.tablero(2)),
  2,
  'Con límite 2 devuelve 2 tarjetas, no las cinco'
);

SELECT is(
  (SELECT max(total_en_etapa) FROM crm.tablero(2)),
  5::bigint,
  'Pero dice que hay 5: el total no depende del límite'
);

SELECT is(
  (SELECT count(*)::int FROM crm.tablero(40)),
  5,
  'Con sitio de sobra devuelve las cinco'
);

-- --- LA AFIRMACIÓN QUE MÁS IMPORTA -----------------------------------
-- Quien pidió una persona y sigue sin que nadie mire va ARRIBA. Si no,
-- el tablero es una lista y no una herramienta de trabajo.
SELECT is(
  (SELECT contacto_id FROM crm.tablero(40) LIMIT 1),
  'ff000003-0000-0000-0000-000000000003'::uuid,
  'La que espera a una persona sale primera, por encima de la más reciente'
);

SELECT ok(
  (SELECT escalado_sin_atender FROM crm.tablero(40)
    WHERE contacto_id = 'ff000003-0000-0000-0000-000000000003'),
  'Y viene marcada como que nadie la ha atendido'
);

SELECT ok(
  NOT (SELECT bool_or(COALESCE(escalado_sin_atender, false)) FROM crm.tablero(40)
        WHERE contacto_id <> 'ff000003-0000-0000-0000-000000000003'),
  'Ninguna otra la enciende: o no escalaron, o su escalada es vieja'
);

-- --- LA REGLA QUE EVITA QUE LA ALERTA SE VUELVA RUIDO ----------------
-- Una escalada de hace cinco días que nadie atendió NO es una tarea
-- pendiente: es historia. Sigue visible, pero no grita.
SELECT ok(
  NOT (SELECT escalado_sin_atender FROM crm.tablero(40)
        WHERE contacto_id = 'ff000004-0000-0000-0000-000000000004'),
  'Una escalada vieja y desatendida NO enciende la alerta'
);

SELECT ok(
  NOT (SELECT escalado_atendido FROM crm.tablero(40)
        WHERE contacto_id = 'ff000004-0000-0000-0000-000000000004'),
  'Pero tampoco se dice que fue atendida, porque no lo fue'
);

SELECT ok(
  (SELECT escalado_at IS NOT NULL FROM crm.tablero(40)
    WHERE contacto_id = 'ff000004-0000-0000-0000-000000000004'),
  'La fecha se conserva: la tarjeta puede contarlo en gris'
);

SELECT is(
  (SELECT contacto_id FROM crm.tablero(40) LIMIT 1),
  'ff000003-0000-0000-0000-000000000003'::uuid,
  'Y arriba sigue la reciente, no la vieja'
);

-- --- Abrir la ficha la atiende ---------------------------------------
-- "Atender" es que alguien del equipo abra la ficha después de la
-- escalada. No se mira si respondió por WhatsApp porque esa respuesta
-- la manda el asesor desde su teléfono y no pasa por esta base.
SELECT lives_ok(
  $$SELECT crm.marcar_leido('ff000003-0000-0000-0000-000000000003')$$,
  'Un asesor abre la ficha'
);

SELECT ok(
  NOT (SELECT escalado_sin_atender FROM crm.tablero(40)
        WHERE contacto_id = 'ff000003-0000-0000-0000-000000000003'),
  'Y deja de estar esperando: alguien llegó'
);

SELECT ok(
  (SELECT escalado_atendido FROM crm.tablero(40)
    WHERE contacto_id = 'ff000003-0000-0000-0000-000000000003'),
  'Ahora sí se puede decir que fue atendida'
);

SELECT is(
  (SELECT escalado_at IS NOT NULL FROM crm.tablero(40)
    WHERE contacto_id = 'ff000003-0000-0000-0000-000000000003'),
  true,
  'La escalada no se borra: se atendió, pero pasó'
);

-- --- Filtros ----------------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM crm.tablero(40, 'Bello')),
  1,
  'El filtro de zona deja solo la de Bello'
);

SELECT is(
  (SELECT count(*)::int FROM crm.tablero(40, NULL, NULL, NULL, 'Persona 2')),
  1,
  'La búsqueda por nombre encuentra a una sola'
);

-- Ya nadie está esperando ni estancado, así que "lo que urge" vacía el
-- tablero. Es la respuesta correcta: no hay nada urgente.
SELECT is(
  (SELECT count(*)::int FROM crm.tablero(40, NULL, NULL, true)),
  0,
  'Con lo reciente atendido, "lo que urge" queda vacío: la vieja no urge'
);

-- --- Aislamiento ------------------------------------------------------
RESET ROLE;
SET LOCAL "request.jwt.claims" = '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM crm.tablero(40)),
  0,
  'Beta no ve ni una tarjeta de Alfa'
);

SELECT is(
  (SELECT count(*)::int FROM crm.zonas()),
  0,
  'Ni sus zonas'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
