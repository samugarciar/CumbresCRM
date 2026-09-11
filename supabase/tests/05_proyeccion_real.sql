-- =====================================================================
-- Los triggers de proyección REALES, no los de juguete.
--
-- 02_patron_proyeccion.sql demostró que la técnica funciona. Esta prueba
-- verifica que los triggers que de verdad están colgados de las tablas de
-- producción la aplican bien.
--
-- La afirmación que importa es la 7: con la proyección rota a propósito,
-- el mensaje del cliente SE GUARDA IGUAL. Si esta prueba se pone roja,
-- el agente comercial puede quedarse mudo en producción.
-- =====================================================================
BEGIN;
SET search_path TO extensions, public;

SELECT plan(9);

DELETE FROM crm.contactos;

-- ---------------------------------------------------------------------
-- Camino feliz: llega un mensaje de WhatsApp
-- ---------------------------------------------------------------------
INSERT INTO public.agente_comercial_conversaciones
  (id, inmobiliaria_id, telefono, cliente_nombre, kommo_lead_id)
VALUES
  ('d1111111-1111-1111-1111-111111111111',
   '11111111-1111-1111-1111-111111111111',
   '3007778899', 'Marcela Prueba', '51999888');

INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido)
VALUES ('d1111111-1111-1111-1111-111111111111', 'usuario',
        'Hola, vi el apartamento en Niquía');

SELECT is((SELECT count(*) FROM crm.contactos), 1::bigint,
  'Un mensaje entrante crea el contacto solo, sin que nadie lo pida');

SELECT is(
  (SELECT telefono_e164 FROM crm.contactos LIMIT 1),
  '+573007778899',
  'El teléfono llega normalizado, y el caché de la ficha queda al día');

SELECT is(
  (SELECT count(*) FROM crm.actividades WHERE tipo = 'mensaje_entrante'),
  1::bigint,
  'El mensaje aparece en el timeline');

SELECT is(
  (SELECT origen FROM crm.actividades WHERE tipo = 'mensaje_entrante'),
  'humano',
  'Marcado como humano: lo escribió el cliente, no el bot');

-- ---------------------------------------------------------------------
-- Una visita del mismo teléfono NO debe crear una segunda persona
-- ---------------------------------------------------------------------
INSERT INTO public.citas
  (inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono)
VALUES
  ('11111111-1111-1111-1111-111111111111',
   'a3333333-3333-3333-3333-333333333333',
   'a1111111-1111-1111-1111-111111111111',
   current_date + 1, '10:00', '10:30', 'Marcela Prueba', '+57 300 777 8899');

SELECT is((SELECT count(*) FROM crm.contactos), 1::bigint,
  'La visita se une a la MISMA persona: escrito distinto, mismo teléfono');

SELECT is(
  (SELECT count(DISTINCT tipo) FROM crm.actividades),
  2::bigint,
  'Y su timeline ya tiene dos clases de hecho: mensaje y visita');

-- ---------------------------------------------------------------------
-- LA PRUEBA QUE IMPORTA: con el CRM roto, el negocio sigue
--
-- Se rompe la resolución de identidad a propósito, que es por donde pasa
-- toda la proyección. Simula cualquier bug futuro del CRM.
-- ---------------------------------------------------------------------
-- Postgres no deja quitar los DEFAULT al reemplazar una función, así que
-- la firma tiene que repetirse completa, tal cual.
CREATE OR REPLACE FUNCTION crm.resolver_contacto(
  p_inmobiliaria_id uuid,
  p_identidades jsonb,
  p_nombre text DEFAULT NULL,
  p_origen text DEFAULT NULL,
  p_tipo_contacto text DEFAULT 'cliente',
  p_telefono_crudo text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $roto$
BEGIN
  RAISE EXCEPTION 'bug simulado del CRM';
END $roto$;

SELECT lives_ok(
  $$INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido)
    VALUES ('d1111111-1111-1111-1111-111111111111', 'usuario',
            '¿Sigue disponible?')$$,
  'Con la proyección rota, el mensaje del cliente SE GUARDA IGUAL'
);

SELECT is(
  (SELECT count(*) FROM public.agente_comercial_mensajes
    WHERE contenido = '¿Sigue disponible?'),
  1::bigint,
  'El mensaje está en la tabla del negocio: el agente no se quedó mudo');

SELECT is(
  (SELECT count(*) FROM crm.eventos
    WHERE estado = 'fallido' AND tabla_origen = 'agente_comercial_mensajes'),
  1::bigint,
  'Y el fallo quedó anotado en crm.eventos para reintentarlo, no perdido');

SELECT * FROM finish();
ROLLBACK;
