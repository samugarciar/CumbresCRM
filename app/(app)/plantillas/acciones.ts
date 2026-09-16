'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { createClient } from '@/lib/supabase/server';
import type { Resultado } from '@/app/(app)/contactos/[id]/acciones';

const esquema = z.object({
  id: z.string().uuid().nullable(),
  nombre: z.string().trim().min(1, 'La plantilla necesita un nombre').max(120),
  cuerpo: z.string().trim().min(1, 'La plantilla está vacía').max(4000),
  categoria: z.enum(['utilidad', 'marketing']),
});

/**
 * Guarda una plantilla, nueva o existente.
 *
 * Las variables NO se validan aquí: lo hace un CHECK en la base. Si una
 * plantilla menciona `{{descuento}}` —que no existe— tiene que reventar
 * al guardarla y no delante de un cliente, y esa garantía vale más en la
 * base que en un formulario que alguien puede saltarse.
 */
export async function guardarPlantilla(
  id: string | null,
  nombre: string,
  cuerpo: string,
  categoria: string
): Promise<Resultado> {
  const v = esquema.safeParse({ id, nombre, cuerpo, categoria });
  if (!v.success) return { ok: false, error: v.error.issues[0].message };

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

  const crm = supabase.schema('crm');
  const { error } = v.data.id
    ? await crm
        .from('plantillas')
        .update({
          nombre: v.data.nombre,
          cuerpo: v.data.cuerpo,
          categoria: v.data.categoria,
          updated_at: new Date().toISOString(),
        })
        .eq('id', v.data.id)
    : await crm.from('plantillas').insert({
        inmobiliaria_id: perfil.inmobiliaria_id,
        nombre: v.data.nombre,
        cuerpo: v.data.cuerpo,
        categoria: v.data.categoria,
        creada_por: user.id,
      });

  if (error) {
    // El CHECK de variables devuelve 23514. Merece un mensaje que diga
    // qué hacer, no el error crudo de Postgres.
    if (error.code === '23514') {
      return {
        ok: false,
        error:
          'Hay una variable que no existe. Solo se pueden usar las de la lista de abajo.',
      };
    }
    if (error.code === '23505') {
      return { ok: false, error: 'Ya hay una plantilla con ese nombre.' };
    }
    if (error.code === '42501') {
      return {
        ok: false,
        error: 'Solo un administrador puede crear o editar plantillas.',
      };
    }
    return { ok: false, error: 'No se pudo guardar la plantilla.' };
  }

  revalidatePath('/plantillas');
  return { ok: true };
}

/** Se desactiva en vez de borrar: los envíos ya hechos apuntan a ella, y
 *  "con qué plantilla le escribimos" es una pregunta legítima. */
export async function archivarPlantilla(id: string): Promise<Resultado> {
  if (!z.string().uuid().safeParse(id).success) {
    return { ok: false, error: 'Plantilla desconocida.' };
  }
  const supabase = await createClient();
  const { error } = await supabase
    .schema('crm')
    .from('plantillas')
    .update({ activa: false })
    .eq('id', id);

  if (error) return { ok: false, error: 'No se pudo archivar.' };
  revalidatePath('/plantillas');
  return { ok: true };
}
