-- =====================================================================
-- FIXTURE DEMO POBLADO: Datos realistas para exploración en local
-- Inmobiliaria Alfa (11111111-1111-1111-1111-111111111111)
-- =====================================================================

DO $$
DECLARE
  v_inmo_id uuid := '11111111-1111-1111-1111-111111111111';
  v_admin_id uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_asesor_id uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';

  -- Inmuebles
  v_inm_laureles uuid := 'a1000000-0000-0000-0000-000000000001';
  v_inm_poblado uuid  := 'a1000000-0000-0000-0000-000000000002';
  v_inm_envigado uuid := 'a1000000-0000-0000-0000-000000000003';
  v_inm_cabanas uuid  := 'a1000000-0000-0000-0000-000000000004';
  v_inm_niquia uuid   := 'a1111111-1111-1111-1111-111111111111'; -- ya existe

  -- Franjas para citas
  v_franja_laureles uuid := 'f1000000-0000-0000-0000-000000000001';

  -- Contactos Comercial
  v_c_com_nuevo_1 uuid := gen_random_uuid();
  v_c_com_nuevo_2 uuid := gen_random_uuid();
  v_c_com_cont_1  uuid := gen_random_uuid();
  v_c_com_cont_2  uuid := gen_random_uuid();
  v_c_com_calif_1 uuid := gen_random_uuid();
  v_c_com_calif_2 uuid := gen_random_uuid();
  v_c_com_vis_ag  uuid := gen_random_uuid();
  v_c_com_vis_re  uuid := gen_random_uuid();
  v_c_com_estud   uuid := gen_random_uuid();

  -- Contactos Administrativa
  v_c_adm_dia_1   uuid := gen_random_uuid();
  v_c_adm_dia_2   uuid := gen_random_uuid();
  v_c_adm_mora    uuid := gen_random_uuid();
  v_c_adm_acuerdo uuid := gen_random_uuid();
  v_c_adm_mant    uuid := gen_random_uuid();
  v_c_adm_renov   uuid := gen_random_uuid();
  v_c_adm_term    uuid := gen_random_uuid();

  -- Contactos Captación
  v_c_cap_prosp_1 uuid := gen_random_uuid();
  v_c_cap_prosp_2 uuid := gen_random_uuid();
  v_c_cap_verif   uuid := gen_random_uuid();
  v_c_cap_aprob   uuid := gen_random_uuid();
  v_c_cap_cont    uuid := gen_random_uuid();
  v_c_cap_negoc   uuid := gen_random_uuid();
  v_c_cap_vis     uuid := gen_random_uuid();

BEGIN
  -- Desactivar temporalmente el trigger que recalcula pipeline en actividades para poblar con precisión
  ALTER TABLE crm.actividades DISABLE TRIGGER crm_pipeline_actividad;

  -- 1. Inmuebles adicionales para Alfa
  INSERT INTO public.inmuebles (
    id, inmobiliaria_id, asesor_id, titulo, descripcion, direccion, precio,
    tipo_transaccion, tipo_inmueble, estado, ciudad, barrio, habitaciones, banos
  ) VALUES
    (v_inm_laureles, v_inmo_id, v_asesor_id, 'Apartaestudio Moderno Laureles',
     'Excelente apartaestudio amoblado cerca a la 70 y Parque de Laureles. Todo incluido.',
     'Circular 4 # 71-15', 1800000, 'arriendo', 'apartamento', 'disponible', 'Medellín', 'Laureles', 1, 1),
    (v_inm_poblado, v_inmo_id, v_asesor_id, 'Apartamento Familiar El Poblado',
     'Amplio apartamento con vista panorámica, 3 alcobas con baño, unidad completa con piscina y gimnasio.',
     'Cra 34 # 7-80', 4200000, 'arriendo', 'apartamento', 'disponible', 'Medellín', 'El Poblado', 3, 3),
    (v_inm_envigado, v_inmo_id, v_asesor_id, 'Casa Campestre Envigado Jardines',
     'Hermosa casa en sector campestre y seguro. Acabados de lujo, jardín privado y 2 parqueaderos.',
     'Calle 38 Sur # 27A-45', 6500000, 'arriendo', 'casa', 'disponible', 'Envigado', 'Jardines', 4, 4),
    (v_inm_cabanas, v_inmo_id, v_asesor_id, 'Apartamento Bello Cabañas',
     'Apartamento bien ubicado a dos cuadras de la estación Madera. Balcón y cocina integral.',
     'Calle 27B # 55-20', 1400000, 'arriendo', 'apartamento', 'disponible', 'Bello', 'Cabañas', 2, 2)
  ON CONFLICT (id) DO UPDATE SET
    titulo = EXCLUDED.titulo,
    precio = EXCLUDED.precio,
    ciudad = EXCLUDED.ciudad,
    barrio = EXCLUDED.barrio;

  -- 2. Franja horaria para Laureles
  INSERT INTO public.franjas_horarias (id, inmobiliaria_id, asesor_id, inmueble_id, fecha, hora_inicio, hora_fin, creado_por)
  VALUES (v_franja_laureles, v_inmo_id, v_asesor_id, v_inm_laureles, current_date + 1, '09:00:00', '18:00:00', v_admin_id)
  ON CONFLICT (id) DO NOTHING;

  -- 3. Catálogo sincronizado
  INSERT INTO crm.catalogo (inmueble_id, inmobiliaria_id, estado, disponible_desde)
  VALUES
    (v_inm_niquia,   v_inmo_id, 'disponible', now() - interval '30 days'),
    (v_inm_laureles, v_inmo_id, 'disponible', now() - interval '15 days'),
    (v_inm_poblado,  v_inmo_id, 'disponible', now() - interval '10 days'),
    (v_inm_envigado, v_inmo_id, 'disponible', now() - interval '5 days'),
    (v_inm_cabanas,  v_inmo_id, 'disponible', now() - interval '2 days')
  ON CONFLICT (inmueble_id) DO UPDATE SET
    estado = EXCLUDED.estado,
    disponible_desde = EXCLUDED.disponible_desde;

  -- ===================================================================
  -- COMERCIAL
  -- ===================================================================

  -- COM 1: Nuevo
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, ultima_actividad_at)
  VALUES (v_c_com_nuevo_1, v_inmo_id, 'Mateo Zuluaga', '+573001234001', 'cliente', now() - interval '25 minutes');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado, zona)
  VALUES (v_inmo_id, v_c_com_nuevo_1, 'comercial', 'nuevo', 'abierta', 'Medellín');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, wa_phone_number_id)
  VALUES (v_inmo_id, 'mensaje_entrante', 'humano', v_c_com_nuevo_1, 'Buenas tardes, vi en Metrocuadrado el apartaestudio en Laureles. ¿Sigue disponible?', now() - interval '25 minutes', '3243516352');

  -- COM 2: Nuevo
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, ultima_actividad_at)
  VALUES (v_c_com_nuevo_2, v_inmo_id, 'Valentina Henao', '+573001234002', 'cliente', now() - interval '40 minutes');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado, zona)
  VALUES (v_inmo_id, v_c_com_nuevo_2, 'comercial', 'nuevo', 'abierta', 'Envigado');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, wa_phone_number_id)
  VALUES (v_inmo_id, 'mensaje_entrante', 'humano', v_c_com_nuevo_2, 'Hola! Busco casa o apto grande en Envigado para mi familia, somos 4 personas.', now() - interval '40 minutes', '3243516352');

  -- COM 3: Contactado
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, asesor_id, ultima_actividad_at)
  VALUES (v_c_com_cont_1, v_inmo_id, 'Santiago Mejía', '+573001234003', 'cliente', v_asesor_id, now() - interval '2 hours');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado, asesor_id, zona)
  VALUES (v_inmo_id, v_c_com_cont_1, 'comercial', 'contactado', 'abierta', v_asesor_id, 'Medellín');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, wa_phone_number_id)
  VALUES
    (v_inmo_id, 'mensaje_entrante', 'humano', v_c_com_cont_1, 'Hola, busco apto de 2 alcobas cerca al metro', now() - interval '3 hours', '3243516352'),
    (v_inmo_id, 'mensaje_saliente', 'humano', v_c_com_cont_1, 'Hola Santiago, con gusto te ayudo. ¿Qué presupuesto mensual tienes contemplado?', now() - interval '2 hours 30 minutes', '3243516352'),
    (v_inmo_id, 'mensaje_entrante', 'humano', v_c_com_cont_1, 'Hasta $2.500.000 con administración incluida.', now() - interval '2 hours', '3243516352');

  -- COM 4: Contactado
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, asesor_id, ultima_actividad_at)
  VALUES (v_c_com_cont_2, v_inmo_id, 'Carolina Duque', '+573001234004', 'cliente', v_asesor_id, now() - interval '4 hours');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado, asesor_id, zona)
  VALUES (v_inmo_id, v_c_com_cont_2, 'comercial', 'contactado', 'abierta', v_asesor_id, 'Bello');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, wa_phone_number_id)
  VALUES
    (v_inmo_id, 'mensaje_entrante', 'humano', v_c_com_cont_2, 'Buenas, me interesa el apto en Cabañas.', now() - interval '5 hours', '3243516352'),
    (v_inmo_id, 'mensaje_saliente', 'humano', v_c_com_cont_2, 'Hola Carolina, claro que sí. Te compartí el enlace con las fotos del inmueble.', now() - interval '4 hours', '3243516352');

  -- COM 5: Calificado
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, asesor_id, ultima_actividad_at)
  VALUES (v_c_com_calif_1, v_inmo_id, 'Andrés Felipe Morales', '+573001234005', 'cliente', v_asesor_id, now() - interval '1 day');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado, asesor_id, zona)
  VALUES (v_inmo_id, v_c_com_calif_1, 'comercial', 'calificado', 'abierta', v_asesor_id, 'Medellín');
  INSERT INTO crm.requerimientos (inmobiliaria_id, contacto_id, ciudad, barrios, tipo_inmueble, tipo_transaccion, precio_max, habitaciones_min, notas)
  VALUES (v_inmo_id, v_c_com_calif_1, 'Medellín', ARRAY['El Poblado'], ARRAY['apartamento'], 'arriendo', 4500000, 3, 'Cliente corporativo, busca piso alto con buena vista');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
  VALUES (v_inmo_id, 'nota', 'humano', v_c_com_calif_1, 'Calificado: ingresos demostrables superiores a 3 veces el canon, busca mudarse el 1 de noviembre.', now() - interval '1 day');

  -- COM 6: Calificado
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, asesor_id, ultima_actividad_at)
  VALUES (v_c_com_calif_2, v_inmo_id, 'Mariana Quintero', '+573001234006', 'cliente', v_asesor_id, now() - interval '18 hours');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado, asesor_id, zona)
  VALUES (v_inmo_id, v_c_com_calif_2, 'comercial', 'calificado', 'abierta', v_asesor_id, 'Medellín');
  INSERT INTO crm.requerimientos (inmobiliaria_id, contacto_id, ciudad, barrios, tipo_inmueble, tipo_transaccion, precio_max, habitaciones_min, notas)
  VALUES (v_inmo_id, v_c_com_calif_2, 'Medellín', ARRAY['Laureles'], ARRAY['apartamento'], 'arriendo', 2000000, 1, 'Busca amoblado o semi-amoblado');

  -- COM 7: Visita agendada
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, asesor_id, ultima_actividad_at)
  VALUES (v_c_com_vis_ag, v_inmo_id, 'Juan Pablo Correa', '+573001234007', 'cliente', v_asesor_id, now() - interval '6 hours');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado, asesor_id, inmueble_id, zona)
  VALUES (v_inmo_id, v_c_com_vis_ag, 'comercial', 'visita_agendada', 'abierta', v_asesor_id, v_inm_laureles, 'Medellín');
  INSERT INTO public.citas (
    id, inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin, cliente_nombre, cliente_telefono, estado, origen
  ) VALUES (
    gen_random_uuid(), v_inmo_id, v_franja_laureles, v_inm_laureles, current_date + 1, '10:00:00', '10:30:00',
    'Juan Pablo Correa', '+573001234007', 'agendada', 'app'
  );
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, inmueble_id, cuerpo, ocurrido_at)
  VALUES (v_inmo_id, 'visita_agendada', 'humano', v_c_com_vis_ag, v_inm_laureles, 'Cita confirmada para mañana a las 10:00 AM en Apartaestudio Laureles', now() - interval '6 hours');

  -- COM 8: Visita realizada
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, asesor_id, ultima_actividad_at)
  VALUES (v_c_com_vis_re, v_inmo_id, 'Daniela Ochoa', '+573001234008', 'cliente', v_asesor_id, now() - interval '1 day');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado, asesor_id, inmueble_id, zona)
  VALUES (v_inmo_id, v_c_com_vis_re, 'comercial', 'visita_realizada', 'abierta', v_asesor_id, v_inm_poblado, 'Medellín');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, inmueble_id, cuerpo, ocurrido_at)
  VALUES (v_inmo_id, 'visita_realizada', 'humano', v_c_com_vis_re, v_inm_poblado, 'Visita completada. Le gustó mucho la vista y cocina. Solicita formulario de aseguradora.', now() - interval '1 day');

  -- COM 9: En estudio
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, asesor_id, ultima_actividad_at)
  VALUES (v_c_com_estud, v_inmo_id, 'Esteban Jaramillo', '+573001234009', 'cliente', v_asesor_id, now() - interval '2 days');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado, asesor_id, inmueble_id, zona)
  VALUES (v_inmo_id, v_c_com_estud, 'comercial', 'en_estudio', 'abierta', v_asesor_id, v_inm_envigado, 'Envigado');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
  VALUES (v_inmo_id, 'nota', 'humano', v_c_com_estud, 'Papeles radicados en FianzaCrédito con 1 codeudor con finca raíz. Esperando concepto final.', now() - interval '1 day 12 hours');

  -- ===================================================================
  -- ADMINISTRATIVA (Inquilinos y contratos)
  -- ===================================================================

  -- ADM 1: Al día
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, ultima_actividad_at)
  VALUES (v_c_adm_dia_1, v_inmo_id, 'Juliana Serna', '+573101112234', 'cliente', now() - interval '5 hours');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado)
  VALUES (v_inmo_id, v_c_adm_dia_1, 'administrativa', 'al_dia', 'abierta');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, wa_phone_number_id)
  VALUES (v_inmo_id, 'mensaje_entrante', 'humano', v_c_adm_dia_1, 'Buenos días, adjunto el soporte de pago del canon de este mes.', now() - interval '5 hours', '3200000000');

  -- ADM 2: En mora
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, ultima_actividad_at)
  VALUES (v_c_adm_mora, v_inmo_id, 'Mauricio Londoño', '+573101112235', 'cliente', now() - interval '1 day');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado)
  VALUES (v_inmo_id, v_c_adm_mora, 'administrativa', 'en_mora', 'abierta');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, wa_phone_number_id)
  VALUES
    (v_inmo_id, 'mensaje_saliente', 'humano', v_c_adm_mora, 'Estimado Mauricio, le recordamos que presenta 8 días de mora en el canon. ¿Cuándo programará el pago?', now() - interval '2 days', '3200000000'),
    (v_inmo_id, 'mensaje_entrante', 'humano', v_c_adm_mora, 'Buenas tardes, tuve una demora en mi quincena, este viernes cancelo sin falta.', now() - interval '1 day', '3200000000');

  -- ADM 3: Acuerdo de pago
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, ultima_actividad_at)
  VALUES (v_c_adm_acuerdo, v_inmo_id, 'Sandra Patricia Marín', '+573101112236', 'cliente', now() - interval '2 days');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado)
  VALUES (v_inmo_id, v_c_adm_acuerdo, 'administrativa', 'acuerdo_de_pago', 'abierta');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
  VALUES (v_inmo_id, 'nota', 'humano', v_c_adm_acuerdo, 'Acuerdo firmado: abono de $600.000 el 15 y saldo de $600.000 el 30 junto al canon ordinario.', now() - interval '2 days');

  -- ADM 4: Mantenimiento
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, ultima_actividad_at)
  VALUES (v_c_adm_mant, v_inmo_id, 'Camilo Restrepo', '+573101112237', 'cliente', now() - interval '3 hours');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado)
  VALUES (v_inmo_id, v_c_adm_mant, 'administrativa', 'mantenimiento', 'abierta');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, wa_phone_number_id)
  VALUES (v_inmo_id, 'mensaje_entrante', 'humano', v_c_adm_mant, 'Hola, hay una filtración en la tubería bajo el lavamanos del baño principal. Se está regando agua.', now() - interval '3 hours', '3200000000');

  -- ADM 5: En renovación
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, ultima_actividad_at)
  VALUES (v_c_adm_renov, v_inmo_id, 'Gloria Inés Tobón', '+573101112238', 'cliente', now() - interval '3 days');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado)
  VALUES (v_inmo_id, v_c_adm_renov, 'administrativa', 'en_renovacion', 'abierta');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
  VALUES (v_inmo_id, 'nota', 'humano', v_c_adm_renov, 'Contrato vence el 30 de noviembre. Se envió propuesta de renovación con incremento del IPC.', now() - interval '3 days');

  -- ADM 6: En terminación
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, ultima_actividad_at)
  VALUES (v_c_adm_term, v_inmo_id, 'Alejandro Bedoya', '+573101112239', 'cliente', now() - interval '4 days');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado)
  VALUES (v_inmo_id, v_c_adm_term, 'administrativa', 'en_terminacion', 'abierta');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
  VALUES (v_inmo_id, 'nota', 'humano', v_c_adm_term, 'Preaviso recibido legalmente. Entrega física del inmueble e inventario fijada para el 31 de octubre.', now() - interval '4 days');

  -- ===================================================================
  -- CAPTACIÓN (Propietarios e inmuebles en consignación)
  -- ===================================================================

  -- CAP 1: Prospecto
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, ultima_actividad_at)
  VALUES (v_c_cap_prosp_2, v_inmo_id, 'Lucas Arango', '+573109988777', 'propietario', now() - interval '1 hour');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado)
  VALUES (v_inmo_id, v_c_cap_prosp_2, 'captacion', 'prospecto', 'abierta');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, wa_phone_number_id)
  VALUES (v_inmo_id, 'mensaje_entrante', 'humano', v_c_cap_prosp_2, 'Buenas tardes, quiero arrendar mi apartamento en Sabaneta sector Mayorca. ¿Cómo es el proceso con ustedes?', now() - interval '1 hour', '3200000000');

  -- CAP 2: Inmueble verificado
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, ultima_actividad_at)
  VALUES (v_c_cap_verif, v_inmo_id, 'Beatriz Eugenia Cano', '+573109988778', 'propietario', now() - interval '1 day');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado)
  VALUES (v_inmo_id, v_c_cap_verif, 'captacion', 'inmueble_verificado', 'abierta');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
  VALUES (v_inmo_id, 'nota', 'humano', v_c_cap_verif, 'Certificado de Tradición revisado (matrícula 001-123456). Inmueble libre de embargos y al día en predial.', now() - interval '1 day');

  -- CAP 3: Por aprobar
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, ultima_actividad_at)
  VALUES (v_c_cap_aprob, v_inmo_id, 'Fernando Gaviria', '+573109988779', 'propietario', now() - interval '2 days');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado)
  VALUES (v_inmo_id, v_c_cap_aprob, 'captacion', 'por_aprobar', 'abierta');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
  VALUES (v_inmo_id, 'nota', 'humano', v_c_cap_aprob, 'Propuesta de canon $3.200.000 enviada a comité comercial para aprobación de publicación.', now() - interval '2 days');

  -- CAP 4: Propietario contactado
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, ultima_actividad_at)
  VALUES (v_c_cap_cont, v_inmo_id, 'Patricia Uribe', '+573109988780', 'propietario', now() - interval '3 days');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado)
  VALUES (v_inmo_id, v_c_cap_cont, 'captacion', 'propietario_contactado', 'abierta');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at, wa_phone_number_id)
  VALUES
    (v_inmo_id, 'mensaje_saliente', 'humano', v_c_cap_cont, 'Hola doña Patricia, un gusto saludarla. Le comparto nuestro portafolio de administración y seguros de arrendamiento.', now() - interval '3 days', '3200000000'),
    (v_inmo_id, 'mensaje_entrante', 'humano', v_c_cap_cont, 'Muchas gracias, lo voy a revisar con mis hijos esta tarde.', now() - interval '2 days 20 hours', '3200000000');

  -- CAP 5: Negociando
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, ultima_actividad_at)
  VALUES (v_c_cap_negoc, v_inmo_id, 'Jorge Ignacio Vélez', '+573109988781', 'propietario', now() - interval '4 days');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado)
  VALUES (v_inmo_id, v_c_cap_negoc, 'captacion', 'negociando', 'abierta');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
  VALUES (v_inmo_id, 'nota', 'humano', v_c_cap_negoc, 'Negociación en curso: propietario propone pintar el inmueble si la inmobiliaria asume el aseo profundo inicial.', now() - interval '4 days');

  -- CAP 6: Visita al inmueble
  INSERT INTO crm.contactos (id, inmobiliaria_id, nombre, telefono_e164, tipo, ultima_actividad_at)
  VALUES (v_c_cap_vis, v_inmo_id, 'Claudia María Echavarría', '+573109988782', 'propietario', now() - interval '18 hours');
  INSERT INTO crm.oportunidades (inmobiliaria_id, contacto_id, embudo, etapa, estado)
  VALUES (v_inmo_id, v_c_cap_vis, 'captacion', 'visita_captacion', 'abierta');
  INSERT INTO crm.actividades (inmobiliaria_id, tipo, origen, contacto_id, cuerpo, ocurrido_at)
  VALUES (v_inmo_id, 'visita_agendada', 'humano', v_c_cap_vis, 'Visita de captación programada para toma de fotografías profesionales y firma de consignación.', now() - interval '18 hours');

  -- Reactivar el trigger
  ALTER TABLE crm.actividades ENABLE TRIGGER crm_pipeline_actividad;

END $$;
