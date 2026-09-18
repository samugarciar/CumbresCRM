'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { createClient } from '@/lib/supabase/server';

export interface Resultado {
  ok: boolean;
  error?: string;
}

/**
 * Registrar que alguien pidió que no le escribamos más.
 *
 * Está en ESTA pantalla y no escondida en la ficha porque es aquí donde
 * se decide a quién escribirle: el sitio donde se manda tiene que ser el
 * mismo donde se puede dejar de mandar.
 *
 * La función de la base deja rastro en el historial y no borra el
 * consentimiento — «consintió y luego pidió salir» y «nunca consintió»
 * no son lo mismo si alguien pregunta.
 */
export async function marcarOptOut(
  contactoId: string,
  motivo?: string
): Promise<Resultado> {
  if (!z.string().uuid().safeParse(contactoId).success) {
    return { ok: false, error: 'Petición inválida.' };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.schema('crm').rpc('marcar_opt_out', {
    p_contacto_id: contactoId,
    p_motivo: motivo?.trim() || undefined,
  });

  if (error) return { ok: false, error: 'No se pudo registrar.' };
  if (data === false) return { ok: false, error: 'Ese contacto ya no existe.' };

  revalidatePath('/reactivacion');
  return { ok: true };
}
