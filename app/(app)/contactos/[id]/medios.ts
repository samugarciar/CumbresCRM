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
  // Los documentos se firman para DESCARGA (Content-Disposition: attachment):
  // un PDF abierto en otra pestaña desde una URL firmada no se puede guardar
  // con su nombre, y en el celular a veces ni se abre. Fotos, audios y
  // videos se firman para verse en línea, en el chat.
  // Cada documento con su nombre original («soporte_pago_octubre.pdf» y no
  // el wamid con que se guardó); son pocos por ficha.
  const documentos = new Map<string, string | null>();
  const enLinea = new Set<string>();
  for (const a of actividades) {
    const medio = medioDe(a);
    if (!medio?.ruta) continue;
    if (medio.tipo === 'document') documentos.set(medio.ruta, medio.nombre?.trim() || null);
    else enLinea.add(medio.ruta);
  }
  if (documentos.size === 0 && enLinea.size === 0) return actividades;

  const bucket = supabase.storage.from(BUCKET);
  const urls = new Map<string, string>();

  const [firmadasEnLinea, ...firmadasDescarga] = await Promise.all([
    enLinea.size > 0 ? bucket.createSignedUrls([...enLinea], DURACION_SEGUNDOS) : null,
    ...[...documentos].map(([ruta, nombre]) =>
      bucket.createSignedUrl(ruta, DURACION_SEGUNDOS, { download: nombre ?? true }).then((r) => ({ ruta, r }))
    ),
  ]);

  if (firmadasEnLinea?.error) {
    console.error('[medios] No se pudieron firmar las URLs:', firmadasEnLinea.error.message);
  }
  for (const d of firmadasEnLinea?.data ?? []) {
    if (d.signedUrl && d.path) urls.set(d.path, d.signedUrl);
  }
  for (const { ruta, r } of firmadasDescarga) {
    if (r.error) console.error('[medios] No se pudo firmar un documento:', r.error.message);
    else if (r.data?.signedUrl) urls.set(ruta, r.data.signedUrl);
  }

  return actividades.map((a) => {
    const medio = medioDe(a);
    if (!medio) return a;
    return { ...a, medio: { ...medio, url: medio.ruta ? (urls.get(medio.ruta) ?? null) : null } };
  });
}
