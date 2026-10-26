import 'server-only';
import type { createClient } from '@/lib/supabase/server';
import type { Actividad, MedioActividad } from './Historial';

/**
 * Las fotos, audios y documentos de WhatsApp viven en el bucket privado
 * `whatsapp_medios` de la plataforma (su migración 2026-10-25). La
 * proyección deja en `metadata.medio` la ruta; aquí se firman con la
 * sesión del usuario, que por la política del bucket solo abre la carpeta
 * de su inmobiliaria. La URL dura una hora: la página se vuelve a pedir
 * antes de eso.
 */
const BUCKET = 'whatsapp_medios';
const DURACION_SEGUNDOS = 60 * 60;

function medioDe(a: Actividad): MedioActividad | null {
  const medio = (a.metadata as { medio?: unknown } | null | undefined)?.medio;
  if (!medio || typeof medio !== 'object') return null;
  return medio as MedioActividad;
}

export async function conMedios(
  supabase: Awaited<ReturnType<typeof createClient>>,
  actividades: Actividad[]
): Promise<Actividad[]> {
  const rutas = [
    ...new Set(actividades.map((a) => medioDe(a)?.ruta).filter((r): r is string => Boolean(r))),
  ];
  if (rutas.length === 0) return actividades;

  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrls(rutas, DURACION_SEGUNDOS);
  if (error) {
    console.error('[medios] No se pudieron firmar las URLs:', error.message);
    return actividades;
  }
  const urls = new Map((data ?? []).filter((d) => d.signedUrl && d.path).map((d) => [d.path!, d.signedUrl]));

  return actividades.map((a) => {
    const medio = medioDe(a);
    if (!medio) return a;
    return { ...a, medio: { ...medio, url: medio.ruta ? (urls.get(medio.ruta) ?? null) : null } };
  });
}
