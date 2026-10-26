import Link from 'next/link';
import { Plus, Send, TriangleAlert } from 'lucide-react';
import { createClient } from '@/lib/supabase/server';
import { Button } from '@/components/ui/button';
import { fechaLarga, tiempoRelativo } from '@/lib/formato';
import { ESTADOS, type EstadoEnvioMasivo } from '@/lib/envios-masivos';

interface Resumen {
  total: number;
  en_cola: number;
  excluidos: number;
  enviados: number;
  fallidos: number;
  respondieron: number;
}

export default async function PaginaEnviosMasivos() {
  const supabase = await createClient();
  const crm = supabase.schema('crm');

  const { data: envios, error } = await crm
    .from('envios_masivos')
    .select('id, nombre, archivo_nombre, estado, created_at, lanzado_at, ultimo_aviso, plantillas(nombre)')
    .order('created_at', { ascending: false })
    .limit(30);

  if (error) {
    return (
      <div className="rounded-xl border border-destructive/30 bg-destructive/10 p-4 text-sm text-destructive">
        No se pudieron cargar los envíos masivos: {error.message}
      </div>
    );
  }

  // Un resumen por envío. Son pocos (los últimos 30), y así cada tarjeta
  // dice lo mismo que la página del envío.
  const resumenes = await Promise.all(
    (envios ?? []).map((e) => crm.rpc('resumen_envio_masivo', { p_id: e.id }))
  );

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-5">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Envíos masivos</h1>
          <p className="max-w-[68ch] text-sm text-muted-foreground mt-1">
            Recordatorios por WhatsApp a partir de un archivo, como el que exporta cartera. Se revisan antes de
            salir, salen por lotes y en horario, y al final se descarga el mismo archivo con lo que pasó con cada
            fila.
          </p>
        </div>
        <Button asChild className="h-9 rounded-xl gap-1.5">
          <Link href="/envios-masivos/nuevo">
            <Plus className="size-4" />
            Nuevo envío
          </Link>
        </Button>
      </header>

      {(envios ?? []).length === 0 ? (
        <div className="rounded-xl border border-dashed border-border/80 py-16 text-center bg-card/40">
          <Send className="mx-auto size-8 text-muted-foreground/60 mb-2" />
          <p className="font-semibold text-foreground">Todavía no hay envíos masivos</p>
          <p className="text-xs text-muted-foreground mt-1 max-w-sm mx-auto">
            Sube el archivo de cartera, elige la plantilla de recordatorio y revisa a quién le llegaría antes de
            lanzarlo.
          </p>
        </div>
      ) : (
        <ul className="flex flex-col gap-3">
          {(envios ?? []).map((e, i) => {
            const r = (resumenes[i]?.data ?? null) as Resumen | null;
            const estado = ESTADOS[e.estado as EstadoEnvioMasivo] ?? ESTADOS.borrador;
            const plantilla = (e.plantillas as { nombre?: string } | null)?.nombre;
            const destinatarios = r ? r.total - r.excluidos : null;
            return (
              <li key={e.id}>
                <Link
                  href={`/envios-masivos/${e.id}`}
                  className="flex flex-col gap-2 rounded-xl border border-border/70 bg-card p-4 shadow-2xs transition-all hover:border-primary/40 hover:shadow-sm"
                >
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <div className="min-w-0">
                      <p className="truncate font-semibold text-sm">{e.nombre}</p>
                      <p className="text-xs text-muted-foreground">
                        {plantilla ?? 'Plantilla archivada'}
                        {e.archivo_nombre ? ` · ${e.archivo_nombre}` : ''}
                      </p>
                    </div>
                    <span className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${estado.estilo}`}>
                      {estado.texto}
                    </span>
                  </div>

                  {r && (
                    <p className="text-xs text-muted-foreground tabular">
                      {e.estado === 'borrador'
                        ? `${destinatarios} de ${r.total} filas recibirían el mensaje`
                        : `${r.enviados} enviados de ${destinatarios}` +
                          (r.en_cola ? ` · ${r.en_cola} en cola` : '') +
                          (r.fallidos ? ` · ${r.fallidos} fallaron` : '') +
                          (r.respondieron ? ` · ${r.respondieron} respondieron` : '')}
                    </p>
                  )}

                  {e.ultimo_aviso && e.estado !== 'terminado' && e.estado !== 'cancelado' && (
                    <p className="flex items-start gap-1.5 text-xs text-warning">
                      <TriangleAlert className="mt-0.5 size-3.5 shrink-0" />
                      {e.ultimo_aviso}
                    </p>
                  )}

                  <p className="text-[11px] text-muted-foreground">
                    {e.lanzado_at
                      ? `Lanzado ${tiempoRelativo(e.lanzado_at)} · ${fechaLarga(e.lanzado_at)}`
                      : `Preparado ${tiempoRelativo(e.created_at)}`}
                  </p>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
