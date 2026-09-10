SET local check_function_bodies = off;

CREATE ROLE "bi_reader" WITH NOSUPERUSER NOINHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS;

ALTER ROLE "bi_reader" SET "default_transaction_read_only" TO 'on';

ALTER ROLE "bi_reader" SET "statement_timeout" TO '20s';

-- ---------------------------------------------------------------------
-- DESACTIVADO A PROPÓSITO — no borrar sin leer esto.
--
-- La línea original era:
--     GRANT "bi_reader" TO "postgres" WITH ADMIN OPTION;
--
-- QUÉ HACÍA
-- Hacía al rol `postgres` miembro de `bi_reader`, y con "WITH ADMIN OPTION"
-- le daba además la facultad de otorgar esa misma membresía a terceros.
--
-- POR QUÉ FALLA EN LOCAL
-- PostgreSQL prohíbe devolverle la opción ADMIN sobre un rol a quien te lo
-- otorgó a ti (error 0LP01, "ADMIN option cannot be granted back to your own
-- grantor"). En PRODUCCIÓN la instrucción es válida porque allí `bi_reader`
-- lo creó `supabase_admin`, así que `postgres` no es su otorgante y sí puede
-- recibir la opción. En LOCAL, `supabase db reset` corre todo como
-- `postgres`: él crea el rol tres líneas más arriba y, acto seguido, esta
-- instrucción intenta devolverle ADMIN a su propio creador. Postgres lo
-- rechaza y aborta la migración entera.
--
-- POR QUÉ ES SEGURO DESACTIVARLA
-- En local `postgres` es superusuario: ya puede hacer todo lo que esta
-- membresía le daría, así que no se pierde ninguna capacidad. Y lo que de
-- verdad importa de `bi_reader` NO está en esta línea, sino en las que
-- quedan activas: la creación del rol, su `default_transaction_read_only`,
-- su `statement_timeout` de 20s y sus GRANT SELECT acotados. Es decir, el
-- contrato de permisos de Arriendabot se sigue reproduciendo completo en
-- local y se puede probar aquí.
--
-- QUÉ PASA CON PRODUCCIÓN
-- Nada. Esta migración ya está marcada como aplicada allá (el `migration
-- repair` del 10/sep/2026), así que nunca se vuelve a ejecutar contra
-- producción. En producción la membresía sigue existiendo tal cual estaba;
-- comentarla aquí no la revoca ni la modifica.
--
-- SI ALGÚN DÍA SE REGENERA LA LÍNEA BASE
-- Un `supabase db pull` nuevo volverá a escribir esta instrucción, porque
-- lee el estado real de producción y allá la membresía existe. Habrá que
-- volver a comentarla por la misma razón. No es un error del pull: es una
-- diferencia legítima entre cómo se construyó producción y cómo se
-- construye una base local desde cero.
-- ---------------------------------------------------------------------
-- GRANT "bi_reader" TO "postgres" WITH ADMIN OPTION;

CREATE EXTENSION "btree_gist" SCHEMA "public";

CREATE EXTENSION "pg_cron";

CREATE EXTENSION "unaccent" SCHEMA "public";

CREATE TABLE "public"."agente_comercial_conversaciones" (
  "id"               uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmobiliaria_id"  uuid                     NOT NULL,
  "telefono"         text                     NOT NULL,
  "kommo_lead_id"    text,
  "kommo_contact_id" text,
  "cliente_nombre"   text,
  "created_at"       timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  "updated_at"       timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT "agente_comercial_conversaciones_inmobiliaria_id_telefono_key" UNIQUE (inmobiliaria_id, telefono),
  CONSTRAINT "agente_comercial_conversaciones_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."agente_comercial_conversaciones"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."agente_comercial_mensajes" (
  "id"                  uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "conversacion_id"     uuid                     NOT NULL,
  "rol"                 text                     NOT NULL,
  "contenido"           text                     NOT NULL,
  "herramientas_usadas" jsonb,
  "created_at"          timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT "agente_comercial_mensajes_pkey" PRIMARY KEY (id),
  CONSTRAINT "agente_comercial_mensajes_rol_check" CHECK ((rol = ANY (ARRAY['usuario'::text, 'agente'::text])))
);

ALTER TABLE "public"."agente_comercial_mensajes"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."agente_comercial_uso" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmobiliaria_id" uuid                     NOT NULL,
  "conversacion_id" uuid,
  "modelo"          text                     NOT NULL,
  "tokens_entrada"  integer                  NOT NULL DEFAULT 0,
  "tokens_salida"   integer                  NOT NULL DEFAULT 0,
  "tokens_cache"    integer                  NOT NULL DEFAULT 0,
  "etapa"           text,
  "escalado"        boolean                  NOT NULL DEFAULT false,
  "costo_usd"       numeric(12,6)            NOT NULL DEFAULT 0,
  "created_at"      timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT "agente_comercial_uso_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."agente_comercial_uso"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."agentes_config" (
  "id"                 uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmobiliaria_id"    uuid                     NOT NULL,
  "agente"             text                     NOT NULL,
  "activo"             boolean                  NOT NULL DEFAULT true,
  "limite_mensual_usd" numeric(10,2),
  "updated_at"         timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  "updated_by"         uuid,
  "prompt_sistema"     text,
  CONSTRAINT "agentes_config_agente_check" CHECK ((agente = ANY (ARRAY['arriendabot_bi'::text, 'comercial_whatsapp'::text, 'captaciones'::text]))),
  CONSTRAINT "agentes_config_inmobiliaria_id_agente_key" UNIQUE (inmobiliaria_id, agente),
  CONSTRAINT "agentes_config_limite_mensual_usd_check" CHECK (((limite_mensual_usd IS NULL) OR (limite_mensual_usd > (0)::numeric))),
  CONSTRAINT "agentes_config_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."agentes_config"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."bi_artefactos" (
  "id"                 uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmobiliaria_id"    uuid                     NOT NULL,
  "usuario_id"         uuid,
  "conversacion_id"    uuid,
  "tipo"               text                     NOT NULL DEFAULT 'informe'::text,
  "titulo"             text                     NOT NULL,
  "resumen"            text,
  "contenido_markdown" text                     NOT NULL,
  "created_at"         timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT "bi_artefactos_pkey" PRIMARY KEY (id),
  CONSTRAINT "bi_artefactos_tipo_check" CHECK ((tipo = ANY (ARRAY['brief_diario'::text, 'informe'::text, 'otro'::text])))
);

ALTER TABLE "public"."bi_artefactos"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."bi_conversaciones" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmobiliaria_id" uuid                     NOT NULL,
  "usuario_id"      uuid                     NOT NULL,
  "titulo"          text                     NOT NULL,
  "created_at"      timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT "bi_conversaciones_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."bi_conversaciones"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."bi_mensajes" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "conversacion_id" uuid                     NOT NULL,
  "rol"             text                     NOT NULL,
  "contenido"       jsonb                    NOT NULL,
  "created_at"      timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT "bi_mensajes_pkey" PRIMARY KEY (id),
  CONSTRAINT "bi_mensajes_rol_check" CHECK ((rol = ANY (ARRAY['usuario'::text, 'asesor'::text])))
);

ALTER TABLE "public"."bi_mensajes"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."bi_uso" (
  "id"                     uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmobiliaria_id"        uuid                     NOT NULL,
  "usuario_id"             uuid,
  "conversacion_id"        uuid,
  "modelo"                 text                     NOT NULL,
  "tokens_entrada"         integer                  NOT NULL DEFAULT 0,
  "tokens_salida"          integer                  NOT NULL DEFAULT 0,
  "tokens_cache_lectura"   integer                  NOT NULL DEFAULT 0,
  "tokens_cache_escritura" integer                  NOT NULL DEFAULT 0,
  "costo_usd"              numeric(12,6)            NOT NULL DEFAULT 0,
  "created_at"             timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT "bi_uso_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."bi_uso"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."captacion_cola" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmobiliaria_id" uuid                     NOT NULL,
  "fuente"          text                     NOT NULL,
  "fuente_id"       text,
  "url"             text                     NOT NULL,
  "titulo"          text,
  "precio"          numeric,
  "estado"          text                     NOT NULL DEFAULT 'pendiente'::text,
  "prospecto_id"    uuid,
  "created_at"      timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT "captacion_cola_estado_check" CHECK ((estado = ANY (ARRAY['pendiente'::text, 'capturado'::text, 'omitido'::text]))),
  CONSTRAINT "captacion_cola_fuente_check" CHECK ((fuente = ANY (ARRAY['mercadolibre'::text, 'facebook'::text, 'otro'::text]))),
  CONSTRAINT "captacion_cola_inmobiliaria_id_fuente_fuente_id_key" UNIQUE (inmobiliaria_id, fuente, fuente_id),
  CONSTRAINT "captacion_cola_pkey" PRIMARY KEY (id),
  CONSTRAINT "captacion_cola_precio_check" CHECK (((precio IS NULL) OR (precio >= (0)::numeric)))
);

ALTER TABLE "public"."captacion_cola"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."captacion_prospectos" (
  "id"                   uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmobiliaria_id"      uuid                     NOT NULL,
  "fuente"               text                     NOT NULL,
  "fuente_id"            text,
  "url"                  text,
  "titulo"               text,
  "descripcion"          text,
  "tipo_inmueble"        text,
  "tipo_transaccion"     text,
  "ciudad"               text,
  "barrio"               text,
  "precio"               numeric,
  "area_m2"              numeric,
  "habitaciones"         integer,
  "banos"                integer,
  "es_dueno_directo"     boolean,
  "score"                numeric,
  "motivos"              text,
  "contacto_nombre"      text,
  "contacto_telefono"    text,
  "contacto_perfil"      text,
  "canal"                text,
  "mensaje_borrador"     text,
  "estado"               text                     NOT NULL DEFAULT 'nuevo'::text,
  "asesor_id"            uuid,
  "inmueble_id"          uuid,
  "proximo_seguimiento"  date,
  "n_seguimientos"       integer                  NOT NULL DEFAULT 0,
  "base_tratamiento"     text,
  "opt_out"              boolean                  NOT NULL DEFAULT false,
  "origen_dato"          text,
  "fecha_captura"        timestamp with time zone DEFAULT timezone('utc'::text, now()),
  "notas"                text,
  "created_at"           timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  "updated_at"           timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  "fecha_contacto"       date,
  "confianza_particular" numeric,
  CONSTRAINT "captacion_prospectos_estado_check"
    CHECK
    ((estado = ANY (ARRAY['nuevo'::text, 'calificado'::text, 'por_aprobar'::text, 'contactado'::text, 'en_conversacion'::text, 'cita'::text, 'captado'::text,
    'descartado'::text]))),
  CONSTRAINT "captacion_prospectos_fuente_check" CHECK ((fuente = ANY (ARRAY['mercadolibre'::text, 'facebook'::text, 'otro'::text]))),
  CONSTRAINT "captacion_prospectos_inmobiliaria_id_fuente_fuente_id_key" UNIQUE (inmobiliaria_id, fuente, fuente_id),
  CONSTRAINT "captacion_prospectos_pkey" PRIMARY KEY (id),
  CONSTRAINT "captacion_prospectos_precio_check" CHECK (((precio IS NULL) OR (precio >= (0)::numeric))),
  CONSTRAINT "captacion_prospectos_tipo_inmueble_check"
    CHECK
    (((tipo_inmueble IS NULL) OR (tipo_inmueble = ANY (ARRAY['casa'::text, 'apartamento'::text, 'lote'::text, 'local'::text, 'bodega'::text, 'oficina'::text, 'otro'::text])))),
  CONSTRAINT "captacion_prospectos_tipo_transaccion_check" CHECK (((tipo_transaccion IS NULL) OR (tipo_transaccion = ANY (ARRAY['venta'::text, 'arriendo'::text]))))
);

ALTER TABLE "public"."captacion_prospectos"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."captacion_uso" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmobiliaria_id" uuid                     NOT NULL,
  "prospecto_id"    uuid,
  "modelo"          text                     NOT NULL,
  "tokens_entrada"  integer                  NOT NULL DEFAULT 0,
  "tokens_salida"   integer                  NOT NULL DEFAULT 0,
  "tokens_cache"    integer                  NOT NULL DEFAULT 0,
  "costo_usd"       numeric(12,6)            NOT NULL DEFAULT 0,
  "created_at"      timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT "captacion_uso_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."captacion_uso"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."citas" (
  "id"               uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmobiliaria_id"  uuid                     NOT NULL,
  "franja_id"        uuid                     NOT NULL,
  "inmueble_id"      uuid                     NOT NULL,
  "fecha"            date                     NOT NULL,
  "hora_inicio"      time without time zone   NOT NULL,
  "hora_fin"         time without time zone   NOT NULL,
  "cliente_nombre"   text                     NOT NULL,
  "cliente_telefono" text                     NOT NULL,
  "cliente_email"    text,
  "notas"            text,
  "estado"           text                     NOT NULL DEFAULT 'agendada'::text,
  "origen"           text                     NOT NULL DEFAULT 'n8n'::text,
  "created_at"       timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  "alcance"          text                     NOT NULL DEFAULT 'inmueble'::text,
  "unidad"           text,
  "aptos_snapshot"   jsonb,
  "confirmada_at"    timestamp with time zone,
  "confirmada_por"   uuid,
  "completada_at"    timestamp with time zone,
  "completada_por"   uuid,
  CONSTRAINT "citas_alcance_valido" CHECK ((alcance = ANY (ARRAY['inmueble'::text, 'unidad'::text]))),
  CONSTRAINT "citas_estado_check" CHECK ((estado = ANY (ARRAY['agendada'::text, 'cancelada'::text, 'completada'::text]))),
  CONSTRAINT "citas_grilla_30min"
    CHECK
    (((((EXTRACT(minute FROM hora_inicio))::integer % 30) = 0) AND (EXTRACT(second FROM hora_inicio) = (0)::numeric) AND (((EXTRACT(minute FROM hora_fin))::integer % 30) = 0) AND
    (EXTRACT(second FROM hora_fin) = (0)::numeric))),
  CONSTRAINT "citas_hora_fin_mayor" CHECK ((hora_fin > hora_inicio)),
  CONSTRAINT "citas_origen_check" CHECK ((origen = ANY (ARRAY['n8n'::text, 'app'::text]))),
  CONSTRAINT "citas_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."citas"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."franjas_horarias" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmobiliaria_id" uuid                     NOT NULL,
  "inmueble_id"     uuid                     NOT NULL,
  "asesor_id"       uuid                     NOT NULL,
  "fecha"           date                     NOT NULL,
  "hora_inicio"     time without time zone   NOT NULL,
  "hora_fin"        time without time zone   NOT NULL,
  "color"           text                     DEFAULT '#00abd8'::text,
  "creado_por"      uuid                     NOT NULL,
  "created_at"      timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT "franjas_horarias_pkey" PRIMARY KEY (id),
  CONSTRAINT "hora_fin_mayor" CHECK ((hora_fin > hora_inicio))
);

ALTER TABLE "public"."franjas_horarias"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."inmobiliarias" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "nombre"     text                     NOT NULL,
  "nit"        text                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT "inmobiliarias_nit_key" UNIQUE (nit),
  CONSTRAINT "inmobiliarias_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."inmobiliarias"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."inmuebles" (
  "id"                        uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmobiliaria_id"           uuid                     NOT NULL,
  "asesor_id"                 uuid,
  "titulo"                    text                     NOT NULL,
  "descripcion"               text,
  "direccion"                 text                     NOT NULL,
  "precio"                    numeric                  NOT NULL,
  "tipo_transaccion"          text                     NOT NULL,
  "tipo_inmueble"             text                     NOT NULL,
  "estado"                    text                     NOT NULL DEFAULT 'disponible'::text,
  "created_at"                timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  "arrendasoft_id"            bigint,
  "arrendasoft_contrato_id"   text,
  "arrendasoft_contrato_info" jsonb,
  "imagenes"                  jsonb,
  "asesor_id_override"        uuid,
  "unidad"                    text,
  "ciudad"                    text,
  "barrio"                    text,
  "habitaciones"              integer,
  "banos"                     integer,
  "estado_erp"                text,
  "estado_override"           text,
  "empalme_contacto_nombre"   text,
  "empalme_contacto_telefono" text,
  "precio_oferta"             numeric,
  CONSTRAINT "inmuebles_arrendasoft_id_key" UNIQUE (arrendasoft_id),
  CONSTRAINT "inmuebles_estado_check" CHECK ((estado = ANY (ARRAY['disponible'::text, 'arrendado'::text, 'inactivo'::text, 'empalme'::text]))),
  CONSTRAINT "inmuebles_estado_override_check" CHECK (((estado_override IS NULL) OR (estado_override = ANY (ARRAY['disponible'::text, 'empalme'::text])))),
  CONSTRAINT "inmuebles_pkey" PRIMARY KEY (id),
  CONSTRAINT "inmuebles_precio_check" CHECK ((precio >= (0)::numeric)),
  CONSTRAINT "inmuebles_tipo_inmueble_check"
    CHECK ((tipo_inmueble = ANY (ARRAY['casa'::text, 'apartamento'::text, 'lote'::text, 'local'::text, 'bodega'::text, 'oficina'::text, 'otro'::text]))),
  CONSTRAINT "inmuebles_tipo_transaccion_check" CHECK ((tipo_transaccion = ANY (ARRAY['venta'::text, 'arriendo'::text])))
);

ALTER TABLE "public"."inmuebles"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."integraciones_mercadolibre" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmobiliaria_id" uuid                     NOT NULL,
  "ml_user_id"      text,
  "ml_nickname"     text,
  "access_token"    text                     NOT NULL,
  "refresh_token"   text                     NOT NULL,
  "scope"           text,
  "expires_at"      timestamp with time zone NOT NULL,
  "conectado_por"   uuid,
  "created_at"      timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT "integraciones_mercadolibre_inmobiliaria_id_key" UNIQUE (inmobiliaria_id),
  CONSTRAINT "integraciones_mercadolibre_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."integraciones_mercadolibre"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."inventarios" (
  "id"                        uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmueble_id"               uuid                     NOT NULL,
  "titulo"                    text                     NOT NULL,
  "items"                     jsonb                    NOT NULL,
  "creado_por"                uuid,
  "created_at"                timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  "estado"                    text                     NOT NULL DEFAULT 'pendiente'::text,
  "arrendasoft_contrato_id"   text,
  "contrato_id_propuesto"     text,
  "firma_asesor_url"          text,
  "selfie_asesor_url"         text,
  "cedula_asesor_url"         text,
  "cedula_asesor_metadata"    jsonb,
  "firma_inquilino_url"       text,
  "selfie_inquilino_url"      text,
  "cedula_inquilino_url"      text,
  "cedula_inquilino_metadata" jsonb,
  "firmado_at"                timestamp with time zone,
  CONSTRAINT "inventarios_estado_check" CHECK ((estado = ANY (ARRAY['pendiente'::text, 'completado'::text]))),
  CONSTRAINT "inventarios_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."inventarios"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."solicitudes_apertura" (
  "id"                uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmobiliaria_id"   uuid                     NOT NULL,
  "inmueble_id"       uuid                     NOT NULL,
  "alcance"           text                     NOT NULL DEFAULT 'inmueble'::text,
  "unidad"            text,
  "tipo_transaccion"  text,
  "fecha"             date                     NOT NULL,
  "hora_inicio"       time without time zone   NOT NULL,
  "hora_fin"          time without time zone   NOT NULL,
  "cliente_nombre"    text                     NOT NULL,
  "cliente_telefono"  text                     NOT NULL,
  "cliente_email"     text,
  "notas"             text,
  "estado"            text                     NOT NULL DEFAULT 'pendiente'::text,
  "motivo_denegacion" text,
  "cita_id"           uuid,
  "decidido_por"      uuid,
  "decidido_at"       timestamp with time zone,
  "created_at"        timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT "solicitudes_apertura_alcance_check" CHECK ((alcance = ANY (ARRAY['inmueble'::text, 'unidad'::text]))),
  CONSTRAINT "solicitudes_apertura_estado_check" CHECK ((estado = ANY (ARRAY['pendiente'::text, 'aprobada'::text, 'denegada'::text]))),
  CONSTRAINT "solicitudes_apertura_pkey" PRIMARY KEY (id),
  CONSTRAINT "solicitudes_grilla_30min"
    CHECK
    (((((EXTRACT(minute FROM hora_inicio))::integer % 30) = 0) AND (EXTRACT(second FROM hora_inicio) = (0)::numeric) AND (((EXTRACT(minute FROM hora_fin))::integer % 30) = 0) AND
    (EXTRACT(second FROM hora_fin) = (0)::numeric))),
  CONSTRAINT "solicitudes_hora_fin_mayor" CHECK ((hora_fin > hora_inicio))
);

ALTER TABLE "public"."solicitudes_apertura"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."tareas" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmobiliaria_id" uuid                     NOT NULL,
  "usuario_id"      uuid,
  "entidad_tipo"    text                     NOT NULL DEFAULT 'general'::text,
  "entidad_id"      uuid,
  "evento_origen"   text,
  "evento_titulo"   text                     NOT NULL,
  "titulo"          text                     NOT NULL,
  "estado"          text                     NOT NULL DEFAULT 'pendiente'::text,
  "created_at"      timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  "completada_at"   timestamp with time zone,
  "completada_por"  uuid,
  CONSTRAINT "tareas_entidad_tipo_check" CHECK ((entidad_tipo = ANY (ARRAY['captacion'::text, 'inventario'::text, 'inmueble'::text, 'general'::text]))),
  CONSTRAINT "tareas_estado_check" CHECK ((estado = ANY (ARRAY['pendiente'::text, 'completada'::text]))),
  CONSTRAINT "tareas_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."tareas"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."usuarios" (
  "id"              uuid                     NOT NULL,
  "inmobiliaria_id" uuid                     NOT NULL,
  "nombre_completo" text                     NOT NULL,
  "email"           text                     NOT NULL,
  "rol"             text                     NOT NULL,
  "created_at"      timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  "telefono"        text,
  CONSTRAINT "usuarios_pkey" PRIMARY KEY (id),
  CONSTRAINT "usuarios_rol_check" CHECK ((rol = ANY (ARRAY['admin'::text, 'asesor'::text])))
);

ALTER TABLE "public"."usuarios"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."webhook_logs" (
  "id"               uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inmobiliaria_id"  uuid                     NOT NULL,
  "usuario_id"       uuid,
  "titulo_captacion" text                     NOT NULL,
  "asesor_nombre"    text                     NOT NULL,
  "precio"           numeric                  NOT NULL,
  "estado"           text                     NOT NULL DEFAULT 'enviando'::text,
  "error_detalles"   text,
  "payload"          jsonb                    NOT NULL,
  "files_count"      integer                  NOT NULL DEFAULT 0,
  "files_size_bytes" bigint                   NOT NULL DEFAULT 0,
  "created_at"       timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT "webhook_logs_estado_check" CHECK ((estado = ANY (ARRAY['enviando'::text, 'exito'::text, 'fallido'::text]))),
  CONSTRAINT "webhook_logs_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."webhook_logs"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.agendar_cita (
  p_inmueble_id      uuid,
  p_fecha            date,
  p_hora_inicio      time without time zone,
  p_hora_fin         time without time zone,
  p_cliente_nombre   text,
  p_cliente_telefono text,
  p_cliente_email    text                   DEFAULT NULL::text,
  p_notas            text                   DEFAULT NULL::text,
  p_alcance          text                   DEFAULT 'inmueble'::text,
  p_unidad           text                   DEFAULT NULL::text,
  p_aptos_snapshot   jsonb                  DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
    v_inmueble RECORD;
    v_franja   RECORD;
    v_cita_id  UUID;
    v_alcance  TEXT := coalesce(nullif(trim(p_alcance), ''), 'inmueble');
    v_unidad   TEXT;
BEGIN
    IF v_alcance NOT IN ('inmueble', 'unidad') THEN
        RETURN jsonb_build_object('success', false, 'error', 'alcance inv√°lido (usa inmueble o unidad).');
    END IF;

    IF p_cliente_nombre IS NULL OR trim(p_cliente_nombre) = ''
       OR p_cliente_telefono IS NULL OR trim(p_cliente_telefono) = '' THEN
        RETURN jsonb_build_object('success', false, 'error', 'El nombre y el tel√©fono del cliente son obligatorios.');
    END IF;

    IF p_hora_fin <= p_hora_inicio THEN
        RETURN jsonb_build_object('success', false, 'error', 'La hora de fin debe ser posterior a la hora de inicio.');
    END IF;

    IF EXTRACT(MINUTE FROM p_hora_inicio)::int % 30 <> 0 OR EXTRACT(MINUTE FROM p_hora_fin)::int % 30 <> 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'Las citas deben iniciar y terminar en bloques de 30 minutos (ej. 09:00, 09:30, 10:00).');
    END IF;

    IF p_fecha < CURRENT_DATE THEN
        RETURN jsonb_build_object('success', false, 'error', 'No se pueden agendar citas en fechas pasadas.');
    END IF;

    SELECT id, inmobiliaria_id, estado, unidad, direccion, titulo
    INTO v_inmueble FROM inmuebles WHERE id = p_inmueble_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Inmueble no encontrado.');
    END IF;

    -- Guarda: agente comercial pausado por la inmobiliaria
    IF public.agente_comercial_pausado(v_inmueble.inmobiliaria_id) THEN
        RETURN jsonb_build_object(
            'success', false, 'agente_pausado', true,
            'error', 'El agente est√° pausado temporalmente por la inmobiliaria. Un asesor humano continuar√° la conversaci√≥n; no se agend√≥ nada.'
        );
    END IF;

    IF v_inmueble.estado <> 'disponible' THEN
        RETURN jsonb_build_object('success', false, 'error', 'El inmueble ya no est√° disponible.');
    END IF;

    v_unidad := coalesce(nullif(trim(p_unidad), ''), v_inmueble.unidad);

    SELECT fr.id, fr.asesor_id, u.nombre_completo AS asesor
    INTO v_franja
    FROM franjas_horarias fr
    JOIN inmuebles base ON base.id = fr.inmueble_id
    JOIN usuarios u ON u.id = fr.asesor_id
    WHERE fr.inmobiliaria_id = v_inmueble.inmobiliaria_id
      AND fr.fecha = p_fecha
      AND fr.hora_inicio <= p_hora_inicio
      AND fr.hora_fin >= p_hora_fin
      AND ubicacion_key(base.unidad, base.direccion) = ubicacion_key(v_inmueble.unidad, v_inmueble.direccion)
    ORDER BY fr.hora_inicio
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'No hay una franja del asesor que cubra ese horario para este inmueble. Usa consultar_disponibilidad para ver los horarios.');
    END IF;

    INSERT INTO citas (
        inmobiliaria_id, franja_id, inmueble_id, fecha, hora_inicio, hora_fin,
        cliente_nombre, cliente_telefono, cliente_email, notas, origen,
        alcance, unidad, aptos_snapshot
    ) VALUES (
        v_inmueble.inmobiliaria_id, v_franja.id, p_inmueble_id, p_fecha, p_hora_inicio, p_hora_fin,
        trim(p_cliente_nombre), trim(p_cliente_telefono), nullif(trim(p_cliente_email), ''), p_notas, 'n8n',
        v_alcance,
        CASE WHEN v_alcance = 'unidad' THEN v_unidad         ELSE NULL END,
        CASE WHEN v_alcance = 'unidad' THEN p_aptos_snapshot ELSE NULL END
    )
    RETURNING id INTO v_cita_id;

    RETURN jsonb_build_object(
        'success', true,
        'cita_id', v_cita_id,
        'alcance', v_alcance,
        'inmueble', CASE WHEN v_alcance = 'unidad' THEN v_unidad ELSE v_inmueble.titulo END,
        'unidad', CASE WHEN v_alcance = 'unidad' THEN v_unidad ELSE NULL END,
        'aptos_count', CASE WHEN v_alcance = 'unidad' AND p_aptos_snapshot IS NOT NULL
                            THEN jsonb_array_length(p_aptos_snapshot) ELSE NULL END,
        'fecha', p_fecha,
        'hora_inicio', p_hora_inicio,
        'hora_fin', p_hora_fin,
        'asesor', v_franja.asesor
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.agendar_cita_por_texto (
  p_texto            text,
  p_fecha            date,
  p_hora_inicio      time without time zone,
  p_hora_fin         time without time zone,
  p_cliente_nombre   text,
  p_cliente_telefono text,
  p_cliente_email    text                   DEFAULT NULL::text,
  p_notas            text                   DEFAULT NULL::text,
  p_alcance          text                   DEFAULT 'inmueble'::text,
  p_tipo_transaccion text                   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
    v_alcance     TEXT := coalesce(nullif(trim(p_alcance), ''), 'inmueble');
    v_count       INT;
    v_id          UUID;
    v_dist_unidad INT;
    v_dist_tipo   INT;
    v_sin_unidad  INT;
    v_unidad      TEXT;
    v_rep         UUID;
    v_snapshot    JSONB;
BEGIN
    IF v_alcance NOT IN ('inmueble', 'unidad') THEN
        RETURN jsonb_build_object('success', false, 'error', 'alcance inv√°lido (usa inmueble o unidad).');
    END IF;

    -- ---- Agendar a la UNIDAD ----
    IF v_alcance = 'unidad' THEN
        SELECT count(*), count(DISTINCT r.unidad), count(DISTINCT r.tipo_transaccion),
               count(*) FILTER (WHERE r.unidad IS NULL), max(r.unidad)
        INTO v_count, v_dist_unidad, v_dist_tipo, v_sin_unidad, v_unidad
        FROM public.resolver_inmuebles_por_texto(p_texto, p_tipo_transaccion) r;

        IF v_count = 0 THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'No encontr√© aptos disponibles que coincidan con "' || p_texto ||
                         '". S√© m√°s espec√≠fico (nombre de la unidad y, si aplica, arriendo o venta).'
            );
        END IF;

        IF NOT (v_dist_unidad = 1 AND v_dist_tipo = 1 AND v_sin_unidad = 0) THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'No pude identificar una sola unidad y tipo para "' || p_texto ||
                         '". Indica la unidad exacta y si es arriendo o venta, o agenda un apto puntual (alcance=inmueble).'
            );
        END IF;

        -- snapshot de aptos + representativo (el m√°s barato; comparten franjas)
        SELECT jsonb_agg(
                   jsonb_build_object(
                       'inmueble_id', r.id, 'titulo', r.titulo,
                       'precio', r.precio, 'habitaciones', r.habitaciones, 'banos', r.banos
                   ) ORDER BY r.precio),
               (array_agg(r.id ORDER BY r.precio))[1]
        INTO v_snapshot, v_rep
        FROM public.resolver_inmuebles_por_texto(p_texto, p_tipo_transaccion) r;

        RETURN public.agendar_cita(
            v_rep, p_fecha, p_hora_inicio, p_hora_fin,
            p_cliente_nombre, p_cliente_telefono, p_cliente_email, p_notas,
            'unidad', v_unidad, v_snapshot
        );
    END IF;

    -- ---- Agendar a un INMUEBLE puntual (comportamiento cl√°sico) ----
    SELECT count(*) INTO v_count
    FROM public.resolver_inmuebles_por_texto(p_texto, p_tipo_transaccion);

    IF v_count = 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'No encontr√© ning√∫n inmueble disponible que coincida con "' || p_texto ||
                     '". S√© m√°s espec√≠fico: el nombre del edificio, el n√∫mero de apartamento o el barrio.'
        );
    END IF;

    IF v_count > 1 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Encontr√© varios inmuebles que coinciden con "' || p_texto ||
                     '". S√© m√°s espec√≠fico para saber cu√°l agendar (agrega el n√∫mero de apartamento o el edificio), o agenda a la unidad con alcance=unidad.'
        );
    END IF;

    SELECT r.id INTO v_id
    FROM public.resolver_inmuebles_por_texto(p_texto, p_tipo_transaccion) r
    LIMIT 1;

    -- Delega TODA la validaci√≥n y el formato de respuesta (alcance=inmueble por default)
    RETURN public.agendar_cita(
        v_id, p_fecha, p_hora_inicio, p_hora_fin,
        p_cliente_nombre, p_cliente_telefono, p_cliente_email, p_notas
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.agente_comercial_pausado (
  p_inmobiliaria uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
    SELECT NOT COALESCE(
        (SELECT ac.activo FROM agentes_config ac
         WHERE ac.inmobiliaria_id = p_inmobiliaria AND ac.agente = 'comercial_whatsapp'),
        true
    );
$function$;

CREATE OR REPLACE FUNCTION public.buscar_inmueble_por_codigo (
  p_codigo text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
    v_digits TEXT := regexp_replace(COALESCE(p_codigo, ''), '\D', '', 'g');
    v_codigo BIGINT;
BEGIN
    IF v_digits = '' OR length(v_digits) > 18 THEN
        RETURN '[]'::jsonb;
    END IF;
    v_codigo := v_digits::bigint;

    RETURN COALESCE((
        SELECT jsonb_agg(t)
        FROM (
            SELECT
                i.id, i.arrendasoft_id, i.titulo, i.descripcion,
                i.tipo_inmueble, i.tipo_transaccion,
                COALESCE(i.precio_oferta, i.precio) AS precio,
                i.direccion, i.unidad, i.ciudad, i.barrio,
                i.habitaciones, i.banos, i.estado
            FROM public.inmuebles i
            WHERE i.arrendasoft_id = v_codigo
        ) t
    ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancelar_cita (
  p_cita_id          uuid,
  p_cliente_telefono text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
    v_inmobiliaria UUID;
BEGIN
    SELECT c.inmobiliaria_id INTO v_inmobiliaria
    FROM citas c
    WHERE c.id = p_cita_id
      AND trim(c.cliente_telefono) = trim(p_cliente_telefono)
      AND c.estado = 'agendada';

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'No se encontr√≥ una cita agendada con ese ID y tel√©fono.');
    END IF;

    -- Guarda: agente comercial pausado por la inmobiliaria
    IF public.agente_comercial_pausado(v_inmobiliaria) THEN
        RETURN jsonb_build_object(
            'success', false, 'agente_pausado', true,
            'error', 'El agente est√° pausado temporalmente por la inmobiliaria. Un asesor humano continuar√° la conversaci√≥n; la cita NO se cancel√≥.'
        );
    END IF;

    UPDATE citas
    SET estado = 'cancelada'
    WHERE id = p_cita_id
      AND trim(cliente_telefono) = trim(p_cliente_telefono)
      AND estado = 'agendada';

    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.consultar_disponibilidad (
  p_inmueble_id uuid,
  p_fecha_desde date DEFAULT CURRENT_DATE,
  p_fecha_hasta date DEFAULT NULL::date
)
  RETURNS TABLE (
    franja_id   uuid,
    fecha       date,
    hora_inicio time without time zone,
    hora_fin    time without time zone,
    asesor      text
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
    v_hasta DATE := coalesce(p_fecha_hasta, p_fecha_desde + 14);
BEGIN
    RETURN QUERY
    SELECT fr.id, fr.fecha, fr.hora_inicio, fr.hora_fin, u.nombre_completo
    FROM franjas_horarias fr
    JOIN inmuebles base ON base.id = fr.inmueble_id
    JOIN inmuebles obj ON obj.id = p_inmueble_id
        AND obj.inmobiliaria_id = fr.inmobiliaria_id
        AND ubicacion_key(obj.unidad, obj.direccion) = ubicacion_key(base.unidad, base.direccion)
    JOIN usuarios u ON u.id = fr.asesor_id
    WHERE fr.fecha BETWEEN p_fecha_desde AND v_hasta
      AND obj.estado = 'disponible'
    ORDER BY fr.fecha, fr.hora_inicio;
END;
$function$;

CREATE OR REPLACE FUNCTION public.consultar_disponibilidad_por_texto (
  p_texto            text,
  p_fecha_desde      date DEFAULT CURRENT_DATE,
  p_fecha_hasta      date DEFAULT NULL::date,
  p_tipo_transaccion text DEFAULT NULL::text
)
  RETURNS TABLE (
    modo        text,
    inmueble_id uuid,
    titulo      text,
    direccion   text,
    unidad      text,
    aptos_count integer,
    aptos       jsonb,
    franja_id   uuid,
    fecha       date,
    hora_inicio time without time zone,
    hora_fin    time without time zone,
    asesor      text
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
    v_hasta        DATE := coalesce(p_fecha_hasta, p_fecha_desde + 14);
    v_count        INT;
    v_dist_unidad  INT;
    v_dist_tipo    INT;
    v_sin_unidad   INT;
    v_unidad       TEXT;
    v_aptos        JSONB;
    v_aptos_count  INT;
    v_rep          UUID;
    v_inm          RECORD;
    v_slot         RECORD;
    v_tiene        BOOLEAN := false;
    v_inmobiliaria UUID;
BEGIN
    SELECT count(*) INTO v_count
    FROM public.resolver_inmuebles_por_texto(p_texto, p_tipo_transaccion);

    -- Sin resultados
    IF v_count = 0 THEN
        modo := 'sin_resultados';
        inmueble_id := NULL; titulo := NULL; direccion := NULL; unidad := NULL; aptos_count := NULL; aptos := NULL;
        franja_id := NULL; fecha := NULL; hora_inicio := NULL; hora_fin := NULL; asesor := NULL;
        RETURN NEXT; RETURN;
    END IF;

    -- Guarda: agente comercial pausado por la inmobiliaria ‚Üí se√±al expl√≠cita
    SELECT i.inmobiliaria_id INTO v_inmobiliaria
    FROM inmuebles i
    WHERE i.id = (SELECT r.id FROM public.resolver_inmuebles_por_texto(p_texto, p_tipo_transaccion) r LIMIT 1);

    IF public.agente_comercial_pausado(v_inmobiliaria) THEN
        modo := 'agente_pausado';
        inmueble_id := NULL; titulo := NULL; direccion := NULL; unidad := NULL; aptos_count := NULL; aptos := NULL;
        franja_id := NULL; fecha := NULL; hora_inicio := NULL; hora_fin := NULL; asesor := NULL;
        RETURN NEXT; RETURN;
    END IF;

    -- Un solo inmueble ‚Üí disponibilidad a nivel apto
    IF v_count = 1 THEN
        SELECT r.id, r.titulo, r.direccion, r.unidad INTO v_inm
        FROM public.resolver_inmuebles_por_texto(p_texto, p_tipo_transaccion) r
        LIMIT 1;

        FOR v_slot IN
            SELECT s.franja_id, s.fecha, s.hora_inicio, s.hora_fin, s.asesor
            FROM public.consultar_disponibilidad(v_inm.id, p_fecha_desde, v_hasta) s
        LOOP
            v_tiene := true;
            modo := 'disponibilidad';
            inmueble_id := v_inm.id; titulo := v_inm.titulo; direccion := v_inm.direccion;
            unidad := v_inm.unidad; aptos_count := NULL; aptos := NULL;
            franja_id := v_slot.franja_id; fecha := v_slot.fecha; hora_inicio := v_slot.hora_inicio; hora_fin := v_slot.hora_fin; asesor := v_slot.asesor;
            RETURN NEXT;
        END LOOP;

        IF NOT v_tiene THEN
            modo := 'sin_disponibilidad';
            inmueble_id := v_inm.id; titulo := v_inm.titulo; direccion := v_inm.direccion;
            unidad := v_inm.unidad; aptos_count := NULL; aptos := NULL;
            franja_id := NULL; fecha := NULL; hora_inicio := NULL; hora_fin := NULL; asesor := NULL;
            RETURN NEXT;
        END IF;
        RETURN;
    END IF;

    -- ‚â•2 inmuebles: ¬øtodos la misma unidad (no nula) y mismo tipo?
    SELECT count(DISTINCT r.unidad), count(DISTINCT r.tipo_transaccion),
           count(*) FILTER (WHERE r.unidad IS NULL), max(r.unidad)
    INTO v_dist_unidad, v_dist_tipo, v_sin_unidad, v_unidad
    FROM public.resolver_inmuebles_por_texto(p_texto, p_tipo_transaccion) r;

    IF v_dist_unidad = 1 AND v_dist_tipo = 1 AND v_sin_unidad = 0 THEN
        -- disponibilidad_unidad: lista de aptos + franjas compartidas (v√≠a un apto representativo)
        -- Nota: NO usar min(r.id): Postgres no tiene min(uuid).
        SELECT jsonb_agg(
                   jsonb_build_object(
                       'inmueble_id', r.id, 'titulo', r.titulo,
                       'precio', r.precio, 'habitaciones', r.habitaciones, 'banos', r.banos
                   ) ORDER BY r.precio),
               count(*), (array_agg(r.id ORDER BY r.precio))[1]
        INTO v_aptos, v_aptos_count, v_rep
        FROM public.resolver_inmuebles_por_texto(p_texto, p_tipo_transaccion) r;

        FOR v_slot IN
            SELECT s.franja_id, s.fecha, s.hora_inicio, s.hora_fin, s.asesor
            FROM public.consultar_disponibilidad(v_rep, p_fecha_desde, v_hasta) s
        LOOP
            v_tiene := true;
            modo := 'disponibilidad_unidad';
            inmueble_id := NULL; titulo := NULL; direccion := NULL;
            unidad := v_unidad; aptos_count := v_aptos_count; aptos := v_aptos;
            franja_id := v_slot.franja_id; fecha := v_slot.fecha; hora_inicio := v_slot.hora_inicio; hora_fin := v_slot.hora_fin; asesor := v_slot.asesor;
            RETURN NEXT;
        END LOOP;

        IF NOT v_tiene THEN
            modo := 'sin_disponibilidad';
            inmueble_id := NULL; titulo := NULL; direccion := NULL;
            unidad := v_unidad; aptos_count := v_aptos_count; aptos := v_aptos;
            franja_id := NULL; fecha := NULL; hora_inicio := NULL; hora_fin := NULL; asesor := NULL;
            RETURN NEXT;
        END IF;
        RETURN;
    END IF;

    -- Mezcla (unidades/tipos distintos, o inmuebles sin unidad) ‚Üí candidatos
    FOR v_inm IN
        SELECT r.id, r.titulo, r.direccion, r.unidad
        FROM public.resolver_inmuebles_por_texto(p_texto, p_tipo_transaccion) r
        ORDER BY r.titulo
        LIMIT 10
    LOOP
        modo := 'candidatos';
        inmueble_id := v_inm.id; titulo := v_inm.titulo; direccion := v_inm.direccion; unidad := v_inm.unidad;
        aptos_count := NULL; aptos := NULL;
        franja_id := NULL; fecha := NULL; hora_inicio := NULL; hora_fin := NULL; asesor := NULL;
        RETURN NEXT;
    END LOOP;
    RETURN;
END;
$function$;

CREATE OR REPLACE FUNCTION public.crear_tarea_actualizar_inmuebles()
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
    v_inmo RECORD;
    v_hoy  DATE := (now() AT TIME ZONE 'America/Bogota')::date;
BEGIN
    FOR v_inmo IN SELECT id FROM inmobiliarias LOOP
        IF NOT EXISTS (
            SELECT 1 FROM tareas t
            WHERE t.inmobiliaria_id = v_inmo.id
              AND t.evento_origen = 'sync_diario_inmuebles'
              AND (t.created_at AT TIME ZONE 'America/Bogota')::date = v_hoy
        ) THEN
            INSERT INTO tareas (
                inmobiliaria_id, usuario_id, entidad_tipo, entidad_id,
                evento_origen, evento_titulo, titulo, estado
            ) VALUES (
                v_inmo.id, NULL, 'general', NULL,
                'sync_diario_inmuebles',
                'Sincronizaci√≥n ERP',
                'Actualizar inmuebles (' || to_char(v_hoy, 'DD/MM') || ')',
                'pendiente'
            );
        END IF;
    END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_inmobiliaria()
  RETURNS uuid
  LANGUAGE sql
  SECURITY DEFINER
  SET row_security TO 'off'
  AS $function$
  SELECT inmobiliaria_id FROM public.usuarios WHERE id = auth.uid();
$function$;

CREATE OR REPLACE FUNCTION public.get_my_role()
  RETURNS text
  LANGUAGE sql
  SECURITY DEFINER
  SET row_security TO 'off'
  AS $function$
  SELECT rol FROM public.usuarios WHERE id = auth.uid();
$function$;

CREATE OR REPLACE FUNCTION public.marcar_cita_realizada (
  p_cita_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_asesor uuid;
  v_estado text;
BEGIN
  SELECT f.asesor_id, c.estado
    INTO v_asesor, v_estado
    FROM public.citas c
    JOIN public.franjas_horarias f ON f.id = c.franja_id
   WHERE c.id = p_cita_id;

  IF v_asesor IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cita no encontrada.');
  END IF;
  IF v_asesor <> auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Solo el asesor de la cita puede marcarla como realizada.');
  END IF;
  IF v_estado <> 'agendada' THEN
    RETURN jsonb_build_object('success', false, 'error', 'La cita ya no est√° agendada (fue cancelada o ya se marc√≥).');
  END IF;

  UPDATE public.citas
     SET estado = 'completada', completada_at = now(), completada_por = auth.uid()
   WHERE id = p_cita_id;

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.resolver_inmuebles_por_texto (
  p_texto            text,
  p_tipo_transaccion text DEFAULT NULL::text
)
  RETURNS TABLE (
    id               uuid,
    titulo           text,
    direccion        text,
    unidad           text,
    tipo_transaccion text,
    precio           numeric,
    habitaciones     integer,
    banos            integer
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
    v_norm    TEXT;
    v_tokens  TEXT[];
    v_sin_cod TEXT[];
    v_filas   INT;
    v_stop    TEXT[] := ARRAY[
        'del','las','los','una','con','sin','por','que',
        'apartamento','apto','casa','local','oficina','bodega','lote',
        'arriendo','venta','alquiler','inmueble','propiedad',
        -- Ruido que describe la ubicación pero no vive en ninguna columna:
        -- "Luna del Valle piso 5", "Torre 4 Vidanta", "unidad Mi Mundo".
        'piso','torre','bloque','interior','unidad','edificio',
        'urbanizacion','urb','conjunto','apartaestudio'
    ];
BEGIN
    IF trim(p_texto) IS NULL OR trim(p_texto) = '' THEN
        RETURN;
    END IF;

    v_norm := unaccent(lower(trim(p_texto)));

    SELECT ARRAY(
        SELECT t
        FROM unnest(regexp_split_to_array(v_norm, '\s+')) AS t
        WHERE length(t) >= 3
          AND NOT (t = ANY(v_stop))
    ) INTO v_tokens;

    -- Si todo era ruido, caer al texto completo normalizado
    IF array_length(v_tokens, 1) IS NULL THEN
        v_tokens := ARRAY[ v_norm ];
    END IF;

    -- 1ª pasada: TODOS los tokens. Un token de 5+ dígitos es un código del ERP
    -- y se compara exacto contra arrendasoft_id; el resto, como subcadena.
    RETURN QUERY
    SELECT i.id, i.titulo, i.direccion, i.unidad, i.tipo_transaccion,
           COALESCE(i.precio_oferta, i.precio), i.habitaciones, i.banos
    FROM inmuebles i
    WHERE i.estado = 'disponible'
      AND (p_tipo_transaccion IS NULL OR i.tipo_transaccion = p_tipo_transaccion)
      AND (
          SELECT bool_and(
              unaccent(lower(
                  COALESCE(i.titulo,    '') || ' ' ||
                  COALESCE(i.direccion, '') || ' ' ||
                  COALESCE(i.unidad,    '') || ' ' ||
                  COALESCE(i.barrio,    '') || ' ' ||
                  COALESCE(i.ciudad,    '')
              )) ILIKE '%' || tok || '%'
              OR (tok ~ '^\d{5,}$' AND tok = i.arrendasoft_id::text)
          )
          FROM unnest(v_tokens) AS tok
      )
    ORDER BY COALESCE(i.precio_oferta, i.precio), i.titulo;

    GET DIAGNOSTICS v_filas = ROW_COUNT;
    IF v_filas > 0 THEN
        RETURN;
    END IF;

    -- 2ª pasada: sin los códigos del ERP (código viejo, de otra inmobiliaria o
    -- inventado por el modelo). Solo corre si había alguno y queda algo útil.
    SELECT ARRAY(
        SELECT t FROM unnest(v_tokens) AS t WHERE t !~ '^\d{5,}$'
    ) INTO v_sin_cod;

    IF array_length(v_sin_cod, 1) IS NULL OR v_sin_cod = v_tokens THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT i.id, i.titulo, i.direccion, i.unidad, i.tipo_transaccion,
           COALESCE(i.precio_oferta, i.precio), i.habitaciones, i.banos
    FROM inmuebles i
    WHERE i.estado = 'disponible'
      AND (p_tipo_transaccion IS NULL OR i.tipo_transaccion = p_tipo_transaccion)
      AND (
          SELECT bool_and(
              unaccent(lower(
                  COALESCE(i.titulo,    '') || ' ' ||
                  COALESCE(i.direccion, '') || ' ' ||
                  COALESCE(i.unidad,    '') || ' ' ||
                  COALESCE(i.barrio,    '') || ' ' ||
                  COALESCE(i.ciudad,    '')
              )) ILIKE '%' || tok || '%'
          )
          FROM unnest(v_sin_cod) AS tok
      )
    ORDER BY COALESCE(i.precio_oferta, i.precio), i.titulo;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
  RETURNS event_trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'pg_catalog'
  AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.solicitar_apertura_agenda (
  p_texto            text,
  p_fecha            date,
  p_hora_inicio      time without time zone,
  p_hora_fin         time without time zone,
  p_cliente_nombre   text,
  p_cliente_telefono text,
  p_cliente_email    text                   DEFAULT NULL::text,
  p_notas            text                   DEFAULT NULL::text,
  p_alcance          text                   DEFAULT 'inmueble'::text,
  p_tipo_transaccion text                   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
    v_alcance      TEXT := coalesce(nullif(trim(p_alcance), ''), 'inmueble');
    v_count        INT;
    v_dist_unidad  INT;
    v_dist_tipo    INT;
    v_sin_unidad   INT;
    v_unidad       TEXT;
    v_inm          RECORD;
    v_inmobiliaria UUID;
    v_ya_franja    BOOLEAN;
    v_dup          RECORD;
    v_id           UUID;
    v_nombre_pub   TEXT;
BEGIN
    IF v_alcance NOT IN ('inmueble', 'unidad') THEN
        RETURN jsonb_build_object('success', false, 'error', 'alcance inv√°lido (usa inmueble o unidad).');
    END IF;

    IF p_tipo_transaccion IS NOT NULL AND p_tipo_transaccion NOT IN ('arriendo', 'venta') THEN
        RETURN jsonb_build_object('success', false, 'error', 'tipo_transaccion inv√°lido (usa arriendo o venta).');
    END IF;

    IF p_cliente_nombre IS NULL OR trim(p_cliente_nombre) = ''
       OR p_cliente_telefono IS NULL OR trim(p_cliente_telefono) = '' THEN
        RETURN jsonb_build_object('success', false, 'error', 'El nombre y el tel√©fono del cliente son obligatorios.');
    END IF;

    IF p_hora_fin <= p_hora_inicio THEN
        RETURN jsonb_build_object('success', false, 'error', 'La hora de fin debe ser posterior a la hora de inicio.');
    END IF;

    IF EXTRACT(MINUTE FROM p_hora_inicio)::int % 30 <> 0 OR EXTRACT(MINUTE FROM p_hora_fin)::int % 30 <> 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'Los horarios deben iniciar y terminar en bloques de 30 minutos (ej. 09:00, 09:30, 10:00).');
    END IF;

    IF p_fecha < CURRENT_DATE THEN
        RETURN jsonb_build_object('success', false, 'error', 'No se pueden solicitar horarios en fechas pasadas.');
    END IF;

    SELECT count(*), count(DISTINCT r.unidad), count(DISTINCT r.tipo_transaccion),
           count(*) FILTER (WHERE r.unidad IS NULL), max(r.unidad)
    INTO v_count, v_dist_unidad, v_dist_tipo, v_sin_unidad, v_unidad
    FROM public.resolver_inmuebles_por_texto(p_texto, p_tipo_transaccion) r;

    IF v_count = 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'No encontr√© ning√∫n inmueble disponible que coincida con "' || p_texto ||
                     '". S√© m√°s espec√≠fico: el nombre del edificio, el n√∫mero de apartamento o el barrio.'
        );
    END IF;

    IF v_alcance = 'unidad' THEN
        IF NOT (v_dist_unidad = 1 AND v_dist_tipo = 1 AND v_sin_unidad = 0) THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'No pude identificar una sola unidad y tipo para "' || p_texto ||
                         '". Indica la unidad exacta y si es arriendo o venta, o solicita para un apto puntual (alcance=inmueble).'
            );
        END IF;
    ELSE
        IF v_count > 1 THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'Encontr√© varios inmuebles que coinciden con "' || p_texto ||
                         '". S√© m√°s espec√≠fico (agrega el n√∫mero de apartamento o el edificio), o solicita a la unidad con alcance=unidad.'
            );
        END IF;
        v_unidad := NULL;
    END IF;

    SELECT r.id, r.titulo, r.direccion, r.unidad INTO v_inm
    FROM public.resolver_inmuebles_por_texto(p_texto, p_tipo_transaccion) r
    ORDER BY r.precio LIMIT 1;

    SELECT i.inmobiliaria_id INTO v_inmobiliaria FROM inmuebles i WHERE i.id = v_inm.id;

    -- Guarda: agente comercial pausado por la inmobiliaria
    IF public.agente_comercial_pausado(v_inmobiliaria) THEN
        RETURN jsonb_build_object(
            'success', false, 'agente_pausado', true,
            'error', 'El agente est√° pausado temporalmente por la inmobiliaria. Un asesor humano continuar√° la conversaci√≥n; no se registr√≥ la solicitud.'
        );
    END IF;

    v_nombre_pub := CASE WHEN v_alcance = 'unidad' THEN v_unidad ELSE v_inm.titulo END;

    SELECT EXISTS (
        SELECT 1
        FROM franjas_horarias fr
        JOIN inmuebles base ON base.id = fr.inmueble_id
        WHERE fr.inmobiliaria_id = v_inmobiliaria
          AND fr.fecha = p_fecha
          AND fr.hora_inicio <= p_hora_inicio
          AND fr.hora_fin >= p_hora_fin
          AND ubicacion_key(base.unidad, base.direccion) = ubicacion_key(v_inm.unidad, v_inm.direccion)
    ) INTO v_ya_franja;

    IF v_ya_franja THEN
        RETURN jsonb_build_object(
            'success', false, 'ya_disponible', true,
            'error', 'Ese horario ya est√° cubierto por la agenda: no necesitas solicitar apertura. Agenda directamente con agendar_cita_por_texto.'
        );
    END IF;

    SELECT s.id INTO v_dup
    FROM solicitudes_apertura s
    JOIN inmuebles si ON si.id = s.inmueble_id
    WHERE s.estado = 'pendiente'
      AND s.cliente_telefono = trim(p_cliente_telefono)
      AND s.fecha = p_fecha
      AND s.hora_inicio = p_hora_inicio
      AND s.hora_fin = p_hora_fin
      AND ubicacion_key(si.unidad, si.direccion) = ubicacion_key(v_inm.unidad, v_inm.direccion)
    LIMIT 1;

    IF FOUND THEN
        RETURN jsonb_build_object(
            'success', true, 'ya_existia', true,
            'solicitud_id', v_dup.id, 'alcance', v_alcance,
            'inmueble', v_nombre_pub, 'unidad', v_unidad,
            'fecha', p_fecha, 'hora_inicio', p_hora_inicio, 'hora_fin', p_hora_fin,
            'mensaje', 'Esta solicitud ya estaba registrada y sigue pendiente de revisi√≥n.'
        );
    END IF;

    INSERT INTO solicitudes_apertura (
        inmobiliaria_id, inmueble_id, alcance, unidad, tipo_transaccion,
        fecha, hora_inicio, hora_fin,
        cliente_nombre, cliente_telefono, cliente_email, notas
    ) VALUES (
        v_inmobiliaria, v_inm.id, v_alcance, v_unidad, p_tipo_transaccion,
        p_fecha, p_hora_inicio, p_hora_fin,
        trim(p_cliente_nombre), trim(p_cliente_telefono), nullif(trim(p_cliente_email), ''), p_notas
    )
    RETURNING id INTO v_id;

    INSERT INTO tareas (
        inmobiliaria_id, usuario_id, entidad_tipo, entidad_id,
        evento_origen, evento_titulo, titulo, estado
    ) VALUES (
        v_inmobiliaria,
        NULL,
        'general',
        v_id,
        'solicitud_apertura',
        'Solicitud de apertura ‚Äî ' || v_nombre_pub,
        'Aprobar o denegar: ' || trim(p_cliente_nombre) || ' ¬∑ ' ||
            to_char(p_fecha, 'DD/MM') || ' ' || left(p_hora_inicio::text, 5),
        'pendiente'
    );

    RETURN jsonb_build_object(
        'success', true, 'ya_existia', false,
        'solicitud_id', v_id, 'alcance', v_alcance,
        'inmueble', v_nombre_pub, 'unidad', v_unidad,
        'fecha', p_fecha, 'hora_inicio', p_hora_inicio, 'hora_fin', p_hora_fin
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.ubicacion_key (
  p_unidad    text,
  p_direccion text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  AS $function$
  SELECT lower(trim(coalesce(nullif(trim(p_unidad), ''), p_direccion)))
$function$;

ALTER TABLE "public"."agente_comercial_mensajes"
  ADD CONSTRAINT "agente_comercial_mensajes_conversacion_id_fkey" FOREIGN KEY (conversacion_id) REFERENCES public.agente_comercial_conversaciones(id) ON DELETE CASCADE;

ALTER TABLE "public"."agente_comercial_uso"
  ADD CONSTRAINT "agente_comercial_uso_conversacion_id_fkey" FOREIGN KEY (conversacion_id) REFERENCES public.agente_comercial_conversaciones(id) ON DELETE SET NULL;

ALTER TABLE "public"."bi_artefactos"
  ADD CONSTRAINT "bi_artefactos_conversacion_id_fkey" FOREIGN KEY (conversacion_id) REFERENCES public.bi_conversaciones(id) ON DELETE SET NULL;

ALTER TABLE "public"."bi_mensajes"
  ADD CONSTRAINT "bi_mensajes_conversacion_id_fkey" FOREIGN KEY (conversacion_id) REFERENCES public.bi_conversaciones(id) ON DELETE CASCADE;

ALTER TABLE "public"."bi_uso"
  ADD CONSTRAINT "bi_uso_conversacion_id_fkey" FOREIGN KEY (conversacion_id) REFERENCES public.bi_conversaciones(id) ON DELETE SET NULL;

ALTER TABLE "public"."captacion_cola"
  ADD CONSTRAINT "captacion_cola_prospecto_id_fkey" FOREIGN KEY (prospecto_id) REFERENCES public.captacion_prospectos(id) ON DELETE SET NULL;

ALTER TABLE "public"."captacion_uso"
  ADD CONSTRAINT "captacion_uso_prospecto_id_fkey" FOREIGN KEY (prospecto_id) REFERENCES public.captacion_prospectos(id) ON DELETE SET NULL;

ALTER TABLE "public"."citas"
  ADD CONSTRAINT "citas_franja_id_fkey" FOREIGN KEY (franja_id) REFERENCES public.franjas_horarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."agente_comercial_conversaciones"
  ADD CONSTRAINT "agente_comercial_conversaciones_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."agente_comercial_uso"
  ADD CONSTRAINT "agente_comercial_uso_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."agentes_config"
  ADD CONSTRAINT "agentes_config_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."bi_artefactos"
  ADD CONSTRAINT "bi_artefactos_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."bi_conversaciones"
  ADD CONSTRAINT "bi_conversaciones_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."bi_uso"
  ADD CONSTRAINT "bi_uso_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."captacion_cola"
  ADD CONSTRAINT "captacion_cola_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."captacion_prospectos"
  ADD CONSTRAINT "captacion_prospectos_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."captacion_uso"
  ADD CONSTRAINT "captacion_uso_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."citas"
  ADD CONSTRAINT "citas_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."franjas_horarias"
  ADD CONSTRAINT "franjas_horarias_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."inmuebles"
  ADD CONSTRAINT "inmuebles_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."captacion_prospectos"
  ADD CONSTRAINT "captacion_prospectos_inmueble_id_fkey" FOREIGN KEY (inmueble_id) REFERENCES public.inmuebles(id) ON DELETE SET NULL;

ALTER TABLE "public"."citas"
  ADD CONSTRAINT "citas_inmueble_id_fkey" FOREIGN KEY (inmueble_id) REFERENCES public.inmuebles(id) ON DELETE CASCADE;

ALTER TABLE "public"."franjas_horarias"
  ADD CONSTRAINT "franjas_horarias_inmueble_id_fkey" FOREIGN KEY (inmueble_id) REFERENCES public.inmuebles(id) ON DELETE CASCADE;

ALTER TABLE "public"."integraciones_mercadolibre"
  ADD CONSTRAINT "integraciones_mercadolibre_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."inventarios"
  ADD CONSTRAINT "inventarios_inmueble_id_fkey" FOREIGN KEY (inmueble_id) REFERENCES public.inmuebles(id) ON DELETE CASCADE;

ALTER TABLE "public"."solicitudes_apertura"
  ADD CONSTRAINT "solicitudes_apertura_cita_id_fkey" FOREIGN KEY (cita_id) REFERENCES public.citas(id) ON DELETE SET NULL;

ALTER TABLE "public"."solicitudes_apertura"
  ADD CONSTRAINT "solicitudes_apertura_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."solicitudes_apertura"
  ADD CONSTRAINT "solicitudes_apertura_inmueble_id_fkey" FOREIGN KEY (inmueble_id) REFERENCES public.inmuebles(id) ON DELETE CASCADE;

ALTER TABLE "public"."tareas"
  ADD CONSTRAINT "tareas_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."usuarios"
  ADD CONSTRAINT "usuarios_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."usuarios"
  ADD CONSTRAINT "usuarios_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."agentes_config"
  ADD CONSTRAINT "agentes_config_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES public.usuarios(id) ON DELETE SET NULL;

ALTER TABLE "public"."bi_artefactos"
  ADD CONSTRAINT "bi_artefactos_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL;

ALTER TABLE "public"."bi_conversaciones"
  ADD CONSTRAINT "bi_conversaciones_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE CASCADE;

ALTER TABLE "public"."bi_uso"
  ADD CONSTRAINT "bi_uso_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL;

ALTER TABLE "public"."captacion_prospectos"
  ADD CONSTRAINT "captacion_prospectos_asesor_id_fkey" FOREIGN KEY (asesor_id) REFERENCES public.usuarios(id) ON DELETE SET NULL;

ALTER TABLE "public"."citas"
  ADD CONSTRAINT "citas_completada_por_fkey" FOREIGN KEY (completada_por) REFERENCES public.usuarios(id) ON DELETE SET NULL;

ALTER TABLE "public"."citas"
  ADD CONSTRAINT "citas_confirmada_por_fkey" FOREIGN KEY (confirmada_por) REFERENCES public.usuarios(id) ON DELETE SET NULL;

ALTER TABLE "public"."franjas_horarias"
  ADD CONSTRAINT "franjas_horarias_asesor_id_fkey" FOREIGN KEY (asesor_id) REFERENCES public.usuarios(id) ON DELETE CASCADE;

ALTER TABLE "public"."franjas_horarias"
  ADD CONSTRAINT "franjas_horarias_creado_por_fkey" FOREIGN KEY (creado_por) REFERENCES public.usuarios(id);

ALTER TABLE "public"."inmuebles"
  ADD CONSTRAINT "inmuebles_asesor_id_fkey" FOREIGN KEY (asesor_id) REFERENCES public.usuarios(id) ON DELETE SET NULL;

ALTER TABLE "public"."inmuebles"
  ADD CONSTRAINT "inmuebles_asesor_id_override_fkey" FOREIGN KEY (asesor_id_override) REFERENCES public.usuarios(id) ON DELETE SET NULL;

ALTER TABLE "public"."integraciones_mercadolibre"
  ADD CONSTRAINT "integraciones_mercadolibre_conectado_por_fkey" FOREIGN KEY (conectado_por) REFERENCES public.usuarios(id) ON DELETE SET NULL;

ALTER TABLE "public"."inventarios"
  ADD CONSTRAINT "inventarios_creado_por_fkey" FOREIGN KEY (creado_por) REFERENCES public.usuarios(id) ON DELETE SET NULL;

ALTER TABLE "public"."solicitudes_apertura"
  ADD CONSTRAINT "solicitudes_apertura_decidido_por_fkey" FOREIGN KEY (decidido_por) REFERENCES public.usuarios(id) ON DELETE SET NULL;

ALTER TABLE "public"."tareas"
  ADD CONSTRAINT "tareas_completada_por_fkey" FOREIGN KEY (completada_por) REFERENCES public.usuarios(id) ON DELETE SET NULL;

ALTER TABLE "public"."tareas"
  ADD CONSTRAINT "tareas_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL;

ALTER TABLE "public"."webhook_logs"
  ADD CONSTRAINT "webhook_logs_inmobiliaria_id_fkey" FOREIGN KEY (inmobiliaria_id) REFERENCES public.inmobiliarias(id) ON DELETE CASCADE;

ALTER TABLE "public"."webhook_logs"
  ADD CONSTRAINT "webhook_logs_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL;

CREATE VIEW "public"."franjas_inmuebles" WITH (security_invoker=true) AS  SELECT f.id AS franja_id,
    vinculado.id AS inmueble_id,
    f.inmobiliaria_id,
    f.asesor_id,
    f.fecha,
    f.hora_inicio,
    f.hora_fin
   FROM ((public.franjas_horarias f
     JOIN public.inmuebles base ON ((base.id = f.inmueble_id)))
     JOIN public.inmuebles vinculado ON (((vinculado.inmobiliaria_id = f.inmobiliaria_id) AND (public.ubicacion_key(vinculado.unidad, vinculado.direccion) = public.ubicacion_key(base.unidad, base.direccion)))));

CREATE INDEX idx_agente_comercial_conv_telefono ON public.agente_comercial_conversaciones USING btree (inmobiliaria_id, telefono);

CREATE INDEX idx_agente_comercial_mensajes_conversacion ON public.agente_comercial_mensajes USING btree (conversacion_id, created_at);

CREATE INDEX idx_agente_comercial_uso_inmobiliaria ON public.agente_comercial_uso USING btree (inmobiliaria_id, created_at DESC);

CREATE INDEX idx_bi_artefactos_inmobiliaria ON public.bi_artefactos USING btree (inmobiliaria_id, created_at DESC);

CREATE INDEX idx_bi_conversaciones_usuario ON public.bi_conversaciones USING btree (usuario_id, updated_at DESC);

CREATE INDEX idx_bi_mensajes_conversacion ON public.bi_mensajes USING btree (conversacion_id, created_at);

CREATE INDEX idx_bi_uso_inmobiliaria ON public.bi_uso USING btree (inmobiliaria_id, created_at DESC);

CREATE INDEX idx_captacion_cola_pendientes ON public.captacion_cola USING btree (inmobiliaria_id, created_at)
  WHERE (estado = 'pendiente'::text);

CREATE INDEX idx_captacion_prospectos_inmobiliaria ON public.captacion_prospectos USING btree (inmobiliaria_id, estado);

CREATE INDEX idx_captacion_prospectos_seguimiento ON public.captacion_prospectos USING btree (inmobiliaria_id, proximo_seguimiento)
  WHERE (proximo_seguimiento IS NOT NULL);

CREATE INDEX idx_captacion_uso_inmobiliaria ON public.captacion_uso USING btree (inmobiliaria_id, created_at DESC);

CREATE INDEX idx_citas_fecha ON public.citas USING btree (fecha);

CREATE INDEX idx_citas_franja ON public.citas USING btree (franja_id);

CREATE INDEX idx_citas_inmobiliaria ON public.citas USING btree (inmobiliaria_id);

CREATE INDEX idx_franjas_asesor ON public.franjas_horarias USING btree (asesor_id);

CREATE INDEX idx_franjas_fecha ON public.franjas_horarias USING btree (fecha);

CREATE INDEX idx_franjas_inmobiliaria ON public.franjas_horarias USING btree (inmobiliaria_id);

CREATE INDEX idx_integraciones_ml_inmobiliaria ON public.integraciones_mercadolibre USING btree (inmobiliaria_id);

CREATE INDEX idx_solicitudes_estado ON public.solicitudes_apertura USING btree (inmobiliaria_id, estado);

CREATE INDEX idx_solicitudes_telefono ON public.solicitudes_apertura USING btree (cliente_telefono);

CREATE POLICY "Admins ven las conversaciones de su inmobiliaria" ON "public"."agente_comercial_conversaciones"
  FOR SELECT
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)));

CREATE POLICY "Admins ven los mensajes de su inmobiliaria" ON "public"."agente_comercial_mensajes"
  FOR SELECT
  TO PUBLIC
  USING ((EXISTS ( SELECT 1
   FROM public.agente_comercial_conversaciones c
  WHERE ((c.id = agente_comercial_mensajes.conversacion_id) AND (c.inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)))));

CREATE POLICY "Admins ven el uso comercial de su inmobiliaria" ON "public"."agente_comercial_uso"
  FOR SELECT
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)));

CREATE POLICY "Admins gestionan los agentes de su inmobiliaria" ON "public"."agentes_config"
  FOR ALL
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)))
  WITH CHECK (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)));

CREATE POLICY "Admins ven y gestionan los informes de su inmobiliaria" ON "public"."bi_artefactos"
  FOR ALL
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)))
  WITH CHECK (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)));

CREATE POLICY "Admin gestiona sus propias conversaciones" ON "public"."bi_conversaciones"
  FOR ALL
  TO PUBLIC
  USING (((usuario_id = auth.uid()) AND (inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)))
  WITH CHECK (((usuario_id = auth.uid()) AND (inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)));

CREATE POLICY "Admin gestiona mensajes de sus conversaciones" ON "public"."bi_mensajes"
  FOR ALL
  TO PUBLIC
  USING ((EXISTS ( SELECT 1
   FROM public.bi_conversaciones c
  WHERE ((c.id = bi_mensajes.conversacion_id) AND (c.usuario_id = auth.uid())))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM public.bi_conversaciones c
  WHERE ((c.id = bi_mensajes.conversacion_id) AND (c.usuario_id = auth.uid())))));

CREATE POLICY "Admins ven y registran el uso BI de su inmobiliaria" ON "public"."bi_uso"
  FOR ALL
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)))
  WITH CHECK (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)));

CREATE POLICY "Admins gestionan la cola de su inmobiliaria" ON "public"."captacion_cola"
  FOR ALL
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)))
  WITH CHECK (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)));

CREATE POLICY "Admins gestionan prospectos de su inmobiliaria" ON "public"."captacion_prospectos"
  FOR ALL
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)))
  WITH CHECK (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)));

CREATE POLICY "Asesores ven sus prospectos asignados" ON "public"."captacion_prospectos"
  FOR SELECT
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (asesor_id = auth.uid())));

CREATE POLICY "Admins ven el uso de captaciones de su inmobiliaria" ON "public"."captacion_uso"
  FOR SELECT
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)));

CREATE POLICY "Admins gestionan citas de su inmobiliaria" ON "public"."citas"
  FOR ALL
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)));

CREATE POLICY "Asesores ven citas de sus franjas" ON "public"."citas"
  FOR SELECT
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (EXISTS ( SELECT 1
   FROM public.franjas_horarias f
  WHERE ((f.id = citas.franja_id) AND (f.asesor_id = auth.uid()))))));

CREATE POLICY "BI reader lee citas" ON "public"."citas"
  FOR SELECT
  TO "bi_reader"
  USING (true);

CREATE POLICY "Admins CRUD franjas de su inmobiliaria" ON "public"."franjas_horarias"
  FOR ALL
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)));

CREATE POLICY "Agente anon lee franjas" ON "public"."franjas_horarias"
  FOR SELECT
  TO "anon"
  USING (true);

CREATE POLICY "Asesores ven sus franjas asignadas" ON "public"."franjas_horarias"
  FOR SELECT
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'asesor'::text) AND (asesor_id = auth.uid())));

CREATE POLICY "BI reader lee franjas" ON "public"."franjas_horarias"
  FOR SELECT
  TO "bi_reader"
  USING (true);

CREATE POLICY "BI reader lee inmobiliarias" ON "public"."inmobiliarias"
  FOR SELECT
  TO "bi_reader"
  USING (true);

CREATE POLICY "Los usuarios pueden ver su propia inmobiliaria" ON "public"."inmobiliarias"
  FOR SELECT
  TO PUBLIC
  USING ((id = public.get_my_inmobiliaria()));

CREATE POLICY "Permitir la creación de inmobiliaria en el registro" ON "public"."inmobiliarias"
  FOR INSERT
  TO PUBLIC
  WITH CHECK (true);

CREATE POLICY "Admins gestionan cualquier inmueble de su inmobiliaria" ON "public"."inmuebles"
  FOR ALL
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)))
  WITH CHECK (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)));

CREATE POLICY "Admins ven todos los inmuebles de su inmobiliaria; Asesores ven" ON "public"."inmuebles"
  FOR SELECT
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND ((public.get_my_role() = 'admin'::text) OR (COALESCE(asesor_id_override, asesor_id) = auth.uid()))));

CREATE POLICY "Agente anon lee inmuebles disponibles" ON "public"."inmuebles"
  FOR SELECT
  TO "anon"
  USING ((estado = 'disponible'::text));

CREATE POLICY "Asesores pueden actualizar sus propios inmuebles asignados" ON "public"."inmuebles"
  FOR UPDATE
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'asesor'::text) AND (COALESCE(asesor_id_override, asesor_id) = auth.uid())))
  WITH CHECK (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'asesor'::text) AND (COALESCE(asesor_id_override, asesor_id) = auth.uid())));

CREATE POLICY "Asesores pueden insertar inmuebles de su propia inmobiliaria as" ON "public"."inmuebles"
  FOR INSERT
  TO PUBLIC
  WITH CHECK (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'asesor'::text) AND (COALESCE(asesor_id_override, asesor_id) = auth.uid())));

CREATE POLICY "BI reader lee inmuebles" ON "public"."inmuebles"
  FOR SELECT
  TO "bi_reader"
  USING (true);

CREATE POLICY "Admins gestionan todos los inventarios de su inmobiliaria" ON "public"."inventarios"
  FOR ALL
  TO PUBLIC
  USING ((EXISTS ( SELECT 1
   FROM public.inmuebles i
  WHERE ((i.id = inventarios.inmueble_id) AND (i.inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM public.inmuebles i
  WHERE ((i.id = inventarios.inmueble_id) AND (i.inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)))));

CREATE POLICY "Admins ven inventarios de su inmobiliaria; Asesores ven de sus " ON "public"."inventarios"
  FOR SELECT
  TO PUBLIC
  USING ((EXISTS ( SELECT 1
   FROM public.inmuebles i
  WHERE
    ((i.id = inventarios.inmueble_id) AND (i.inmobiliaria_id = public.get_my_inmobiliaria()) AND ((public.get_my_role() = 'admin'::text) OR (COALESCE(i.asesor_id_override,
    i.asesor_id) = auth.uid()) OR (inventarios.creado_por = auth.uid()))))));

CREATE POLICY "Asesores pueden crear y editar inventarios para sus inmuebles a" ON "public"."inventarios"
  FOR ALL
  TO PUBLIC
  USING ((EXISTS ( SELECT 1
   FROM public.inmuebles i
  WHERE
    ((i.id = inventarios.inmueble_id) AND (i.inmobiliaria_id = public.get_my_inmobiliaria()) AND ((COALESCE(i.asesor_id_override, i.asesor_id) = auth.uid()) OR
    (inventarios.creado_por = auth.uid()))))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM public.inmuebles i
  WHERE
    ((i.id = inventarios.inmueble_id) AND (i.inmobiliaria_id = public.get_my_inmobiliaria()) AND ((COALESCE(i.asesor_id_override, i.asesor_id) = auth.uid()) OR
    (inventarios.creado_por = auth.uid()))))));

CREATE POLICY "BI reader lee inventarios" ON "public"."inventarios"
  FOR SELECT
  TO "bi_reader"
  USING (true);

CREATE POLICY "Admins gestionan solicitudes de su inmobiliaria" ON "public"."solicitudes_apertura"
  FOR ALL
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)));

CREATE POLICY "BI reader lee solicitudes_apertura" ON "public"."solicitudes_apertura"
  FOR SELECT
  TO "bi_reader"
  USING (true);

CREATE POLICY "BI reader lee tareas" ON "public"."tareas"
  FOR SELECT
  TO "bi_reader"
  USING (true);

CREATE POLICY "Solo admins pueden actualizar tareas" ON "public"."tareas"
  FOR UPDATE
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)));

CREATE POLICY "Usuarios pueden insertar tareas" ON "public"."tareas"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((inmobiliaria_id = public.get_my_inmobiliaria()));

CREATE POLICY "Usuarios ven tareas según rol y pertenencia" ON "public"."tareas"
  FOR SELECT
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND ((public.get_my_role() = 'admin'::text) OR (usuario_id = auth.uid()))));

CREATE POLICY "BI reader lee usuarios" ON "public"."usuarios"
  FOR SELECT
  TO "bi_reader"
  USING (true);

CREATE POLICY "Los administradores pueden gestionar usuarios de su inmobiliari" ON "public"."usuarios"
  FOR ALL
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)))
  WITH CHECK (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (public.get_my_role() = 'admin'::text)));

CREATE POLICY "Los usuarios pueden actualizar su propio perfil" ON "public"."usuarios"
  FOR UPDATE
  TO PUBLIC
  USING ((id = auth.uid()))
  WITH CHECK ((id = auth.uid()));

CREATE POLICY "Los usuarios pueden ver perfiles de su misma inmobiliaria" ON "public"."usuarios"
  FOR SELECT
  TO PUBLIC
  USING ((inmobiliaria_id = public.get_my_inmobiliaria()));

CREATE POLICY "Permitir inserción de primer perfil" ON "public"."usuarios"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((id = auth.uid()));

CREATE POLICY "Admins ven todos los logs de su inmobiliaria; Asesores ven los " ON "public"."webhook_logs"
  FOR SELECT
  TO PUBLIC
  USING (((inmobiliaria_id = public.get_my_inmobiliaria()) AND ((public.get_my_role() = 'admin'::text) OR (usuario_id = auth.uid()))));

CREATE POLICY "BI reader lee webhook_logs" ON "public"."webhook_logs"
  FOR SELECT
  TO "bi_reader"
  USING (true);

CREATE POLICY "Los usuarios pueden insertar sus propios logs" ON "public"."webhook_logs"
  FOR INSERT
  TO PUBLIC
  WITH CHECK (((inmobiliaria_id = public.get_my_inmobiliaria()) AND (usuario_id = auth.uid())));

CREATE POLICY "Permitir a asesores subir firmas de su inmobiliaria" ON "storage"."objects"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((bucket_id = 'firmas_biometricas'::text) AND ((storage.foldername(name))[1] = ( SELECT (usuarios.inmobiliaria_id)::text AS inmobiliaria_id
   FROM public.usuarios
  WHERE (usuarios.id = auth.uid())))));

CREATE POLICY "Permitir a asesores ver firmas de su inmobiliaria" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING (((bucket_id = 'firmas_biometricas'::text) AND ((storage.foldername(name))[1] = ( SELECT (usuarios.inmobiliaria_id)::text AS inmobiliaria_id
   FROM public.usuarios
  WHERE (usuarios.id = auth.uid())))));

CREATE POLICY "Solo administradores de la inmobiliaria pueden borrar firmas" ON "storage"."objects"
  FOR DELETE
  TO "authenticated"
  USING (((bucket_id = 'firmas_biometricas'::text) AND ((storage.foldername(name))[1] = ( SELECT (usuarios.inmobiliaria_id)::text AS inmobiliaria_id
   FROM public.usuarios
  WHERE ((usuarios.id = auth.uid()) AND (usuarios.rol = 'admin'::text))))));

CREATE POLICY "captaciones: lectura publica" ON "storage"."objects"
  FOR SELECT
  TO PUBLIC
  USING ((bucket_id = 'captaciones'::text));

CREATE POLICY "captaciones: subida autenticada" ON "storage"."objects"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((bucket_id = 'captaciones'::text));

CREATE EVENT TRIGGER "ensure_rls"
  ON ddl_command_end
  WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  EXECUTE FUNCTION "public"."rls_auto_enable"();

COMMENT ON COLUMN "public"."citas"."alcance" IS 'inmueble = visita a un apto puntual; unidad = visita a la unidad (varios aptos equivalentes)';

COMMENT ON COLUMN "public"."citas"."aptos_snapshot" IS 'Aptos disponibles al agendar [{inmueble_id,titulo,precio,habitaciones,banos}] (solo alcance=unidad)';

COMMENT ON COLUMN "public"."citas"."completada_at" IS 'Cu√°ndo el asesor marc√≥ la cita como realizada; NULL = no marcada';

COMMENT ON COLUMN "public"."citas"."completada_por" IS 'Asesor que marc√≥ la cita como realizada';

COMMENT ON COLUMN "public"."citas"."confirmada_at" IS '√öltima vez que la cita se envi√≥ al flujo n8n "Confirmar citas" (‚Üí Kommo); NULL = nunca enviada';

COMMENT ON COLUMN "public"."citas"."confirmada_por" IS 'Admin que dispar√≥ esa confirmaci√≥n';

COMMENT ON COLUMN "public"."citas"."unidad" IS 'Nombre de la unidad cuando alcance=unidad (ej. "Mi Mundo"); NULL cuando alcance=inmueble';

COMMENT ON COLUMN "public"."inmuebles"."precio_oferta" IS 'Canon con el que se está ofreciendo un inmueble en desocupación (sube por IPC). Override local: el sync del ERP no lo toca. NULL = usar precio. El precio efectivo es COALESCE(precio_oferta, precio).';

COMMENT ON EXTENSION "btree_gist" IS 'support for indexing common datatypes in GiST';

COMMENT ON EXTENSION "pg_cron" IS 'Job scheduler for PostgreSQL';

COMMENT ON EXTENSION "unaccent" IS 'text search dictionary that removes accents';

GRANT EXECUTE
  ON FUNCTION "public"."agendar_cita"(uuid, date, time WITHOUT time zone, time WITHOUT time zone, text, text, text, text, text, text, jsonb)
  TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

GRANT EXECUTE
  ON FUNCTION "public"."agendar_cita_por_texto"(text, date, time WITHOUT time zone, time WITHOUT time zone, text, text, text, text, text, text)
  TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

REVOKE ALL ON FUNCTION "public"."agente_comercial_pausado"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."agente_comercial_pausado"(uuid) TO "postgres", "service_role";

GRANT EXECUTE ON FUNCTION "public"."buscar_inmueble_por_codigo"(text) TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

GRANT EXECUTE ON FUNCTION "public"."cancelar_cita"(uuid, text) TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

GRANT EXECUTE ON FUNCTION "public"."consultar_disponibilidad"(uuid, date, date) TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

GRANT EXECUTE ON FUNCTION "public"."consultar_disponibilidad_por_texto"(text, date, date, text) TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

REVOKE ALL ON FUNCTION "public"."crear_tarea_actualizar_inmuebles"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."crear_tarea_actualizar_inmuebles"() TO "postgres", "service_role";

GRANT EXECUTE ON FUNCTION "public"."get_my_inmobiliaria"() TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

GRANT EXECUTE ON FUNCTION "public"."get_my_role"() TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

REVOKE ALL ON FUNCTION "public"."marcar_cita_realizada"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."marcar_cita_realizada"(uuid) TO "authenticated", "postgres", "service_role";

GRANT EXECUTE ON FUNCTION "public"."resolver_inmuebles_por_texto"(text, text) TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

GRANT EXECUTE ON FUNCTION "public"."rls_auto_enable"() TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

GRANT EXECUTE
  ON FUNCTION "public"."solicitar_apertura_agenda"(text, date, time WITHOUT time zone, time WITHOUT time zone, text, text, text, text, text, text)
  TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

GRANT EXECUTE ON FUNCTION "public"."ubicacion_key"(text, text) TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

REVOKE ALL ON SCHEMA "public" FROM "bi_reader";

GRANT USAGE ON SCHEMA "public" TO "bi_reader";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."agente_comercial_conversaciones" TO "authenticated", "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."agente_comercial_mensajes" TO "authenticated", "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."agente_comercial_uso" TO "authenticated", "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."agentes_config" TO "authenticated", "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."bi_artefactos" TO "authenticated", "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."bi_conversaciones" TO "authenticated", "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."bi_mensajes" TO "authenticated", "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."bi_uso" TO "authenticated", "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."captacion_cola" TO "anon", "authenticated", "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."captacion_prospectos" TO "authenticated", "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."captacion_uso" TO "authenticated", "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."citas" TO "authenticated";

GRANT SELECT ON TABLE "public"."citas" TO "bi_reader";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."citas" TO "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."franjas_horarias" TO "anon", "authenticated";

GRANT SELECT ON TABLE "public"."franjas_horarias" TO "bi_reader";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."franjas_horarias" TO "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inmobiliarias" TO "anon", "authenticated";

GRANT SELECT ON TABLE "public"."inmobiliarias" TO "bi_reader";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inmobiliarias" TO "postgres", "service_role";

REVOKE ALL ("banos") ON TABLE "public"."inmuebles" FROM "anon";

GRANT SELECT ("banos") ON TABLE "public"."inmuebles" TO "anon";

REVOKE ALL ("barrio") ON TABLE "public"."inmuebles" FROM "anon";

GRANT SELECT ("barrio") ON TABLE "public"."inmuebles" TO "anon";

REVOKE ALL ("ciudad") ON TABLE "public"."inmuebles" FROM "anon";

GRANT SELECT ("ciudad") ON TABLE "public"."inmuebles" TO "anon";

REVOKE ALL ("created_at") ON TABLE "public"."inmuebles" FROM "anon";

GRANT SELECT ("created_at") ON TABLE "public"."inmuebles" TO "anon";

REVOKE ALL ("descripcion") ON TABLE "public"."inmuebles" FROM "anon";

GRANT SELECT ("descripcion") ON TABLE "public"."inmuebles" TO "anon";

REVOKE ALL ("direccion") ON TABLE "public"."inmuebles" FROM "anon";

GRANT SELECT ("direccion") ON TABLE "public"."inmuebles" TO "anon";

REVOKE ALL ("estado") ON TABLE "public"."inmuebles" FROM "anon";

GRANT SELECT ("estado") ON TABLE "public"."inmuebles" TO "anon";

REVOKE ALL ("habitaciones") ON TABLE "public"."inmuebles" FROM "anon";

GRANT SELECT ("habitaciones") ON TABLE "public"."inmuebles" TO "anon";

REVOKE ALL ("id") ON TABLE "public"."inmuebles" FROM "anon";

GRANT SELECT ("id") ON TABLE "public"."inmuebles" TO "anon";

REVOKE ALL ("imagenes") ON TABLE "public"."inmuebles" FROM "anon";

GRANT SELECT ("imagenes") ON TABLE "public"."inmuebles" TO "anon";

REVOKE ALL ("inmobiliaria_id") ON TABLE "public"."inmuebles" FROM "anon";

GRANT SELECT ("inmobiliaria_id") ON TABLE "public"."inmuebles" TO "anon";

REVOKE ALL ("precio") ON TABLE "public"."inmuebles" FROM "anon";

GRANT SELECT ("precio") ON TABLE "public"."inmuebles" TO "anon";

REVOKE ALL ("tipo_inmueble") ON TABLE "public"."inmuebles" FROM "anon";

GRANT SELECT ("tipo_inmueble") ON TABLE "public"."inmuebles" TO "anon";

REVOKE ALL ("tipo_transaccion") ON TABLE "public"."inmuebles" FROM "anon";

GRANT SELECT ("tipo_transaccion") ON TABLE "public"."inmuebles" TO "anon";

REVOKE ALL ("titulo") ON TABLE "public"."inmuebles" FROM "anon";

GRANT SELECT ("titulo") ON TABLE "public"."inmuebles" TO "anon";

REVOKE ALL ("unidad") ON TABLE "public"."inmuebles" FROM "anon";

GRANT SELECT ("unidad") ON TABLE "public"."inmuebles" TO "anon";

REVOKE ALL ON TABLE "public"."inmuebles" FROM "anon";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inmuebles" TO "anon";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inmuebles" TO "authenticated";

GRANT SELECT ON TABLE "public"."inmuebles" TO "bi_reader";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inmuebles" TO "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."integraciones_mercadolibre" TO "authenticated", "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventarios" TO "anon", "authenticated";

GRANT SELECT ON TABLE "public"."inventarios" TO "bi_reader";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventarios" TO "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."solicitudes_apertura" TO "authenticated";

GRANT SELECT ON TABLE "public"."solicitudes_apertura" TO "bi_reader";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."solicitudes_apertura" TO "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tareas" TO "anon", "authenticated";

GRANT SELECT ON TABLE "public"."tareas" TO "bi_reader";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tareas" TO "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."usuarios" TO "anon", "authenticated";

GRANT SELECT ON TABLE "public"."usuarios" TO "bi_reader";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."usuarios" TO "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."webhook_logs" TO "anon", "authenticated";

GRANT SELECT ON TABLE "public"."webhook_logs" TO "bi_reader";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."webhook_logs" TO "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."franjas_inmuebles" TO "anon", "authenticated";

GRANT SELECT ON TABLE "public"."franjas_inmuebles" TO "bi_reader";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."franjas_inmuebles" TO "postgres", "service_role";

SELECT cron.schedule_in_database('tarea-actualizar-inmuebles', '0 11 * * 1-6', 'SELECT public.crear_tarea_actualizar_inmuebles()', 'postgres', NULL, true);

