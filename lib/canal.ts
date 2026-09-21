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
 */

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
    const r = await fetch(`${process.env.PLATAFORMA_URL}/api/whatsapp/enviar`, {
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
