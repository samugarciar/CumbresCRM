'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { createClient } from '@/lib/supabase/server';
import type { Resultado } from '@/app/(app)/contactos/[id]/acciones';

const esquemaTarea = z.object({
  contactoId: z.string().uuid().nullable(),
  titulo: z.string().trim().min(1, 'La tarea necesita un título').max(200),
  // Se acepta la fecha como texto del formulario y se valida aquí: el
  // cliente es una sugerencia, no una garantía.
  venceAt: z.string().min(1, 'Hace falta una fecha'),
});

/**
 * Crea una tarea.
 *
 * `vence_at` es obligatorio porque una tarea sin fecha no es una tarea, es
 * una intención — y sin fecha no se puede ordenar un día, que es lo único
 * que esta pantalla hace.
 */
export async function crearTarea(
  contactoId: string | null,
  titulo: string,
  venceAt: string
): Promise<Resultado> {
  const validado = esquemaTarea.safeParse({ contactoId, titulo, venceAt });
  if (!validado.success) {
    return { ok: false, error: validado.error.issues[0].message };
  }

  const fecha = new Date(validado.data.venceAt);
  if (Number.isNaN(fecha.getTime())) {
    return { ok: false, error: 'Esa fecha no se entiende.' };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { ok: false, error: 'Tu sesión expiró. Vuelve a entrar.' };

  const { data: perfil } = await supabase
    .from('usuarios')
    .select('inmobiliaria_id')
    .eq('id', user.id)
    .single();
  if (!perfil) return { ok: false, error: 'No se encontró tu perfil.' };

  const { error } = await supabase
    .schema('crm')
    .from('tareas')
    .insert({
      inmobiliaria_id: perfil.inmobiliaria_id,
      contacto_id: validado.data.contactoId,
      titulo: validado.data.titulo,
      vence_at: fecha.toISOString(),
      asignado_a: user.id,
      creado_por: user.id,
    });

  if (error) return { ok: false, error: 'No se pudo guardar la tarea.' };

  revalidatePath('/mi-dia');
  if (validado.data.contactoId) {
    revalidatePath(`/contactos/${validado.data.contactoId}`);
  }
  return { ok: true };
}

/** Se marca con fecha en vez de borrar: "qué se hizo ayer" es una
 *  pregunta que alguien va a hacer. */
export async function completarTarea(tareaId: string): Promise<Resultado> {
  if (!z.string().uuid().safeParse(tareaId).success) {
    return { ok: false, error: 'Tarea desconocida.' };
  }
  const supabase = await createClient();
  const { error } = await supabase
    .schema('crm')
    .rpc('completar_tarea', { p_tarea_id: tareaId });

  if (error) return { ok: false, error: 'No se pudo marcar como hecha.' };

  revalidatePath('/mi-dia');
  return { ok: true };
}
