'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { createClient } from '@/lib/supabase/server';

export interface Resultado {
  ok: boolean;
  error?: string;
}

// Se valida en el servidor aunque el formulario ya valide: el cliente es
// una sugerencia, no una garantía.
const esquemaNota = z.object({
  contactoId: z.string().uuid(),
  cuerpo: z.string().trim().min(1, 'La nota está vacía').max(5000),
});

const esquemaContacto = z.object({
  contactoId: z.string().uuid(),
  nombre: z.string().trim().max(200).nullable(),
  tipo: z.enum(['cliente', 'propietario', 'ambos']),
});

/**
 * Deja una nota en el timeline.
 *
 * Escribe con el token del usuario, NO con la service role: así la RLS
 * decide si puede, y `creado_por` queda con su id. Una nota que no sabe
 * quién la escribió no sirve como memoria de equipo.
 */
export async function agregarNota(
  contactoId: string,
  cuerpo: string
): Promise<Resultado> {
  const validado = esquemaNota.safeParse({ contactoId, cuerpo });
  if (!validado.success) {
    return { ok: false, error: validado.error.issues[0].message };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { ok: false, error: 'Tu sesión expiró. Vuelve a entrar.' };

  // La inmobiliaria se toma del contacto, no del formulario: si viniera
  // del cliente, sería un parámetro manipulable para escribir en otra.
  const { data: contacto } = await supabase
    .schema('crm')
    .from('contactos')
    .select('inmobiliaria_id')
    .eq('id', validado.data.contactoId)
    .single();

  if (!contacto) return { ok: false, error: 'Ese contacto ya no existe.' };

  const { error } = await supabase
    .schema('crm')
    .from('actividades')
    .insert({
      inmobiliaria_id: contacto.inmobiliaria_id,
      contacto_id: validado.data.contactoId,
      tipo: 'nota',
      origen: 'humano',
      cuerpo: validado.data.cuerpo,
      creado_por: user.id,
    });

  if (error) return { ok: false, error: 'No se pudo guardar la nota.' };

  revalidatePath(`/contactos/${validado.data.contactoId}`);
  return { ok: true };
}

/** Edita los datos que una persona sí decide: nombre y tipo. */
export async function actualizarContacto(
  contactoId: string,
  nombre: string | null,
  tipo: string
): Promise<Resultado> {
  const validado = esquemaContacto.safeParse({
    contactoId,
    nombre: nombre?.trim() || null,
    tipo,
  });
  if (!validado.success) {
    return { ok: false, error: validado.error.issues[0].message };
  }

  const supabase = await createClient();
  const { error } = await supabase
    .schema('crm')
    .from('contactos')
    .update({ nombre: validado.data.nombre, tipo: validado.data.tipo })
    .eq('id', validado.data.contactoId);

  if (error) return { ok: false, error: 'No se pudo guardar el cambio.' };

  revalidatePath(`/contactos/${validado.data.contactoId}`);
  return { ok: true };
}

// Nota: las columnas `consentimiento`, `consentimiento_at` y
// `consentimiento_canal` siguen existiendo en crm.contactos. La
// autorización de tratamiento de datos la cubre el contrato con el
// cliente, así que no se pide desde la interfaz — pero el dato tiene
// dónde guardarse el día que haga falta registrarlo por contacto.

/**
 * Marca el historial como leído hasta ahora.
 *
 * Se llama desde un componente cliente al abrir la ficha, NO durante el
 * render del servidor: si se hiciera al renderizar, una precarga del
 * navegador o un rastreador marcarían como leído algo que nadie miró.
 */
export async function marcarLeido(contactoId: string): Promise<void> {
  if (!z.string().uuid().safeParse(contactoId).success) return;
  const supabase = await createClient();
  await supabase.schema('crm').rpc('marcar_leido', { p_contacto_id: contactoId });
}

/**
 * Rellena una plantilla con los datos reales de una persona.
 *
 * El relleno ocurre en la BASE, no aquí: hoy lo usa esta pantalla, mañana
 * el agente. Dos renderizadores es como el asesor y el bot acaban
 * mandando textos distintos con la misma plantilla.
 */
export async function renderizar(
  plantillaId: string,
  contactoId: string,
  inmuebleId: string | null,
  asesor: string | null
): Promise<string | null> {
  const uuid = z.string().uuid();
  if (!uuid.safeParse(plantillaId).success) return null;
  if (!uuid.safeParse(contactoId).success) return null;

  const supabase = await createClient();
  const { data, error } = await supabase.schema('crm').rpc('render_plantilla', {
    p_plantilla_id: plantillaId,
    p_contacto_id: contactoId,
    p_inmueble_id: inmuebleId && uuid.safeParse(inmuebleId).success ? inmuebleId : undefined,
    p_asesor: asesor ?? undefined,
  });

  return error ? null : data;
}

const esquemaBot = z.object({
  contactoId: z.string().uuid(),
  activo: z.boolean(),
});

/**
 * Apaga o enciende el bot para esta persona.
 *
 * No es un UPDATE suelto: pasa por crm.cambiar_bot(), que además del
 * cambio escribe la línea en el historial. Si esto fueran dos escrituras
 * desde aquí, un fallo entre medias dejaría el bot callado sin que el
 * timeline lo contara — y nadie sabría por qué no contesta.
 */
export async function cambiarBot(
  contactoId: string,
  activo: boolean
): Promise<Resultado> {
  const validado = esquemaBot.safeParse({ contactoId, activo });
  if (!validado.success) return { ok: false, error: 'Petición inválida.' };

  const supabase = await createClient();
  const { data, error } = await supabase.schema('crm').rpc('cambiar_bot', {
    p_contacto_id: validado.data.contactoId,
    p_activo: validado.data.activo,
  });

  if (error) return { ok: false, error: 'No se pudo cambiar el bot.' };
  // `false` = la RLS no lo dejó ver, o ya no existe. La función responde
  // lo mismo en los dos casos a propósito.
  if (data === false) {
    return { ok: false, error: 'Ese lead ya no está disponible.' };
  }

  revalidatePath(`/contactos/${validado.data.contactoId}`);
  return { ok: true };
}

/**
 * Hacerse responsable de un lead, o pasárselo a otro.
 *
 * Sin `asesorId` significa "me encargo yo". La función de la base deja el
 * cambio escrito en el historial: cambiar de responsable sin que conste
 * es de las cosas que después nadie consigue explicar.
 */
export async function asignarLead(
  contactoId: string,
  asesorId?: string | null
): Promise<Resultado> {
  if (!z.string().uuid().safeParse(contactoId).success) {
    return { ok: false, error: 'Petición inválida.' };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { ok: false, error: 'Tu sesión expiró. Vuelve a entrar.' };

  const destino = asesorId === undefined ? user.id : asesorId;
  if (destino !== null && !z.string().uuid().safeParse(destino).success) {
    return { ok: false, error: 'Petición inválida.' };
  }

  // Omitir el parámetro es lo que significa "sin responsable": la función
  // lo tiene con DEFAULT NULL, y supabase-js no serializa las claves
  // `undefined`.
  const { data, error } = await supabase.schema('crm').rpc('asignar_lead', {
    p_contacto_id: contactoId,
    p_asesor_id: destino ?? undefined,
  });

  if (error) return { ok: false, error: 'No se pudo asignar.' };
  if (data === false) {
    return { ok: false, error: 'Ese lead no tiene una oportunidad abierta.' };
  }

  revalidatePath(`/contactos/${contactoId}`);
  return { ok: true };
}
