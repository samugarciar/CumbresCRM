-- =====================================================================
-- La bandeja de reactivación.
--
-- POR QUÉ ESTA PANTALLA Y NO OTRA
-- La investigación de UX la llamó "probablemente la fuente de ingreso
-- más barata del proyecto", y las cifras la respaldan: 488 personas
-- consintieron, llevan más de dos semanas calladas y no han pedido salir.
-- De ellas, 255 DIJERON QUÉ BUSCABAN antes de callarse.
--
-- Escribirle a alguien que te contó lo que quería y lleva un mes en
-- silencio no es una campaña: es terminar una conversación que quedó a
-- medias.
--
-- LO QUE ESTA PANTALLA NO PUEDE HACER TODAVÍA, Y POR QUÉ
-- Enviar. Todo este público está FUERA de la ventana de 24 horas de
-- WhatsApp —por definición: llevan 14 días o más—, así que lo único
-- legal es una plantilla aprobada por Meta, y el canal propio es la fase
-- 5-B. Hasta entonces la pantalla prepara el mensaje relleno y el asesor
-- lo copia, igual que en la ficha. `crm.envios` sigue naciendo vacía:
-- copiar no es enviar.
-- =====================================================================

-- ---------------------------------------------------------------------
-- El idioma de la plantilla, que Meta exige en cada envío
--
-- Lo pide en la creación Y en el envío, y una plantilla aprobada en `es`
-- NO sirve para mandar con `es_CO`: son plantillas distintas para Meta.
-- Por eso conviene elegir uno y no volver a tocarlo — cambiar de idea
-- después obliga a pasar todo el catálogo por aprobación otra vez.
--
-- Se pone `es` y no `es_CO` a propósito: es el más común, el que menos
-- sorpresas da en la aprobación, y no obliga a nada regional que hoy no
-- estemos usando.
-- ---------------------------------------------------------------------
ALTER TABLE crm.plantillas
  ADD COLUMN idioma text NOT NULL DEFAULT 'es'
    CHECK (idioma ~ '^[a-z]{2}(_[A-Z]{2})?$');

COMMENT ON COLUMN crm.plantillas.idioma IS
  'Código de idioma de Meta. Una plantilla aprobada en `es` no se puede enviar como `es_CO`: para Meta son dos plantillas distintas.';

-- ---------------------------------------------------------------------
-- A quién llamar hoy, y con qué excusa
--
-- Se apoya en crm.publico_marketing(), que es la única puerta por la que
-- sale un lote: filtra el opt_out y exige consentimiento. Esta función
-- NO reimplementa ese filtro — si un día hay que añadir una condición
-- nueva, se añade allí y vale para todos los caminos a la vez.
--
-- ORDEN: del más callado al menos, igual que la rotación de inmuebles.
-- Va contra el instinto —lo reciente se atiende solo— y es justo el
-- motivo: al que lleva cuatro meses no le escribe nadie nunca.
--
-- `calzan` cuesta unos 9 ms por contacto (medido contra producción), así
-- que el coste es proporcional a LA PÁGINA y no al público entero: 222 ms
-- para 25 filas. Por eso la paginación no es un adorno, es la condición
-- para que esto sea viable.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.reactivables(
  p_dias   int DEFAULT 14,
  p_limite int DEFAULT 25,
  p_salto  int DEFAULT 0)
RETURNS TABLE (
  contacto_id   uuid,
  nombre        text,
  telefono_e164 text,
  dias_callado  int,
  ultima_actividad_at timestamptz,
  busca         text,
  calzan        int
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $react$
  WITH publico AS (
    SELECT * FROM crm.publico_marketing(p_dias, 5000)
     ORDER BY ultima_actividad_at ASC
     LIMIT p_limite OFFSET p_salto
  )
  SELECT
    p.contacto_id,
    p.nombre,
    p.telefono_e164,
    p.dias_callado,
    p.ultima_actividad_at,
    -- Lo que pidió, en una línea legible. NULL si nunca lo dijo: la
    -- pantalla lo distingue, porque a quien no dijo nada hay que
    -- escribirle otra cosa.
    (SELECT concat_ws(' · ',
              NULLIF(btrim(concat_ws(' en ',
                array_to_string(r.tipo_inmueble, ' o '),
                COALESCE(array_to_string(r.barrios, ', '), r.ciudad))), ''),
              CASE WHEN r.precio_max IS NOT NULL
                   THEN 'hasta $' || to_char(r.precio_max, 'FM999,999,999') END,
              CASE WHEN r.habitaciones_min IS NOT NULL
                   THEN r.habitaciones_min || '+ hab' END)
       FROM crm.requerimientos r
      WHERE r.contacto_id = p.contacto_id AND r.activo
      ORDER BY r.updated_at DESC LIMIT 1),
    -- Cuántos inmuebles del catálogo le calzan HOY. Es la diferencia
    -- entre "hace mucho que no hablamos" y "apareció lo que buscabas".
    (SELECT count(*)::int FROM crm.inmuebles_para(
       p.contacto_id, 50::smallint, 20, true))
  FROM publico p
  ORDER BY p.ultima_actividad_at ASC;
$react$;

COMMENT ON FUNCTION crm.reactivables(int, int, int) IS
  'A quién reactivar hoy, del más callado al menos, con lo que pidió y cuántos inmuebles le calzan ahora. Pasa por publico_marketing: nunca se salta el opt_out.';

GRANT EXECUTE ON FUNCTION crm.reactivables(int, int, int) TO authenticated;

-- ---------------------------------------------------------------------
-- Cuántos hay en total, para poder paginar de verdad
--
-- Aparte y no dentro, porque contar es barato y traer la página no.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.reactivables_total(p_dias int DEFAULT 14)
RETURNS int
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $tot$
  SELECT count(*)::int FROM crm.publico_marketing(p_dias, 100000);
$tot$;

GRANT EXECUTE ON FUNCTION crm.reactivables_total(int) TO authenticated;
