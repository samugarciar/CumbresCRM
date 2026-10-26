import 'server-only';

/**
 * El CRM pide, la plataforma escribe.
 *
 * Es la decisión 13: el CRM no habla con Meta ni escribe en `public`. Le
 * pide a la plataforma —que es dueña del canal y del número— que mande, y
 * ella guarda el mensaje donde ya viven los del bot. De ahí el trigger de
 * proyección lo trae de vuelta a `crm.actividades`, que es lo que cierra
 * el agujero de los cero salientes humanos.
 *
 * Todo el acoplamiento entre los dos repos vive en este fichero. Si algún
 * día el canal se muda, se cambia aquí y en ningún otro sitio.
 *
 * DESDE QUÉ LÍNEA (1 oct 2026, antes del paso 5)
 * Con una línea por embudo, el CRM dice por cuál quiere mandar: `desde`,
 * con el `phone_number_id` de Meta —la misma llave que usa
 * crm.credencial_linea()— y el embudo. La plataforma lo lee desde el 8 oct:
 * con `desde`, manda por esa línea o por ninguna. Sin él, por su número
 * por defecto. Contrato en la nota 9 del vault.
 *
 * LAS PLANTILLAS (contrato C2, 9 oct)
 * También las pide el CRM y las tramita la plataforma: el token de Meta de
 * cada línea vive en Vault y no sale de ahí. El CRM no guarda ningún token
 * de Meta.
 */

/** La URL de una ruta de la plataforma, aunque PLATAFORMA_URL traiga «/» al final. */
function urlPlataforma(ruta: string): string {
  return `${(process.env.PLATAFORMA_URL ?? '').replace(/\/+$/, '')}${ruta}`;
}

export interface ResultadoCanal {
  ok: boolean;
  /** El id de Meta. Es lo que casa los acuses con la fila de crm.envios. */
  waMessageId?: string;
  error?: string;
  /** Si el canal ni siquiera está montado todavía. */
  sinCanal?: boolean;
}

export function canalConfigurado(): boolean {
  return Boolean(process.env.PLATAFORMA_URL && process.env.CRM_ENVIO_TOKEN);
}

export async function enviarPorCanal(opciones: {
  inmobiliariaId: string;
  telefono: string;
  texto: string;
  envioId: string;
  /** Por qué línea mandar. Sin línea conectada, se omite y la plataforma usa la suya. */
  desde?: {
    waPhoneNumberId: string;
    embudo: string;
  };
  plantilla?: {
    nombre_meta: string;
    idioma: string;
    variables?: Record<string, string>;
  };
}): Promise<ResultadoCanal> {
  if (!canalConfigurado()) {
    return {
      ok: false,
      sinCanal: true,
      error:
        'El envío directo todavía no está conectado: falta mover el número a la Cloud API de Meta.',
    };
  }

  try {
    const r = await fetch(urlPlataforma('/api/whatsapp/enviar'), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-crm-token': process.env.CRM_ENVIO_TOKEN!,
      },
      body: JSON.stringify({
        inmobiliaria_id: opciones.inmobiliariaId,
        telefono: opciones.telefono,
        texto: opciones.texto,
        envio_id: opciones.envioId,
        // JSON.stringify omite las claves undefined: sin línea, el campo
        // no viaja y la plataforma ve exactamente lo de antes.
        desde: opciones.desde && {
          wa_phone_number_id: opciones.desde.waPhoneNumberId,
          embudo: opciones.desde.embudo,
        },
        plantilla: opciones.plantilla,
      }),
    });

    const datos = await r.json().catch(() => ({}));

    if (!r.ok) {
      // 503 es "el canal no está montado", que no es un fallo del mensaje.
      if (r.status === 503) {
        return { ok: false, sinCanal: true, error: datos?.error };
      }
      return { ok: false, error: datos?.error ?? `La plataforma respondió ${r.status}` };
    }

    return { ok: true, waMessageId: datos?.wa_message_id };
  } catch (error) {
    // Fallo de RED: no se sabe si salió. Quien llame NO debe marcarlo
    // fallido ni invitar a reenviar — el cliente podría recibirlo dos
    // veces. La fila se queda 'pendiente' y el acuse de Meta la resuelve.
    return {
      ok: false,
      error:
        error instanceof Error
          ? `No se pudo contactar con la plataforma: ${error.message}`
          : 'No se pudo contactar con la plataforma',
    };
  }
}

// ---------------------------------------------------------------------
// Contrato C2 · Plantillas de Meta, por línea
// ---------------------------------------------------------------------

/** Una plantilla tal como la tiene Meta en la WABA de una línea. */
export interface PlantillaMeta {
  id: string;
  name: string;
  status: string;
  category: string;
  language: string;
  components?: { type: string; text?: string }[];
  rejected_reason?: string;
}

/**
 * La plataforma pide a Meta una sola página de 100. Si vienen 100 puede
 * que falten: entonces la sincronización no retira nada (ver
 * crm.sincronizar_plantillas, p_completa).
 */
const PAGINA_DE_PLANTILLAS = 100;

function sinCanal(): { ok: false; sinCanal: true; error: string } {
  return {
    ok: false,
    sinCanal: true,
    error: 'El CRM todavía no está conectado con la plataforma: faltan PLATAFORMA_URL y CRM_ENVIO_TOKEN.',
  };
}

/** Las plantillas que hay en Meta para esta línea. */
export async function plantillasDeLinea(opciones: {
  inmobiliariaId: string;
  waPhoneNumberId: string;
}): Promise<{
  ok: boolean;
  plantillas?: PlantillaMeta[];
  completa?: boolean;
  error?: string;
  sinCanal?: boolean;
}> {
  if (!canalConfigurado()) return sinCanal();

  const consulta = new URLSearchParams({
    inmobiliaria_id: opciones.inmobiliariaId,
    wa_phone_number_id: opciones.waPhoneNumberId,
  });

  try {
    const r = await fetch(urlPlataforma(`/api/whatsapp/plantillas?${consulta}`), {
      headers: { 'x-crm-token': process.env.CRM_ENVIO_TOKEN! },
      cache: 'no-store',
    });
    const datos = await r.json().catch(() => ({}));
    if (!r.ok || !datos?.ok) {
      return { ok: false, error: datos?.error ?? `La plataforma respondió ${r.status}` };
    }
    const plantillas = (Array.isArray(datos.datos) ? datos.datos : []) as PlantillaMeta[];
    return { ok: true, plantillas, completa: plantillas.length < PAGINA_DE_PLANTILLAS };
  } catch (error) {
    return {
      ok: false,
      error:
        error instanceof Error
          ? `No se pudo contactar con la plataforma: ${error.message}`
          : 'No se pudo contactar con la plataforma',
    };
  }
}

/**
 * Borra la plantilla de la WABA de la línea (solo ese idioma). Si ya no
 * estaba en Meta también es ok: `existia` lo dice.
 */
export async function borrarPlantillaEnMeta(opciones: {
  inmobiliariaId: string;
  waPhoneNumberId: string;
  nombreMeta: string;
  idioma: string;
}): Promise<{ ok: boolean; existia?: boolean; error?: string; sinCanal?: boolean }> {
  if (!canalConfigurado()) return sinCanal();

  try {
    const r = await fetch(urlPlataforma('/api/whatsapp/plantillas'), {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        'x-crm-token': process.env.CRM_ENVIO_TOKEN!,
      },
      body: JSON.stringify({
        inmobiliaria_id: opciones.inmobiliariaId,
        wa_phone_number_id: opciones.waPhoneNumberId,
        nombre_meta: opciones.nombreMeta,
        idioma: opciones.idioma,
      }),
    });
    const datos = await r.json().catch(() => ({}));
    if (!r.ok || !datos?.ok) {
      return { ok: false, error: datos?.error ?? `La plataforma respondió ${r.status}` };
    }
    return { ok: true, existia: Boolean(datos.existia) };
  } catch (error) {
    return {
      ok: false,
      error:
        error instanceof Error
          ? `No se pudo contactar con la plataforma: ${error.message}`
          : 'No se pudo contactar con la plataforma',
    };
  }
}

/**
 * Crea la plantilla en la WABA de la línea y la manda a revisión de Meta.
 * Los ejemplos van por nombre de variable: Meta exige uno por cada una.
 */
export async function crearPlantillaEnMeta(opciones: {
  inmobiliariaId: string;
  waPhoneNumberId: string;
  nombreMeta: string;
  categoria: 'utilidad' | 'marketing';
  idioma: string;
  cuerpo: string;
  ejemplos: Record<string, string>;
}): Promise<{ ok: boolean; idMeta?: string; status?: string; error?: string; sinCanal?: boolean }> {
  if (!canalConfigurado()) return sinCanal();

  try {
    const r = await fetch(urlPlataforma('/api/whatsapp/plantillas'), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-crm-token': process.env.CRM_ENVIO_TOKEN!,
      },
      body: JSON.stringify({
        inmobiliaria_id: opciones.inmobiliariaId,
        wa_phone_number_id: opciones.waPhoneNumberId,
        nombre_meta: opciones.nombreMeta,
        categoria: opciones.categoria,
        idioma: opciones.idioma,
        cuerpo: opciones.cuerpo,
        ejemplos: opciones.ejemplos,
      }),
    });
    const datos = await r.json().catch(() => ({}));
    if (!r.ok || !datos?.ok) {
      return { ok: false, error: datos?.error ?? `La plataforma respondió ${r.status}` };
    }
    return { ok: true, idMeta: datos.id_meta, status: datos.status };
  } catch (error) {
    // Aquí sí se puede reintentar: crear la misma plantilla dos veces lo
    // rechaza Meta por nombre repetido, no le llega nada a ningún cliente.
    return {
      ok: false,
      error:
        error instanceof Error
          ? `No se pudo contactar con la plataforma: ${error.message}`
          : 'No se pudo contactar con la plataforma',
    };
  }
}
