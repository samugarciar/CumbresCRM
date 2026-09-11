-- =====================================================================
-- SEED — SOLO LOCAL. Nunca corre en producción ni en staging: `supabase db
-- reset` lo aplica sobre la base de Docker y nada más.
--
-- Siembra DOS inmobiliarias completas y ajenas entre sí. Dos, no una, a
-- propósito: el aislamiento entre inquilinos no se puede probar con un solo
-- inquilino, y esa es la prueba que más importa en este proyecto.
-- =====================================================================

-- pgTAP vive aquí y no en una migración, justamente para que no llegue a
-- producción. Las pruebas hacen `set search_path` para encontrarlo.
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

-- ---------------------------------------------------------------------
-- Identificadores fijos: las pruebas los referencian por nombre.
--   Alfa → 1111…  ·  Beta → 2222…
-- ---------------------------------------------------------------------

INSERT INTO public.inmobiliarias (id, nombre, nit) VALUES
  ('11111111-1111-1111-1111-111111111111', 'Inmobiliaria Alfa (prueba)', '900000001'),
  ('22222222-2222-2222-2222-222222222222', 'Inmobiliaria Beta (prueba)', '900000002')
ON CONFLICT (id) DO NOTHING;

-- Usuarios de autenticación. La contraseña de ambos es `prueba1234`.
-- Se hashea con bcrypt vía pgcrypto para que el login local funcione de
-- verdad, no solo la lectura de datos.
-- OJO con las columnas de token en '' y no en NULL: GoTrue las lee como
-- string de Go y revienta con "converting NULL to string is unsupported",
-- que se manifiesta como un 500 "Database error querying schema" al hacer
-- login. Cuesta encontrarlo porque el error no menciona la columna hasta
-- que se miran los logs del contenedor de auth.
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token,
  email_change_token_new, email_change_token_current, email_change,
  phone_change, phone_change_token, reauthentication_token
) VALUES
  (
    '00000000-0000-0000-0000-000000000000',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'authenticated', 'authenticated', 'alfa@prueba.local',
    extensions.crypt('prueba1234', extensions.gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}', '{}',
    '', '', '', '', '', '', '', ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'authenticated', 'authenticated', 'beta@prueba.local',
    extensions.crypt('prueba1234', extensions.gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}', '{}',
    '', '', '', '', '', '', '', ''
  )
ON CONFLICT (id) DO NOTHING;

-- GoTrue necesita la identidad además del usuario para permitir el login
-- por correo y contraseña.
INSERT INTO auth.identities (
  provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
) VALUES
  (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","email":"alfa@prueba.local","email_verified":true}',
    'email', now(), now(), now()
  ),
  (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","email":"beta@prueba.local","email_verified":true}',
    'email', now(), now(), now()
  )
ON CONFLICT (provider, provider_id) DO NOTHING;

INSERT INTO public.usuarios (id, inmobiliaria_id, nombre_completo, email, rol) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111',
   'Admin Alfa', 'alfa@prueba.local', 'admin'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222',
   'Admin Beta', 'beta@prueba.local', 'admin')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.inmuebles (
  id, inmobiliaria_id, asesor_id, titulo, direccion, ciudad, barrio,
  habitaciones, banos, precio, tipo_transaccion, tipo_inmueble, estado
) VALUES
  ('a1111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Apartamento Alfa 101', 'Calle 1 #1-01',
   'Bello', 'Niquía', 3, 2, 1200000, 'arriendo', 'apartamento', 'disponible'),
  ('b2222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222',
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Apartamento Beta 202', 'Calle 2 #2-02',
   'Medellín', 'Robledo', 2, 1, 950000, 'arriendo', 'apartamento', 'disponible')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.franjas_horarias (
  id, inmobiliaria_id, inmueble_id, asesor_id, fecha, hora_inicio, hora_fin, creado_por
) VALUES
  ('a3333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111',
   'a1111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   current_date + 1, '09:00', '11:00', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('b4444444-4444-4444-4444-444444444444', '22222222-2222-2222-2222-222222222222',
   'b2222222-2222-2222-2222-222222222222', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   current_date + 1, '14:00', '16:00', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.citas (
  id, inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
  cliente_nombre, cliente_telefono
) VALUES
  ('a5555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111',
   'a3333333-3333-3333-3333-333333333333', 'a1111111-1111-1111-1111-111111111111',
   current_date + 1, '09:00', '09:30', 'Cliente de Alfa', '+573000000001'),
  ('b6666666-6666-6666-6666-666666666666', '22222222-2222-2222-2222-222222222222',
   'b4444444-4444-4444-4444-444444444444', 'b2222222-2222-2222-2222-222222222222',
   current_date + 1, '14:00', '14:30', 'Cliente de Beta', '+573000000002')
ON CONFLICT (id) DO NOTHING;
