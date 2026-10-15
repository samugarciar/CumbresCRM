'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { createClient } from '@/lib/supabase/server';
import { MAX_FILAS } from '@/lib/envios-masivos';
import type { FilaResultado } from '@/lib/archivos';

/**
 * Las acciones de los envíos masivos. Todas llaman a una función de la
 * base con la sesión de quien está en la pantalla: la base decide quién
 * puede y qué (migración 20261015190001). Aquí solo se valida la forma.
 */

export interface ResultadoAccion {
  ok: boolean;
  error?: string;
}

/** El mensaje de la base cuando es para personas (22023, 42501); si no, uno genérico. */
function errorLegible(error: { code?: string; message?: string } | null, porDefecto: string): string {
  if (error && (error.code === '22023' || error.code === '42501') && error.message) {
    return error.message;
  }
  return porDefecto;
}

const esquemaCrear = z.object({
  nombre: z.string().trim().min(1, 'Ponle un nombre al envío').max(120),
  archivoNombre: z.string().trim().max(255).nullable(),
  columnas: z.array(z.string().max(200)).min(1).max(100),
  filas: z.array(z.record(z.string(), z.string().max(2000))).min(1).max(MAX_FILAS),
  columnaTelefono: z.string().min(1, 'Elige la columna del teléfono'),
  columnaNombre: z.string().nullable(),
  plantillaId: z.string().uuid('Elige la plantilla'),
  variables: z.record(z.string().regex(/^[a-z_]+$/), z.string()),
  abrirCaso: z.boolean(),
});

export type DatosEnvioMasivo = z.infer<typeof esquemaCrear>;

/** Del archivo al borrador. No crea contactos ni manda nada. */
export async function crearEnvioMasivo(
  datos: DatosEnvioMasivo
): Promise<ResultadoAccion & { id?: string }> {
  const v = esquemaCrear.safeParse(datos);
  if (!v.success) return { ok: false, error: v.error.issues[0].message };

  const supabase = await createClient();
  const { data, error } = await supabase.schema('crm').rpc('crear_envio_masivo', {
    p_nombre: v.data.nombre,
    // La base trata el texto vacío como «no hay».
    p_archivo_nombre: v.data.archivoNombre ?? '',
    p_columnas: v.data.columnas,
    p_filas: v.data.filas,
    p_columna_telefono: v.data.columnaTelefono,
    p_columna_nombre: v.data.columnaNombre ?? '',
    p_plantilla_id: v.data.plantillaId,
    p_variables: v.data.variables,
    p_abrir_caso: v.data.abrirCaso,
  });

  if (error || !data) {
    return { ok: false, error: errorLegible(error, 'No se pudo preparar el envío.') };
  }

  revalidatePath('/envios-masivos');
  return { ok: true, id: data as string };
}

const uuid = z.string().uuid();

/** Lanzar, con el número exacto de destinatarios como confirmación. */
export async function lanzarEnvioMasivo(id: string, confirmacion: number): Promise<ResultadoAccion> {
  if (!uuid.safeParse(id).success) return { ok: false, error: 'Envío desconocido.' };
  if (!Number.isInteger(confirmacion) || confirmacion < 1) {
    return { ok: false, error: 'Escribe cuántos destinatarios son.' };
  }

  const supabase = await createClient();
  const { error } = await supabase.schema('crm').rpc('lanzar_envio_masivo', {
    p_id: id,
    p_confirmacion: confirmacion,
  });
  if (error) return { ok: false, error: errorLegible(error, 'No se pudo lanzar el envío.') };

  revalidatePath('/envios-masivos');
  revalidatePath(`/envios-masivos/${id}`);
  return { ok: true };
}

export async function cambiarEstadoEnvioMasivo(
  id: string,
  accion: 'pausar' | 'reanudar' | 'cancelar'
): Promise<ResultadoAccion> {
  if (!uuid.safeParse(id).success) return { ok: false, error: 'Envío desconocido.' };
  if (!['pausar', 'reanudar', 'cancelar'].includes(accion)) {
    return { ok: false, error: 'Acción desconocida.' };
  }

  const supabase = await createClient();
  const { error } = await supabase.schema('crm').rpc('cambiar_estado_envio_masivo', {
    p_id: id,
    p_accion: accion,
  });
  if (error) return { ok: false, error: errorLegible(error, 'No se pudo cambiar el envío.') };

  revalidatePath('/envios-masivos');
  revalidatePath(`/envios-masivos/${id}`);
  return { ok: true };
}

const hhmm = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Hora inválida');

const esquemaAjustes = z.object({
  tamanoLote: z.number().int().min(1).max(250),
  minutosEntreLotes: z.number().int().min(1).max(1440),
  topeDiario: z.number().int().min(1).max(100000),
  frecuenciaDias: z.number().int().min(0).max(90),
  horario: z.object({
    zona: z.literal('America/Bogota'),
    franjas: z.record(z.enum(['1', '2', '3', '4', '5', '6', '7']), z.tuple([hhmm, hhmm])),
  }),
});

export async function ajustarEnvioMasivo(
  id: string,
  ajustes: z.infer<typeof esquemaAjustes>
): Promise<ResultadoAccion> {
  if (!uuid.safeParse(id).success) return { ok: false, error: 'Envío desconocido.' };
  const v = esquemaAjustes.safeParse(ajustes);
  if (!v.success) return { ok: false, error: v.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase.schema('crm').rpc('ajustar_envio_masivo', {
    p_id: id,
    p_tamano_lote: v.data.tamanoLote,
    p_minutos_entre_lotes: v.data.minutosEntreLotes,
    p_tope_diario: v.data.topeDiario,
    p_frecuencia_dias: v.data.frecuenciaDias,
    p_horario: v.data.horario,
  });
  if (error) return { ok: false, error: errorLegible(error, 'No se pudieron guardar los ajustes.') };

  revalidatePath(`/envios-masivos/${id}`);
  return { ok: true };
}

/** Las filas con su resultado, para el archivo que se le devuelve a cartera. */
export async function resultadosEnvioMasivo(
  id: string
): Promise<ResultadoAccion & { columnas?: string[]; archivo?: string; filas?: FilaResultado[] }> {
  if (!uuid.safeParse(id).success) return { ok: false, error: 'Envío desconocido.' };

  const supabase = await createClient();
  const crm = supabase.schema('crm');
  const [{ data: envio }, { data: filas, error }] = await Promise.all([
    crm.from('envios_masivos').select('nombre, archivo_nombre, columnas').eq('id', id).maybeSingle(),
    crm.rpc('resultados_envio_masivo', { p_id: id }),
  ]);

  if (!envio) return { ok: false, error: 'No se encontró el envío.' };
  if (error) return { ok: false, error: 'No se pudieron leer los resultados.' };

  return {
    ok: true,
    columnas: envio.columnas as string[],
    archivo: (envio.archivo_nombre as string | null) ?? `${envio.nombre}.xlsx`,
    filas: (filas ?? []) as unknown as FilaResultado[],
  };
}
