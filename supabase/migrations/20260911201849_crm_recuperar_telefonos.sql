-- =====================================================================
-- crm.recuperar_telefonos_desde_herramientas
--
-- Recuperación puntual: unas 40 de las 226 personas que llegaron sin
-- teléfono SÍ lo dieron después, y quedó registrado en la bitácora de
-- herramientas del agente. Desde el 11 ago el agente pide el número
-- explícitamente cuando no lo tiene, y al llamar a `agendar_cita` o
-- `solicitar_apertura_de_agenda` lo pasa como argumento.
--
-- POR QUÉ VA APARTE Y NO DENTRO DEL BACKFILL
-- Depende de la forma del JSON `herramientas_usadas`, que es una bitácora
-- de DEPURACIÓN de otro repo, no un contrato. Aislarla aquí significa que
-- el día que n8n se arregle, esta función se borra y no hay que tocar
-- nada más.
--
-- QUÉ NO HACE, A PROPÓSITO
-- No lee teléfonos del texto libre del cliente. Un número suelto en una
-- conversación puede ser el de otra persona —el dueño, un familiar, un
-- amigo al que le pasan el contacto— y asignarlo fusionaría a dos seres
-- humanos. Solo se toma lo que el agente capturó como argumento de una
-- herramienta, que es una afirmación explícita de "este es su número".
--
-- Y descarta las conversaciones donde aparece MÁS DE UN número distinto:
-- esas son revisión humana, no automatización.
-- =====================================================================

CREATE OR REPLACE FUNCTION crm.recuperar_telefonos_desde_herramientas(
  p_inmobiliaria_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  r              record;
  v_recuperados  int := 0;
  v_ambiguos     int := 0;
  v_sin_contacto int := 0;
BEGIN
  FOR r IN
    WITH candidatos AS (
      SELECT c.id AS conv_id,
             COALESCE(c.kommo_contact_id,
                      (regexp_match(c.telefono, '^kommo-([0-9]+)$'))[1]) AS kommo_contact,
             crm.normalizar_telefono(h->'entrada'->>'cliente_telefono') AS tel
        FROM public.agente_comercial_conversaciones c
        JOIN public.agente_comercial_mensajes m ON m.conversacion_id = c.id
        CROSS JOIN LATERAL jsonb_array_elements(
          CASE WHEN jsonb_typeof(m.herramientas_usadas) = 'array'
               THEN m.herramientas_usadas ELSE '[]'::jsonb END) h
       WHERE c.inmobiliaria_id = p_inmobiliaria_id
         -- Solo las que no tienen teléfono utilizable.
         AND crm.normalizar_telefono(c.telefono) IS NULL
         AND h->>'nombre' IN ('agendar_cita', 'solicitar_apertura_de_agenda')
         AND crm.normalizar_telefono(h->'entrada'->>'cliente_telefono') IS NOT NULL
    )
    SELECT conv_id, kommo_contact,
           min(tel) AS tel,
           count(DISTINCT tel) AS distintos
      FROM candidatos
     WHERE kommo_contact IS NOT NULL
     GROUP BY conv_id, kommo_contact
  LOOP
    -- Más de un número en la misma conversación: no se decide solo.
    IF r.distintos > 1 THEN
      v_ambiguos := v_ambiguos + 1;
      CONTINUE;
    END IF;

    -- El contacto se localiza por la identidad de Kommo, que es la que
    -- el backfill ya le puso.
    INSERT INTO crm.identidades (inmobiliaria_id, contacto_id, tipo, valor, origen)
    SELECT p_inmobiliaria_id, i.contacto_id, 'telefono_e164', r.tel,
           'recuperado_de_herramientas'
      FROM crm.identidades i
     WHERE i.inmobiliaria_id = p_inmobiliaria_id
       AND i.tipo = 'kommo_contact'
       AND i.valor = r.kommo_contact
     LIMIT 1
    ON CONFLICT (inmobiliaria_id, tipo, valor) DO NOTHING;

    IF FOUND THEN
      v_recuperados := v_recuperados + 1;
    ELSE
      v_sin_contacto := v_sin_contacto + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'telefonos_recuperados', v_recuperados,
    'ambiguos_para_revision', v_ambiguos,
    'sin_contacto_o_ya_tenian', v_sin_contacto
  );
END $$;

COMMENT ON FUNCTION crm.recuperar_telefonos_desde_herramientas(uuid) IS
  'Recuperación puntual de teléfonos desde la bitácora de herramientas del agente. Borrable cuando n8n deje de escribir kommo-<id> en telefono.';
