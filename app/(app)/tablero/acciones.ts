'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { createClient } from '@/lib/supabase/server';
import type { Resultado } from '@/app/(app)/contactos/[id]/acciones';

const ETAPAS = [
  'nuevo',
  'contactado',
  'calificado',
  'visita_agendada',
  'visita_realizada',
  'en_estudio',
] as const;

const MOTIVOS = [
  'precio',
  'zona',
  'disponibilidad',
  'requisitos',
  'no_responde',
  'arrendo_con_otro',
  'duplicado',
  'otro',
] as const;

const esquemaMover = z.object({
  oportunidadId: z.string().uuid(),
  etapa: z.enum(ETAPAS),
  motivo: z.string().trim().max(500).nullable(),
});

const esquemaCerrar = z
  .object({
    oportunidadId: z.string().uuid(),
    estado: z.enum(['ganada', 'perdida']),
    motivoPerdida: z.enum(MOTIVOS).nullable(),
    inmuebleId: z.string().uuid().nullable(),
    nota: z.string().trim().max(500).nullable(),
  })
  // La misma regla que el CHECK de la base, repetida aquí para poder dar
  // un mensaje en español en vez de un error de Postgres.
  .refine((v) => v.estado !== 'perdida' || v.motivoPerdida !== null, {
    message: 'Para dar por perdida una oportunidad hace falta decir por qué.',
  });

/**
 * Mueve una tarjeta de columna.
 *
 * Va por `crm.mover_etapa`, que es SECURITY INVOKER: la RLS decide si
 * esta persona puede tocar esta oportunidad, y la función escribe sola
 * la línea en crm.transiciones. No se hace un UPDATE directo desde aquí
 * precisamente para que no exista forma de mover una tarjeta sin dejar
 * rastro de quién la movió.
 *
 * Permite ir hacia atrás a propósito: corregir un error del sistema es
 * el caso de uso, y para eso está el historial.
 */
export async function moverEtapa(
  oportunidadId: string,
  etapa: string,
  motivo: string | null = null
): Promise<Resultado> {
  const validado = esquemaMover.safeParse({ oportunidadId, etapa, motivo });
  if (!validado.success) {
    return { ok: false, error: validado.error.issues[0].message };
  }

  const supabase = await createClient();
  const { error } = await supabase.schema('crm').rpc('mover_etapa', {
    p_oportunidad_id: validado.data.oportunidadId,
    p_etapa: validado.data.etapa,
    p_motivo: validado.data.motivo ?? undefined,
  });

  if (error) {
    return { ok: false, error: 'No se pudo mover la tarjeta.' };
  }

  revalidatePath('/tablero');
  return { ok: true };
}

/**
 * Cierra una oportunidad como ganada o perdida.
 *
 * Ganada pide el inmueble: además de medir, deja el vínculo
 * persona↔inmueble que la bandeja de reactivación necesitará. Perdida
 * exige motivo, que es el único dato que explica por qué el embudo se
 * estrecha donde se estrecha.
 */
export async function cerrarOportunidad(
  oportunidadId: string,
  estado: string,
  motivoPerdida: string | null,
  inmuebleId: string | null,
  nota: string | null
): Promise<Resultado> {
  const validado = esquemaCerrar.safeParse({
    oportunidadId,
    estado,
    motivoPerdida: motivoPerdida || null,
    inmuebleId: inmuebleId || null,
    nota: nota?.trim() || null,
  });
  if (!validado.success) {
    return { ok: false, error: validado.error.issues[0].message };
  }

  const supabase = await createClient();
  const { error } = await supabase.schema('crm').rpc('cerrar_oportunidad', {
    p_oportunidad_id: validado.data.oportunidadId,
    p_estado: validado.data.estado,
    p_motivo_perdida: validado.data.motivoPerdida ?? undefined,
    p_inmueble_id: validado.data.inmuebleId ?? undefined,
    p_nota: validado.data.nota ?? undefined,
  });

  if (error) {
    return { ok: false, error: 'No se pudo cerrar la oportunidad.' };
  }

  revalidatePath('/tablero');
  return { ok: true };
}
