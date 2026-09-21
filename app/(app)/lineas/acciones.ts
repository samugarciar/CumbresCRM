'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { createClient } from '@/lib/supabase/server';

export interface Resultado {
  ok: boolean;
  error?: string;
}

const esquema = z.object({
  embudo: z.enum(['comercial', 'administrativa', 'captacion']),
  nombre: z.string().trim().min(1, 'Ponle un nombre').max(60),
  // El id de Meta, no el teléfono. Son dígitos y es largo; la confusión
  // entre los dos es el error más común al configurar esto.
  waPhoneNumberId: z
    .string()
    .trim()
    .regex(/^\d{6,25}$/, 'El phone number ID de Meta son solo dígitos'),
  telefono: z
    .string()
    .trim()
    .regex(/^\+\d{8,15}$/, 'El teléfono va en formato internacional, con +')
    .optional()
    .or(z.literal('')),
});

/**
 * Registrar o actualizar la línea de un embudo.
 *
 * Una línea activa por embudo, que lo garantiza un índice único parcial:
 * dos líneas activas para lo mismo dejarían sin respuesta la pregunta
 * "¿por cuál le escribo?". Por eso esto actualiza la que haya en vez de
 * crear otra.
 */
export async function guardarLinea(
  embudo: string,
  nombre: string,
  waPhoneNumberId: string,
  telefono: string
): Promise<Resultado> {
  const v = esquema.safeParse({ embudo, nombre, waPhoneNumberId, telefono });
  if (!v.success) {
    return { ok: false, error: v.error.issues[0].message };
  }

  const supabase = await createClient();
  const crm = supabase.schema('crm');

  const { data: usuario } = await supabase.auth.getUser();
  if (!usuario.user) return { ok: false, error: 'Tu sesión expiró. Vuelve a entrar.' };

  const { data: perfil } = await supabase
    .from('usuarios')
    .select('inmobiliaria_id')
    .eq('id', usuario.user.id)
    .single();

  if (!perfil?.inmobiliaria_id) {
    return { ok: false, error: 'No se pudo determinar tu inmobiliaria.' };
  }

  const { data: existente } = await crm
    .from('lineas')
    .select('id')
    .eq('embudo', v.data.embudo)
    .eq('activa', true)
    .maybeSingle();

  const campos = {
    nombre: v.data.nombre,
    wa_phone_number_id: v.data.waPhoneNumberId,
    telefono_e164: v.data.telefono || null,
  };

  const { error } = existente
    ? await crm.from('lineas').update(campos).eq('id', existente.id)
    : await crm
        .from('lineas')
        .insert({ inmobiliaria_id: perfil.inmobiliaria_id, embudo: v.data.embudo, ...campos });

  if (error) {
    // 23505 = ese phone_number_id ya está en otra línea. Es el error que
    // de verdad ocurre: pegar el mismo id en dos embudos.
    if (error.code === '23505') {
      return {
        ok: false,
        error: 'Ese phone number ID ya está asignado a otra línea.',
      };
    }
    return { ok: false, error: 'No se pudo guardar. ¿Eres administrador?' };
  }

  revalidatePath('/lineas');
  return { ok: true };
}
