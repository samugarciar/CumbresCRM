-- =====================================================================
-- Requerimientos y cruce contra el catálogo.
--
-- Lo que se mide: que el puntaje premie lo que la persona pidió y SOLO
-- eso, que descalifique lo que nunca hay que enseñar, que del inmueble
-- se llegue a las personas —el criterio de la fase— y que quien tiene la
-- oportunidad cerrada siga apareciendo, porque en eso consiste reactivar.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(16);

DELETE FROM crm.contactos;

-- El catálogo de la prueba. El del seed más tres, para poder distinguir
-- barrio exacto de misma ciudad, y dentro de presupuesto de fuera.
INSERT INTO public.inmuebles
  (id, inmobiliaria_id, asesor_id, titulo, direccion, ciudad, barrio,
   habitaciones, banos, precio, tipo_transaccion, tipo_inmueble, estado)
VALUES
  ('11110001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Apto Niquía justo', 'Cra 1',
   'Bello', 'Niquia', 3, 2, 1400000, 'arriendo', 'apartamento', 'disponible'),
  ('11110002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Apto otro barrio', 'Cra 2',
   'Bello', 'Madera', 3, 2, 1400000, 'arriendo', 'apartamento', 'disponible'),
  ('11110003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Apto carísimo', 'Cra 3',
   'Bello', 'Niquia', 3, 2, 4000000, 'arriendo', 'apartamento', 'disponible'),
  ('11110004-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Apto en VENTA', 'Cra 4',
   'Bello', 'Niquia', 3, 2, 300000000, 'venta', 'apartamento', 'disponible');

INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164)
VALUES
  ('bb000001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Pide Niquía', '+573001110001'),
  ('bb000002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'Dijo poco', '+573001110002'),
  ('bb000003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
   'Ya cerrada', '+573001110003');

-- Requerimiento completo: apartamento en Niquía, 3 hab, hasta 1,5M.
INSERT INTO crm.requerimientos
  (id, inmobiliaria_id, contacto_id, ciudad, barrios, tipo_inmueble,
   tipo_transaccion, precio_max, habitaciones_min)
VALUES ('44440001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'bb000001-0000-0000-0000-000000000001',
        'Bello', ARRAY['Niquía'], ARRAY['apartamento'], 'arriendo', 1500000, 3);

-- Requerimiento escueto: solo dijo "apartamento en Bello". La mitad de
-- la gente real habla así.
INSERT INTO crm.requerimientos
  (id, inmobiliaria_id, contacto_id, ciudad, tipo_inmueble, tipo_transaccion)
VALUES ('44440002-0000-0000-0000-000000000002',
        '11111111-1111-1111-1111-111111111111',
        'bb000002-0000-0000-0000-000000000002',
        'Bello', ARRAY['apartamento'], 'arriendo');

-- =====================================================================
-- El puntaje
-- =====================================================================
SELECT is(
  crm.puntaje_match('44440001-0000-0000-0000-000000000001',
                    '11110001-0000-0000-0000-000000000001'),
  100::smallint,
  'Cumple todo lo que pidió: 100'
);

-- LA TILDE NO DECIDE UN NEGOCIO: el catálogo dice "Niquia" y la persona
-- pidió "Niquía". Sin normalizar, ese acento cuesta una coincidencia.
SELECT ok(
  crm.puntaje_match('44440001-0000-0000-0000-000000000001',
                    '11110001-0000-0000-0000-000000000001') = 100,
  'Y "Niquía" encuentra "Niquia": la tilde no cuesta un negocio'
);

SELECT ok(
  crm.puntaje_match('44440001-0000-0000-0000-000000000001',
                    '11110002-0000-0000-0000-000000000002')
  < crm.puntaje_match('44440001-0000-0000-0000-000000000001',
                      '11110001-0000-0000-0000-000000000001'),
  'Otro barrio de la misma ciudad puntúa menos que el barrio pedido'
);

SELECT ok(
  crm.puntaje_match('44440001-0000-0000-0000-000000000001',
                    '11110002-0000-0000-0000-000000000002') > 0,
  'Pero no cero: "no es Niquía pero es Bello" es una conversación que se puede tener'
);

-- --- Descalificaciones ------------------------------------------------
SELECT is(
  crm.puntaje_match('44440001-0000-0000-0000-000000000001',
                    '11110004-0000-0000-0000-000000000004'),
  NULL,
  'Una VENTA no se le enseña a quien busca arriendo, por bien que encaje'
);

SELECT is(
  crm.puntaje_match('44440001-0000-0000-0000-000000000001',
                    '11110003-0000-0000-0000-000000000003'),
  NULL,
  'Ni uno de 4M a quien dijo hasta 1,5M: eso no es estirar, es otro negocio'
);

-- --- Solo se puntúa lo que se pidió -----------------------------------
-- Quien solo dijo "apartamento en Bello" no puede salir penalizado por
-- haberse callado el presupuesto. Si el modelo exigiera todos los
-- campos, describiría un cliente que no existe.
SELECT is(
  crm.puntaje_match('44440002-0000-0000-0000-000000000002',
                    '11110003-0000-0000-0000-000000000003'),
  100::smallint,
  'Quien solo pidió tipo y ciudad obtiene 100 con lo que cumple esos dos'
);

-- =====================================================================
-- EL CRITERIO DE LA FASE: del inmueble a las personas
-- =====================================================================
SELECT is(
  (SELECT count(*)::int FROM crm.clientes_para('11110001-0000-0000-0000-000000000001')),
  2,
  'Entra el apto de Niquía y salen las dos personas que encajan'
);

-- Las dos sacan 100: una cumple los 2 campos que pidió y la otra los 4.
-- Encajan igual de bien, pero de la segunda sabemos mucho más, y ésa es
-- la que el asesor quiere arriba.
SELECT is(
  (SELECT contacto_id FROM crm.clientes_para('11110001-0000-0000-0000-000000000001') LIMIT 1),
  'bb000001-0000-0000-0000-000000000001'::uuid,
  'Empatadas a 100, arriba va la que pidió MÁS cosas: la coincidencia informada'
);

SELECT ok(
  (SELECT especificidad FROM crm.clientes_para('11110001-0000-0000-0000-000000000001')
    WHERE contacto_id = 'bb000001-0000-0000-0000-000000000001')
  > (SELECT especificidad FROM crm.clientes_para('11110001-0000-0000-0000-000000000001')
      WHERE contacto_id = 'bb000002-0000-0000-0000-000000000002'),
  'Y la pantalla puede decir cuántas cosas cumple, no solo un porcentaje'
);

SELECT is(
  (SELECT pidio FROM crm.clientes_para('11110001-0000-0000-0000-000000000001')
    WHERE contacto_id = 'bb000001-0000-0000-0000-000000000001'),
  'apartamento, en Niquía, 3+ hab, hasta $1.500.000',
  'Con lo que pidió en una línea legible, no en un jsonb'
);

SELECT is(
  (SELECT count(*)::int FROM crm.clientes_para('11110004-0000-0000-0000-000000000004')),
  0,
  'Y el de venta no le sale a nadie que busque arriendo'
);

-- --- LA REACTIVACIÓN --------------------------------------------------
-- Alguien a quien cerramos hace meses SIGUE habiendo dicho qué quería.
-- Si el cruce solo mirara oportunidades abiertas, la bandeja de
-- reactivación —probablemente la fuente de ingreso más barata del
-- proyecto— sería imposible.
INSERT INTO crm.requerimientos
  (inmobiliaria_id, contacto_id, ciudad, barrios, tipo_inmueble, tipo_transaccion)
VALUES ('11111111-1111-1111-1111-111111111111',
        'bb000003-0000-0000-0000-000000000003',
        'Bello', ARRAY['Niquia'], ARRAY['apartamento'], 'arriendo');

INSERT INTO crm.oportunidades
  (inmobiliaria_id, contacto_id, etapa, estado, motivo_perdida, cerrada_at)
VALUES ('11111111-1111-1111-1111-111111111111',
        'bb000003-0000-0000-0000-000000000003',
        'contactado', 'perdida', 'no_responde', now() - interval '3 months');

SELECT is(
  (SELECT count(*)::int FROM crm.clientes_para('11110001-0000-0000-0000-000000000001')
    WHERE contacto_id = 'bb000003-0000-0000-0000-000000000003'),
  1,
  'Quien tiene la oportunidad CERRADA también aparece: en eso consiste reactivar'
);

SELECT is(
  (SELECT oportunidad_id FROM crm.clientes_para('11110001-0000-0000-0000-000000000001')
    WHERE contacto_id = 'bb000003-0000-0000-0000-000000000003'),
  NULL,
  'Sin oportunidad abierta, y la pantalla puede decirlo'
);

-- =====================================================================
-- El sentido contrario y el aislamiento
-- =====================================================================
SET LOCAL "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT ok(
  (SELECT count(*) FROM crm.inmuebles_para('bb000001-0000-0000-0000-000000000001')) >= 1,
  'Y desde la persona se llega a lo que le sirve hoy'
);

RESET ROLE;
SET LOCAL "request.jwt.claims" = '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}';
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM crm.requerimientos),
  0,
  'Beta no ve ni un requerimiento de Alfa'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
