-- =====================================================================
-- Las líneas de WhatsApp, y las reglas que impiden configurarlas mal.
--
-- Esta pantalla se llena UNA vez, el día que Meta devuelva los
-- identificadores, y un error ahí no se nota: el webhook descarta los
-- mensajes en silencio. Por eso las garantías van en la base.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(7);

DELETE FROM crm.lineas;

INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, telefono_e164, nombre)
VALUES ('11111111-1111-1111-1111-111111111111', 'comercial',
        '109876543210987', '+573001111111', 'Comercial');

SELECT is(
  (SELECT l.embudo FROM crm.linea_por_numero('109876543210987') l),
  'comercial',
  'El webhook traduce un phone_number_id a su embudo'
);

SELECT ok(
  (SELECT l.bot_atiende FROM crm.linea_por_numero('109876543210987') l),
  'Y le dice que en comercial el bot SÍ contesta'
);

-- --- Una línea activa por embudo -------------------------------------
-- Dos dejarían sin respuesta la pregunta "¿por cuál le escribo?".
SELECT throws_ok(
  $$INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre)
    VALUES ('11111111-1111-1111-1111-111111111111', 'comercial',
            '222222222222222', 'Otra comercial')$$,
  '23505',
  NULL,
  'Dos líneas activas para el mismo embudo no caben'
);

-- --- Un número no puede alimentar dos embudos ------------------------
-- Es el error real al configurar: pegar el mismo id en dos fichas.
SELECT throws_ok(
  $$INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre)
    VALUES ('11111111-1111-1111-1111-111111111111', 'administrativa',
            '109876543210987', 'Administrativa')$$,
  '23505',
  NULL,
  'Y el mismo phone_number_id no puede estar en dos líneas'
);

-- --- Los otros embudos, y lo que dicen del bot -----------------------
INSERT INTO crm.lineas (inmobiliaria_id, embudo, wa_phone_number_id, nombre)
VALUES ('11111111-1111-1111-1111-111111111111', 'administrativa',
        '333333333333333', 'Administrativa');

SELECT ok(
  NOT (SELECT l.bot_atiende FROM crm.linea_por_numero('333333333333333') l),
  'En administrativa el bot NO contesta: el webhook lo sabe antes de despertarlo'
);

-- --- Un número desconocido no resuelve nada --------------------------
SELECT is(
  (SELECT count(*)::int FROM crm.linea_por_numero('000000000000000')),
  0,
  'Un número sin línea no devuelve nada, y el webhook lo registra en vez de adivinar'
);

-- --- Solo un admin configura el canal --------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM crm.lineas),
  2,
  'Un asesor VE las líneas —necesita saber por dónde entra cada cosa— pero conectarlas es de admin'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
