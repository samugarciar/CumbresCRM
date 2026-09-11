-- =====================================================================
-- HISTÓRICO SINTÉTICO — SOLO LOCAL.
--
-- Genera ~1.600 filas repartidas en las tres fuentes, con la MISMA FORMA
-- que tiene el histórico real de producción (medido el 11 sep 2026):
--
--   · 710 conversaciones con teléfono bueno
--   · 225 conversaciones con un valor de 8 dígitos que NO es teléfono
--     (el caso real de las personas sin número utilizable)
--   · 513 citas y 96 solicitudes, con solapamiento deliberado
--
-- Ojo: `telefono` es NOT NULL en agente_comercial_conversaciones, y
-- `cliente_telefono` lo es en citas y solicitudes. Por eso en producción
-- las filas problemáticas traen un valor basura en vez de estar vacías:
-- el origen está OBLIGADO a escribir algo. El fixture lo reproduce igual,
-- con cadena vacía donde no hay dato.
--
-- PARA QUÉ SIRVE
--   1. Construir la interfaz de la fase 1-C contra una bandeja con
--      volumen real, no con tres filas de juguete.
--   2. Ver cuánto tarda el backfill de verdad antes de correrlo contra
--      producción.
--
-- Es reproducible, que es algo que un staging con datos reales no da: si
-- alguien encuentra un caso raro, lo añade aquí y queda para siempre.
--
--     npm run db:reset          # base limpia
--     npm run db:fixture        # carga este archivo
--     psql … -c "SELECT crm.backfill('11111111-1111-1111-1111-111111111111');"
--
-- ⚠️ NO corras `npm run db:test` con el fixture cargado: varias pruebas
-- cuentan filas exactas ("Alfa ve 1 cita") y aquí hay 515. Resetea antes.
-- =====================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.inmobiliarias
                  WHERE id = '11111111-1111-1111-1111-111111111111') THEN
    RAISE EXCEPTION 'Esto es solo para la base LOCAL: no encuentro la inmobiliaria de prueba del seed. Aborto para no tocar datos reales.';
  END IF;
END $$;

-- Los triggers se apagan a propósito: este fixture reproduce el histórico
-- que YA existía antes de que hubiera proyección, que es justo el caso que
-- el backfill tiene que resolver.
ALTER TABLE public.agente_comercial_mensajes DISABLE TRIGGER crm_proyectar_mensaje;
ALTER TABLE public.citas                     DISABLE TRIGGER crm_proyectar_cita;
ALTER TABLE public.solicitudes_apertura      DISABLE TRIGGER crm_proyectar_solicitud;

-- ---------------------------------------------------------------------
-- 0. Nombres con la forma REAL de los datos
--
-- El nombre de una conversación de WhatsApp es el nombre de PERFIL que la
-- persona se puso. Medido sobre producción: ~33% tienen forma de "Nombre
-- Apellido", ~53% son una sola palabra y ~14% traen emoji. Kommo muestra
-- exactamente lo mismo, porque es lo único que manda la API.
--
-- Los nombres de citas y solicitudes sí son completos: ahí el agente le
-- PREGUNTA el nombre al cliente. Esa diferencia es la que justifica
-- crm.mejor_nombre, y el fixture la reproduce para poder verla.
--
-- Un fixture que no se parece a la realidad hace juzgar mal la interfaz.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE _pila (i int, v text);
INSERT INTO _pila (i, v) VALUES
  (0,'Santiago'),(1,'María'),(2,'Juan José'),(3,'Laura'),(4,'Andrés'),
  (5,'Melianny'),(6,'Camilo'),(7,'Adriana'),(8,'Juliana'),(9,'Sebastián'),
  (10,'Valentina'),(11,'Jorge'),(12,'Daniela'),(13,'Mateo'),(14,'Carolina'),
  (15,'Esteban'),(16,'Paula'),(17,'Nicolás'),(18,'Sara'),(19,'Felipe');

CREATE TEMP TABLE _apellido (i int, v text);
INSERT INTO _apellido (i, v) VALUES
  (0,'Vanegas'),(1,'González'),(2,'Rojas'),(3,'Restrepo'),(4,'Arango'),
  (5,'Zapata'),(6,'Gómez'),(7,'Ospina'),(8,'Vélez'),(9,'Cardona'),
  (10,'Betancur'),(11,'Quintero'),(12,'Mesa'),(13,'Hoyos'),(14,'Agudelo');

CREATE TEMP TABLE _apodo (i int, v text);
INSERT INTO _apodo (i, v) VALUES
  (0,'Juli☺️'),(1,'MG❤️'),(2,'Melianny✨'),(3,'Sara🌸'),(4,'JLFR'),
  (5,'.'),(6,'Pipe🔥'),(7,'La Flaca'),(8,'Dani🌻'),(9,'💛');

-- ---------------------------------------------------------------------
-- 1. Conversaciones de WhatsApp
-- ---------------------------------------------------------------------
INSERT INTO public.agente_comercial_conversaciones
  (id, inmobiliaria_id, telefono, cliente_nombre, kommo_lead_id, kommo_contact_id, created_at)
SELECT
  gen_random_uuid(),
  '11111111-1111-1111-1111-111111111111',
  CASE
    WHEN i <= 710 THEN '3' || lpad(i::text, 9, '0')          -- teléfono bueno
    ELSE (49968779 + (i - 710) * 10000)::text                -- el valor que no es teléfono
  END,
  CASE
    -- ~14%: apodo o emoji, tal cual llega de WhatsApp
    WHEN i % 7 = 0 THEN (SELECT v FROM _apodo WHERE i = (i_ext % 10))
    -- ~33%: nombre y apellido
    WHEN i % 3 = 0 THEN (SELECT v FROM _pila WHERE i = (i_ext % 20)) || ' ' ||
                        (SELECT v FROM _apellido WHERE i = (i_ext % 15))
    -- el resto: una sola palabra
    ELSE (SELECT v FROM _pila WHERE i = (i_ext % 20))
  END,
  (51000000 + i)::text,
  (77000000 + i)::text,
  now() - ((935 - i) || ' hours')::interval
FROM generate_series(1, 935) i_ext
CROSS JOIN LATERAL (SELECT i_ext AS i) alias
ON CONFLICT DO NOTHING;

-- Entre 1 y 6 mensajes por conversación, alternando cliente y agente.
INSERT INTO public.agente_comercial_mensajes (conversacion_id, rol, contenido, created_at)
SELECT c.id,
       CASE WHEN m % 2 = 1 THEN 'usuario' ELSE 'agente' END,
       CASE WHEN m % 2 = 1 THEN 'Mensaje ' || m || ' del cliente'
            ELSE 'Respuesta ' || m || ' del asistente' END,
       c.created_at + (m || ' minutes')::interval
  FROM public.agente_comercial_conversaciones c
 CROSS JOIN LATERAL generate_series(1, 1 + (abs(hashtext(c.id::text)) % 6)) m
 WHERE c.inmobiliaria_id = '11111111-1111-1111-1111-111111111111'
   -- No se filtra por nombre: los nombres ahora son realistas y variados,
   -- así que no sirven de marca. Se salta lo que ya tenga mensajes, que
   -- además hace el fixture repetible sin duplicar.
   AND NOT EXISTS (
     SELECT 1 FROM public.agente_comercial_mensajes m
      WHERE m.conversacion_id = c.id);

-- ---------------------------------------------------------------------
-- 2. Franjas y citas
--    Los teléfonos se toman del rango 600-1019: se solapan con las
--    conversaciones en 600-710 (111 personas compartidas).
-- ---------------------------------------------------------------------
INSERT INTO public.franjas_horarias
  (id, inmobiliaria_id, inmueble_id, asesor_id, fecha, hora_inicio, hora_fin, creado_por)
SELECT
  gen_random_uuid(),
  '11111111-1111-1111-1111-111111111111',
  'a1111111-1111-1111-1111-111111111111',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  current_date + n, '08:00', '18:00',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
FROM generate_series(1, 30) n;

INSERT INTO public.citas
  (inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono, estado, created_at)
SELECT
  '11111111-1111-1111-1111-111111111111',
  f.id,
  'a1111111-1111-1111-1111-111111111111',
  f.fecha,
  ('08:00'::time + ((i % 19) * interval '30 minutes')),
  ('08:30'::time + ((i % 19) * interval '30 minutes')),
  (SELECT v FROM _pila WHERE i = ((600 + (i_ext % 420)) % 20)) || ' ' ||
  (SELECT v FROM _apellido WHERE i = ((600 + (i_ext % 420)) % 15)),
  CASE
    WHEN i % 128 = 0 THEN ''                                    -- vino vacío
    WHEN i % 3 = 0 THEN '+57 3' || lpad((600 + (i % 420))::text, 9, '0')
    WHEN i % 3 = 1 THEN '573' || lpad((600 + (i % 420))::text, 9, '0')
    ELSE '3' || lpad((600 + (i % 420))::text, 9, '0')            -- el mismo, escrito distinto
  END,
  CASE WHEN i % 7 = 0 THEN 'completada'
       WHEN i % 11 = 0 THEN 'cancelada'
       ELSE 'agendada' END,
  now() - ((513 - i) || ' hours')::interval
FROM generate_series(1, 513) i_ext
CROSS JOIN LATERAL (SELECT i_ext AS i) alias
JOIN LATERAL (
  SELECT id, fecha FROM public.franjas_horarias
   WHERE inmobiliaria_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY fecha OFFSET (i % 30) LIMIT 1
) f ON true;

-- ---------------------------------------------------------------------
-- 3. Solicitudes de apertura (rango 690-761: se solapan con ambas)
-- ---------------------------------------------------------------------
INSERT INTO public.solicitudes_apertura
  (inmobiliaria_id, inmueble_id, fecha, hora_inicio, hora_fin,
   cliente_nombre, cliente_telefono, created_at)
SELECT
  '11111111-1111-1111-1111-111111111111',
  'a1111111-1111-1111-1111-111111111111',
  current_date + (i % 20) + 1,
  '19:00', '20:00',
  (SELECT v FROM _pila WHERE i = ((690 + (i_ext % 72)) % 20)) || ' ' ||
  (SELECT v FROM _apellido WHERE i = ((690 + (i_ext % 72)) % 15)),
  '3' || lpad((690 + (i % 72))::text, 9, '0'),
  now() - ((96 - i) || ' hours')::interval
FROM generate_series(1, 96) i_ext
CROSS JOIN LATERAL (SELECT i_ext AS i) alias;

ALTER TABLE public.agente_comercial_mensajes ENABLE TRIGGER crm_proyectar_mensaje;
ALTER TABLE public.citas                     ENABLE TRIGGER crm_proyectar_cita;
ALTER TABLE public.solicitudes_apertura      ENABLE TRIGGER crm_proyectar_solicitud;

DROP TABLE _pila, _apellido, _apodo;

SELECT 'fixture cargado. Ahora: SELECT crm.backfill(''11111111-1111-1111-1111-111111111111'');' AS siguiente;
