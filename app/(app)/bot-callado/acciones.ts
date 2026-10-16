'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { createClient } from '@/lib/supabase/server';

export interface Resultado {
  ok: boolean;
  error?: string;
}

const esquemaTelefono = z.string().trim().min(7).max(30);

/**
 * Le devuelve la voz al bot de alguien que no está en el CRM: la 324 por
 * Kommo, hasta el corte (paso 6). Esa gente no tiene ficha, así que el
 * botón vive en la lista y el freno se busca por teléfono.
 *
 * La RLS decide quién puede (admin y asesores de la misma inmobiliaria);
 * `false` significa que no había nada que encender o que no le tocaba.
 */
export async function encenderBotFreno(telefono: string): Promise<Resultado> {
  const validado = esquemaTelefono.safeParse(telefono);
  if (!validado.success) return { ok: false, error: 'Petición inválida.' };

  const supabase = await createClient();
  const { data, error } = await supabase.schema('crm').rpc('encender_bot_freno', {
    p_telefono: validado.data,
  });

  if (error) return { ok: false, error: 'No se pudo encender el bot.' };
  if (data === false) {
    return { ok: false, error: 'Ya estaba respondiendo, o no lo puedes encender.' };
  }

  revalidatePath('/bot-callado');
  return { ok: true };
}
