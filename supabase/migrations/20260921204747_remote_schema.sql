SET local check_function_bodies = off;

REVOKE ALL ON FUNCTION "public"."agente_comercial_pausado"(uuid) FROM "anon";

REVOKE ALL ON FUNCTION "public"."agente_comercial_pausado"(uuid) FROM "authenticated";

REVOKE ALL ON FUNCTION "public"."crear_tarea_actualizar_inmuebles"() FROM "anon";

REVOKE ALL ON FUNCTION "public"."crear_tarea_actualizar_inmuebles"() FROM "authenticated";

REVOKE ALL ON FUNCTION "public"."marcar_cita_realizada"(uuid) FROM "anon";

REVOKE ALL ON TABLE "public"."agente_comercial_conversaciones" FROM "anon";

REVOKE ALL ON TABLE "public"."agente_comercial_mensajes" FROM "anon";

REVOKE ALL ON TABLE "public"."agente_comercial_uso" FROM "anon";

REVOKE ALL ON TABLE "public"."agentes_config" FROM "anon";

REVOKE ALL ON TABLE "public"."bi_artefactos" FROM "anon";

REVOKE ALL ON TABLE "public"."bi_conversaciones" FROM "anon";

REVOKE ALL ON TABLE "public"."bi_mensajes" FROM "anon";

REVOKE ALL ON TABLE "public"."bi_uso" FROM "anon";

REVOKE ALL ON TABLE "public"."captacion_prospectos" FROM "anon";

REVOKE ALL ON TABLE "public"."captacion_uso" FROM "anon";

REVOKE ALL ON TABLE "public"."citas" FROM "anon";

REVOKE ALL ON TABLE "public"."integraciones_mercadolibre" FROM "anon";

REVOKE ALL ON TABLE "public"."solicitudes_apertura" FROM "anon";

ALTER TABLE "public"."agente_comercial_mensajes"
  DROP CONSTRAINT "agente_comercial_mensajes_rol_check";

ALTER TABLE "public"."agente_comercial_conversaciones"
  ADD COLUMN "referral_source_id" text;

ALTER TABLE "public"."agente_comercial_conversaciones"
  ADD COLUMN "referral_ctwa_clid" text;

ALTER TABLE "public"."agente_comercial_conversaciones"
  ADD COLUMN "referral" jsonb;

ALTER TABLE "public"."agente_comercial_mensajes"
  ADD COLUMN "wa_message_id" text;

ALTER TABLE "public"."inmobiliarias"
  ADD COLUMN "wa_phone_number_id" text;

ALTER TABLE "public"."agente_comercial_mensajes"
  ADD CONSTRAINT "agente_comercial_mensajes_rol_check" CHECK ((rol = ANY (ARRAY['usuario'::text, 'agente'::text, 'asesor'::text])));

CREATE INDEX agente_comercial_conversaciones_referral ON public.agente_comercial_conversaciones USING btree (referral_source_id)
  WHERE (referral_source_id IS NOT NULL);

CREATE UNIQUE INDEX agente_comercial_mensajes_wamid ON public.agente_comercial_mensajes USING btree (wa_message_id)
  WHERE (wa_message_id IS NOT NULL);

CREATE UNIQUE INDEX inmobiliarias_wa_phone_number_id ON public.inmobiliarias USING btree (wa_phone_number_id)
  WHERE (wa_phone_number_id IS NOT NULL);

COMMENT ON COLUMN "public"."agente_comercial_conversaciones"."referral_ctwa_clid" IS 'Click ID de click-to-WhatsApp. Es lo que permite cerrar el ciclo con el gasto de la campaña.';

COMMENT ON COLUMN "public"."agente_comercial_conversaciones"."referral_source_id" IS 'El identificador del anuncio de Meta que trajo a esta persona. Llega SOLO en el primer mensaje: si no se guarda ahí, no se recupera nunca.';

COMMENT ON COLUMN "public"."agente_comercial_mensajes"."rol" IS 'Quién habla: usuario (el cliente), agente (el bot), asesor (una persona del equipo escribiendo desde el CRM).';

COMMENT ON COLUMN "public"."agente_comercial_mensajes"."wa_message_id" IS 'El id de Meta (wamid). Evita duplicar cuando Meta reintenta el webhook, y es lo que casa los acuses de entrega con la fila que salió.';

COMMENT ON COLUMN "public"."inmobiliarias"."wa_phone_number_id" IS 'El phone_number_id de la Cloud API de Meta. Es como llega identificado el número en cada webhook entrante.';

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

