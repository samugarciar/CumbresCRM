'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { createClient } from '@/lib/supabase/server';
import type { Resultado } from '@/app/(app)/contactos/[id]/acciones';
import {
  sincronizarPlantillasWABA,
  enviarPlantillaRevisionMeta,
} from '@/lib/meta/plantillas';

const esquema = z.object({
  id: z.string().uuid().nullable(),
  nombre: z.string().trim().min(1, 'La plantilla necesita un nombre').max(120),
  cuerpo: z.string().trim().min(1, 'La plantilla está vacía').max(4000),
  categoria: z.string().trim().min(1),
  tipo: z.enum(['chat', 'whatsapp']).default('whatsapp'),
  nombreMeta: z.string().trim().nullable().optional(),
  idioma: z.string().trim().default('es'),
});

export async function guardarPlantilla(
  id: string | null,
  nombre: string,
  cuerpo: string,
  categoria: string,
  tipo: 'chat' | 'whatsapp' = 'whatsapp',
  nombreMeta: string | null = null,
  idioma: string = 'es'
): Promise<Resultado> {
  const v = esquema.safeParse({
    id,
    nombre,
    cuerpo,
    categoria,
    tipo,
    nombreMeta,
    idioma,
  });
  if (!v.success) return { ok: false, error: v.error.issues[0].message };

  // Reglas de negocio por tipo:
  if (v.data.tipo === 'whatsapp') {
    if (!['utilidad', 'marketing'].includes(v.data.categoria)) {
      return {
        ok: false,
        error: 'Las plantillas de WhatsApp para Meta deben ser de Utilidad o Marketing.',
      };
    }
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

  const crm = supabase.schema('crm');

  // Si es tipo chat, estado_meta queda automáticamente en 'aprobada' (aprobada local)
  // Si es tipo whatsapp, si no tiene estado se deja en 'borrador'
  const estadoMetaInicial = v.data.tipo === 'chat' ? 'aprobada' : 'borrador';

  const datosComunes = {
    nombre: v.data.nombre,
    cuerpo: v.data.cuerpo,
    categoria: v.data.categoria,
    tipo: v.data.tipo,
    idioma: v.data.idioma,
    nombre_meta:
      v.data.tipo === 'whatsapp'
        ? v.data.nombreMeta ||
          v.data.nombre.toLowerCase().replace(/[^a-z0-9_]/g, '_').slice(0, 50)
        : null,
  };

  const { error } = v.data.id
    ? await crm
        .from('plantillas')
        .update({
          ...datosComunes,
          updated_at: new Date().toISOString(),
        })
        .eq('id', v.data.id)
    : await crm.from('plantillas').insert({
        inmobiliaria_id: perfil.inmobiliaria_id,
        creada_por: user.id,
        estado_meta: estadoMetaInicial,
        ...datosComunes,
      });

  if (error) {
    if (error.code === '23514') {
      return {
        ok: false,
        error:
          'Hay una variable que no existe o una restricción de formato. Revisa las variables disponibles.',
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
    return { ok: false, error: `No se pudo guardar la plantilla: ${error.message}` };
  }

  revalidatePath('/plantillas');
  return { ok: true };
}

/**
 * Envía una plantilla de WhatsApp a revisión ante Meta Graph API
 */
export async function enviarAMeta(plantillaId: string): Promise<Resultado> {
  const supabase = await createClient();
  const crm = supabase.schema('crm');

  const { data: plantilla, error } = await crm
    .from('plantillas')
    .select('id, nombre, cuerpo, categoria, tipo, nombre_meta, idioma')
    .eq('id', plantillaId)
    .single();

  if (error || !plantilla) {
    return { ok: false, error: 'No se encontró la plantilla.' };
  }

  if (plantilla.tipo !== 'whatsapp') {
    return { ok: false, error: 'Solo las plantillas de tipo WhatsApp se envían a Meta.' };
  }

  const nombreMeta =
    plantilla.nombre_meta ||
    plantilla.nombre.toLowerCase().replace(/[^a-z0-9_]/g, '_').slice(0, 50);

  const resMeta = await enviarPlantillaRevisionMeta({
    nombreMeta,
    cuerpo: plantilla.cuerpo,
    categoria: plantilla.categoria === 'marketing' ? 'marketing' : 'utilidad',
    idioma: plantilla.idioma || 'es',
  });

  if (!resMeta.ok) {
    return {
      ok: false,
      error: resMeta.error || 'Meta rechazó la solicitud de revisión.',
    };
  }

  // Si Meta aceptó la solicitud, la marcamos como 'enviada'
  await crm
    .from('plantillas')
    .update({
      estado_meta: 'enviada',
      nombre_meta: nombreMeta,
      motivo_rechazo_meta: null,
      updated_at: new Date().toISOString(),
    })
    .eq('id', plantillaId);

  revalidatePath('/plantillas');
  return { ok: true };
}

/**
 * Sincroniza todas las plantillas de la WABA de Meta hacia el CRM
 */
export async function sincronizarConMeta(): Promise<Resultado & { detalles?: string }> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { ok: false, error: 'Tu sesión expiró.' };

  const { data: perfil } = await supabase
    .from('usuarios')
    .select('inmobiliaria_id')
    .eq('id', user.id)
    .single();
  if (!perfil) return { ok: false, error: 'No se encontró tu perfil.' };

  const res = await sincronizarPlantillasWABA(perfil.inmobiliaria_id);

  if (!res.ok) {
    return {
      ok: false,
      error: res.error || 'No se pudo sincronizar con Meta.',
    };
  }

  revalidatePath('/plantillas');
  const d = res.datos;
  const msg = d
    ? `${d.total} plantillas en Meta (${d.agregadas} nuevas incorporadas, ${d.actualizadas} estados actualizados).`
    : 'Sincronización completada.';

  return { ok: true, detalles: msg };
}

/** Se desactiva en vez de borrar: los envíos ya hechos apuntan a ella */
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
