'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { createClient } from '@/lib/supabase/server';
import type { Resultado } from '@/app/(app)/contactos/[id]/acciones';
import { borrarPlantillaEnMeta, crearPlantillaEnMeta, plantillasDeLinea } from '@/lib/canal';
import { ejemplosPara } from '@/lib/plantillas';

/**
 * Las plantillas de WhatsApp viven en la WABA de una línea (migración
 * 20261015180001). El CRM las redacta; tramitarlas con Meta lo hace la
 * plataforma (contrato C2), que es la que tiene el token de cada línea.
 */

const esquema = z.object({
  id: z.string().uuid().nullable(),
  nombre: z.string().trim().min(1, 'La plantilla necesita un nombre').max(120),
  cuerpo: z.string().trim().min(1, 'La plantilla está vacía').max(4000),
  categoria: z.string().trim().min(1),
  tipo: z.enum(['chat', 'whatsapp']).default('whatsapp'),
  nombreMeta: z
    .string()
    .trim()
    .regex(/^[a-z0-9_]{1,512}$/, 'El nombre en Meta solo admite minúsculas, números y guiones bajos')
    .nullable()
    .optional(),
  idioma: z.enum(['es', 'es_CO', 'en', 'en_US']).default('es'),
  waPhoneNumberId: z.string().trim().regex(/^\d{5,30}$/).nullable().optional(),
});

/** El usuario, su inmobiliaria y su rol, o el motivo por el que no sigue. */
async function quienSoy() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { supabase, error: 'Tu sesión expiró. Vuelve a entrar.' } as const;

  const { data: perfil } = await supabase
    .from('usuarios')
    .select('inmobiliaria_id, rol')
    .eq('id', user.id)
    .single();
  if (!perfil) return { supabase, error: 'No se encontró tu perfil.' } as const;

  return { supabase, user, perfil } as const;
}

/** La línea, si es activa y de esta inmobiliaria (la RLS esconde las ajenas). */
async function lineaActiva(
  supabase: Awaited<ReturnType<typeof createClient>>,
  waPhoneNumberId: string
) {
  const { data } = await supabase
    .schema('crm')
    .from('lineas')
    .select('wa_phone_number_id, nombre')
    .eq('wa_phone_number_id', waPhoneNumberId)
    .eq('activa', true)
    .maybeSingle();
  return data;
}

export async function guardarPlantilla(
  id: string | null,
  nombre: string,
  cuerpo: string,
  categoria: string,
  tipo: 'chat' | 'whatsapp' = 'whatsapp',
  nombreMeta: string | null = null,
  idioma: string = 'es',
  waPhoneNumberId: string | null = null
): Promise<Resultado & { id?: string }> {
  const v = esquema.safeParse({
    id,
    nombre,
    cuerpo,
    categoria,
    tipo,
    nombreMeta: nombreMeta || null,
    idioma,
    waPhoneNumberId: waPhoneNumberId || null,
  });
  if (!v.success) return { ok: false, error: v.error.issues[0].message };

  if (v.data.tipo === 'whatsapp' && !['utilidad', 'marketing'].includes(v.data.categoria)) {
    return {
      ok: false,
      error: 'Las plantillas de WhatsApp para Meta deben ser de Utilidad o Marketing.',
    };
  }

  const yo = await quienSoy();
  if ('error' in yo) return { ok: false, error: yo.error };
  const { supabase, user, perfil } = yo;
  const crm = supabase.schema('crm');

  const linea = v.data.tipo === 'whatsapp' ? (v.data.waPhoneNumberId ?? null) : null;
  if (linea && !(await lineaActiva(supabase, linea))) {
    return { ok: false, error: 'Esa línea no está activa o no es de esta inmobiliaria.' };
  }

  // Lo que ya está en Meta no se cambia desde aquí: el cuerpo, la
  // categoría, el idioma y la línea son los que Meta revisó. Cambiar uno
  // dejaría al CRM diciendo una cosa y a Meta mandando otra.
  let estadoActual: string | null = null;
  if (v.data.id) {
    const { data: actual } = await crm
      .from('plantillas')
      .select('tipo, estado_meta, cuerpo, categoria, idioma, nombre_meta, wa_phone_number_id')
      .eq('id', v.data.id)
      .maybeSingle();
    if (!actual) return { ok: false, error: 'No se encontró la plantilla.' };
    estadoActual = actual.estado_meta;

    if (actual.tipo === 'whatsapp' && ['enviada', 'aprobada'].includes(actual.estado_meta)) {
      const cambiaLoDeMeta =
        actual.cuerpo !== v.data.cuerpo ||
        actual.categoria !== v.data.categoria ||
        actual.idioma !== v.data.idioma ||
        (actual.nombre_meta ?? null) !== (v.data.nombreMeta ?? actual.nombre_meta ?? null) ||
        (actual.wa_phone_number_id ?? null) !== linea;
      if (cambiaLoDeMeta) {
        return {
          ok: false,
          error:
            'Esta plantilla ya está en Meta: solo se puede cambiar el título. Para cambiar el texto, crea otra.',
        };
      }
    }
  }

  const datosComunes = {
    nombre: v.data.nombre,
    cuerpo: v.data.cuerpo,
    categoria: v.data.categoria,
    tipo: v.data.tipo,
    idioma: v.data.idioma,
    wa_phone_number_id: linea,
    nombre_meta:
      v.data.tipo === 'whatsapp'
        ? v.data.nombreMeta ||
          v.data.nombre.toLowerCase().replace(/[^a-z0-9_]/g, '_').slice(0, 50)
        : null,
  };

  const resultado = v.data.id
    ? await crm
        .from('plantillas')
        .update({
          ...datosComunes,
          // Una rechazada que se corrige vuelve a borrador: hay que mandarla otra vez.
          ...(v.data.tipo === 'whatsapp' && estadoActual === 'rechazada'
            ? { estado_meta: 'borrador', motivo_rechazo_meta: null }
            : {}),
          updated_at: new Date().toISOString(),
        })
        .eq('id', v.data.id)
        .select('id')
        .single()
    : await crm
        .from('plantillas')
        .insert({
          inmobiliaria_id: perfil.inmobiliaria_id,
          creada_por: user.id,
          // Una de chat no pasa por Meta: queda lista de una vez.
          estado_meta: v.data.tipo === 'chat' ? 'aprobada' : 'borrador',
          ...datosComunes,
        })
        .select('id')
        .single();

  const { data: guardada, error } = resultado;

  if (error) {
    if (error.code === '23514') {
      return {
        ok: false,
        error:
          'Hay una variable que no existe o una restricción de formato. Revisa las variables disponibles.',
      };
    }
    if (error.code === '23505') {
      return {
        ok: false,
        error: 'Ya hay una plantilla con ese título o con ese nombre en Meta en esta línea.',
      };
    }
    if (error.code === '42501' || error.code === 'PGRST116') {
      return {
        ok: false,
        error: 'Solo un administrador puede crear o editar plantillas.',
      };
    }
    return { ok: false, error: `No se pudo guardar la plantilla: ${error.message}` };
  }

  revalidatePath('/plantillas');
  return { ok: true, id: guardada?.id as string | undefined };
}

/**
 * Manda una plantilla de WhatsApp a revisión de Meta, en la WABA de su
 * línea. Si es un borrador sin línea, se le asigna la que se elija aquí.
 */
export async function enviarAMeta(
  plantillaId: string,
  waPhoneNumberId: string | null = null
): Promise<Resultado> {
  if (!z.string().uuid().safeParse(plantillaId).success) {
    return { ok: false, error: 'Plantilla desconocida.' };
  }
  if (waPhoneNumberId && !/^\d{5,30}$/.test(waPhoneNumberId)) {
    return { ok: false, error: 'Línea desconocida.' };
  }

  const yo = await quienSoy();
  if ('error' in yo) return { ok: false, error: yo.error };
  const { supabase, perfil } = yo;

  // Antes de pedirle nada a Meta: crear la plantilla allá y no poder
  // anotarla aquí dejaría una plantilla en Meta que el CRM no conoce.
  if (perfil.rol !== 'admin') {
    return { ok: false, error: 'Solo un administrador manda plantillas a revisión.' };
  }

  const crm = supabase.schema('crm');
  const { data: plantilla } = await crm
    .from('plantillas')
    .select('id, nombre, cuerpo, categoria, tipo, nombre_meta, idioma, estado_meta, wa_phone_number_id')
    .eq('id', plantillaId)
    .maybeSingle();

  if (!plantilla) return { ok: false, error: 'No se encontró la plantilla.' };
  if (plantilla.tipo !== 'whatsapp') {
    return { ok: false, error: 'Solo las plantillas de WhatsApp se mandan a Meta.' };
  }
  if (!['borrador', 'rechazada'].includes(plantilla.estado_meta)) {
    return { ok: false, error: 'Esta plantilla ya está en Meta.' };
  }

  const linea = plantilla.wa_phone_number_id ?? waPhoneNumberId;
  if (!linea) {
    return { ok: false, error: 'Elige primero por qué línea va a salir esta plantilla.' };
  }
  if (!(await lineaActiva(supabase, linea))) {
    return { ok: false, error: 'Esa línea no está activa o no es de esta inmobiliaria.' };
  }

  const nombreMeta =
    plantilla.nombre_meta ||
    plantilla.nombre.toLowerCase().replace(/[^a-z0-9_]/g, '_').slice(0, 50);

  // Meta no admite dos plantillas con el mismo nombre e idioma en una WABA.
  const { data: repetida } = await crm
    .from('plantillas')
    .select('id')
    .eq('wa_phone_number_id', linea)
    .eq('nombre_meta', nombreMeta)
    .eq('idioma', plantilla.idioma ?? 'es')
    .eq('activa', true)
    .neq('id', plantilla.id)
    .maybeSingle();
  if (repetida) {
    return {
      ok: false,
      error: `Ya hay una plantilla «${nombreMeta}» en esa línea. Cambia el nombre en Meta.`,
    };
  }

  const r = await crearPlantillaEnMeta({
    inmobiliariaId: perfil.inmobiliaria_id,
    waPhoneNumberId: linea,
    nombreMeta,
    categoria: plantilla.categoria === 'marketing' ? 'marketing' : 'utilidad',
    idioma: plantilla.idioma || 'es',
    cuerpo: plantilla.cuerpo,
    ejemplos: ejemplosPara(plantilla.cuerpo),
  });

  if (!r.ok) {
    return { ok: false, error: r.error || 'Meta no aceptó la plantilla.' };
  }

  const { error } = await crm
    .from('plantillas')
    .update({
      estado_meta: 'enviada',
      nombre_meta: nombreMeta,
      wa_phone_number_id: linea,
      motivo_rechazo_meta: null,
      updated_at: new Date().toISOString(),
    })
    .eq('id', plantilla.id);

  if (error) {
    // Meta ya la tiene: la próxima sincronización la adopta por su nombre.
    return {
      ok: false,
      error: `Meta la recibió, pero no se pudo anotar aquí (${error.message}). Pulsa «Sincronizar con Meta».`,
    };
  }

  revalidatePath('/plantillas');
  return { ok: true };
}

/**
 * Trae de Meta el estado de las plantillas de cada línea activa y lo cruza
 * con las del CRM (crm.sincronizar_plantillas, con la RLS del admin).
 */
export async function sincronizarConMeta(): Promise<Resultado & { detalles?: string }> {
  const yo = await quienSoy();
  if ('error' in yo) return { ok: false, error: yo.error };
  const { supabase, perfil } = yo;

  if (perfil.rol !== 'admin') {
    return { ok: false, error: 'Solo un administrador sincroniza las plantillas.' };
  }

  const crm = supabase.schema('crm');
  const { data: lineas } = await crm
    .from('lineas')
    .select('wa_phone_number_id, nombre')
    .eq('activa', true)
    .not('wa_phone_number_id', 'is', null);

  if (!lineas?.length) {
    return {
      ok: false,
      error: 'No hay ninguna línea conectada: las plantillas de Meta viven en la cuenta de cada línea.',
    };
  }

  const partes: string[] = [];
  const omitidas: string[] = [];

  for (const linea of lineas) {
    const remotas = await plantillasDeLinea({
      inmobiliariaId: perfil.inmobiliaria_id,
      waPhoneNumberId: linea.wa_phone_number_id as string,
    });
    if (!remotas.ok) {
      partes.push(`${linea.nombre}: ${remotas.error ?? 'no se pudo consultar Meta'}`);
      continue;
    }

    const { data, error } = await crm.rpc('sincronizar_plantillas', {
      p_wa_phone_number_id: linea.wa_phone_number_id as string,
      p_remotas: JSON.parse(JSON.stringify(remotas.plantillas ?? [])),
      p_completa: remotas.completa ?? false,
    });
    if (error || !data) {
      partes.push(`${linea.nombre}: no se pudo anotar (${error?.message ?? 'sin respuesta'})`);
      continue;
    }

    const d = data as {
      total: number;
      agregadas: number;
      actualizadas: number;
      retiradas: number;
      omitidas: { nombre_meta: string; motivo: string }[];
    };
    partes.push(
      `${linea.nombre}: ${d.total} en Meta, ${d.agregadas} nuevas, ${d.actualizadas} actualizadas` +
        (d.retiradas ? `, ${d.retiradas} ya no estaban en Meta` : '')
    );
    for (const o of d.omitidas ?? []) omitidas.push(`${o.nombre_meta} (${o.motivo})`);
  }

  revalidatePath('/plantillas');
  return {
    ok: true,
    detalles:
      partes.join(' · ') +
      (omitidas.length ? `. No se trajeron: ${omitidas.join('; ')}.` : '.'),
  };
}

/**
 * Borra una plantilla. Si está en Meta (enviada, aprobada o rechazada),
 * primero allá: borrarla solo aquí la haría volver con la próxima
 * sincronización. Si ya se usó en algún envío, aquí se archiva en vez de
 * borrarse, porque esos envíos apuntan a ella.
 */
export async function borrarPlantilla(id: string): Promise<Resultado & { archivada?: boolean }> {
  if (!z.string().uuid().safeParse(id).success) {
    return { ok: false, error: 'Plantilla desconocida.' };
  }

  const yo = await quienSoy();
  if ('error' in yo) return { ok: false, error: yo.error };
  const { supabase, perfil } = yo;
  if (perfil.rol !== 'admin') {
    return { ok: false, error: 'Solo un administrador borra plantillas.' };
  }

  const crm = supabase.schema('crm');
  const { data: plantilla } = await crm
    .from('plantillas')
    .select('id, tipo, estado_meta, nombre_meta, idioma, wa_phone_number_id')
    .eq('id', id)
    .maybeSingle();
  if (!plantilla) return { ok: false, error: 'No se encontró la plantilla.' };

  // Una de una línea desconectada no vuelve con la sincronización (solo
  // mira las activas) y la plataforma ya no tiene con qué entrar a su
  // cuenta: esa se borra solo aquí.
  const enMeta =
    plantilla.tipo === 'whatsapp' &&
    ['enviada', 'aprobada', 'rechazada'].includes(plantilla.estado_meta) &&
    Boolean(plantilla.nombre_meta) &&
    Boolean(plantilla.wa_phone_number_id) &&
    Boolean(await lineaActiva(supabase, plantilla.wa_phone_number_id as string));

  if (enMeta) {
    const r = await borrarPlantillaEnMeta({
      inmobiliariaId: perfil.inmobiliaria_id,
      waPhoneNumberId: plantilla.wa_phone_number_id as string,
      nombreMeta: plantilla.nombre_meta as string,
      idioma: plantilla.idioma || 'es',
    });
    if (!r.ok) {
      return { ok: false, error: `No se pudo borrar en Meta: ${r.error ?? 'sin respuesta'}` };
    }
  }

  const { data: borradas, error } = await crm
    .from('plantillas')
    .delete()
    .eq('id', plantilla.id)
    .select('id');

  if (error?.code === '23503') {
    const { error: errorArchivo } = await crm
      .from('plantillas')
      .update({ activa: false, updated_at: new Date().toISOString() })
      .eq('id', plantilla.id);
    if (errorArchivo) {
      return {
        ok: false,
        error: enMeta
          ? 'Se borró en Meta, pero aquí no se pudo quitar. Inténtalo otra vez.'
          : 'No se pudo borrar.',
      };
    }
    revalidatePath('/plantillas');
    return { ok: true, archivada: true };
  }

  if (error || !borradas?.length) {
    return {
      ok: false,
      error: enMeta
        ? 'Se borró en Meta, pero aquí no se pudo quitar. Inténtalo otra vez.'
        : `No se pudo borrar${error ? `: ${error.message}` : '.'}`,
    };
  }

  revalidatePath('/plantillas');
  return { ok: true };
}
