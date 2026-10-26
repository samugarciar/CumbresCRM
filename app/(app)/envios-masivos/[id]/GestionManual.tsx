'use client';

import { useMemo, useState, useTransition } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { CheckCircle2, Loader2, TriangleAlert, Undo2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { comoPesos } from '@/lib/archivos';
import { telefonoLegible, tiempoRelativo } from '@/lib/formato';
import { MAX_NOTA_GESTION, columnasDeCartera, type FilaGestion } from '@/lib/envios-masivos';
import { desmarcarGestionManual, marcarGestionManual } from '../acciones';

/**
 * Las personas a las que el envío no les llegó: sin número, número
 * inválido, sin datos, falló, sin confirmar o sin entregar en 24 horas.
 * Alguien las llama o les escribe por otro lado y las marca aquí. Quien
 * lanzó el envío las tiene en Mi día hasta que no quede ninguna.
 */
export function GestionManual({
  envioId,
  filas,
  columnas,
  error: errorLectura,
}: {
  envioId: string;
  filas: FilaGestion[];
  columnas: string[];
  error: string | null;
}) {
  const router = useRouter();
  const [pendiente, iniciar] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [abierta, setAbierta] = useState<string | null>(null);
  const [nota, setNota] = useState('');

  const pendientes = filas.filter((f) => !f.gestionado).length;
  const gestionadas = filas.length - pendientes;
  const [soloPendientes, setSoloPendientes] = useState(pendientes > 0);

  // Lo que sirve para llamar con la deuda a la mano, si el archivo lo trae.
  const { mora, facturas } = useMemo(() => columnasDeCartera(columnas), [columnas]);
  const visibles = soloPendientes ? filas.filter((f) => !f.gestionado) : filas;

  function correr(accion: () => Promise<{ ok: boolean; error?: string }>) {
    setError(null);
    iniciar(async () => {
      const r = await accion();
      if (!r.ok) {
        setError(r.error ?? 'No se pudo.');
        return;
      }
      setAbierta(null);
      setNota('');
      router.refresh();
    });
  }

  function abrir(id: string) {
    setError(null);
    setNota('');
    setAbierta(id);
  }

  return (
    <section id="gestion" className="flex scroll-mt-20 flex-col gap-3 rounded-xl border border-border/70 bg-card p-4">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div className="max-w-[68ch]">
          <h2 className="text-sm font-semibold">Gestión manual</h2>
          <p className="mt-0.5 text-xs text-muted-foreground">
            A estas personas el mensaje no se les pudo mandar o no les llegó. Llámalas o escríbeles por otro lado y
            márcalas cuando estén gestionadas. Quien lanzó el envío las tiene en Mi día hasta que no quede ninguna.
          </p>
        </div>
        {filas.length > 0 && (
          <div className="flex flex-wrap items-center gap-3 text-xs">
            <span className="text-muted-foreground">
              <b className="tabular text-foreground">{pendientes}</b> {pendientes === 1 ? 'pendiente' : 'pendientes'}{' '}
              · <b className="tabular text-foreground">{gestionadas}</b>{' '}
              {gestionadas === 1 ? 'gestionada' : 'gestionadas'}
            </span>
            <label className="flex items-center gap-1.5 font-medium">
              <input
                type="checkbox"
                checked={soloPendientes}
                onChange={(e) => setSoloPendientes(e.target.checked)}
              />
              Solo pendientes
            </label>
          </div>
        )}
      </header>

      {errorLectura ? (
        <p className="text-xs text-destructive">{errorLectura}</p>
      ) : filas.length === 0 ? (
        <p className="text-xs text-muted-foreground">
          Nadie para gestionar a mano: el mensaje salió para todos o sigue saliendo.
        </p>
      ) : visibles.length === 0 ? (
        <p className="flex items-center gap-2 text-xs text-emerald-700 dark:text-emerald-400">
          <CheckCircle2 className="size-4" />
          No queda nadie pendiente.
        </p>
      ) : (
        // En el celular la tabla se desliza de lado en vez de partir cada palabra en un renglón.
        <div className="overflow-x-auto rounded-xl border">
          <table className="w-full min-w-[46rem] text-xs">
            <thead className="bg-muted/40 text-left text-[11px] text-muted-foreground">
              <tr>
                <th className="px-3 py-2 font-semibold">Fila</th>
                <th className="px-3 py-2 font-semibold">Nombre</th>
                <th className="px-3 py-2 font-semibold">Teléfono</th>
                <th className="px-3 py-2 font-semibold">Por qué</th>
                {mora && <th className="px-3 py-2 text-right font-semibold">{mora}</th>}
                {facturas && <th className="px-3 py-2 text-right font-semibold">{facturas}</th>}
                <th className="px-3 py-2 font-semibold">Gestión</th>
              </tr>
            </thead>
            <tbody>
              {visibles.map((f) => {
                const legible = telefonoLegible(f.telefono_e164);
                return (
                  <tr key={f.destinatario_id} className="border-t border-border/50 align-top">
                    <td className="px-3 py-2 tabular text-muted-foreground">{f.fila}</td>
                    <td className="px-3 py-2">
                      {f.contacto_id ? (
                        <Link href={`/contactos/${f.contacto_id}`} className="font-medium text-primary hover:underline">
                          {f.nombre ?? 'Sin nombre'}
                        </Link>
                      ) : (
                        <span className="font-medium">{f.nombre ?? 'Sin nombre'}</span>
                      )}
                    </td>
                    <td className="px-3 py-2 tabular whitespace-nowrap">
                      {f.telefono_e164 ? (
                        <a href={`tel:${f.telefono_e164}`} className="hover:underline">
                          {legible ?? f.telefono_e164}
                        </a>
                      ) : f.telefono_crudo ? (
                        <span className="text-warning" title="Así venía en el archivo">
                          {f.telefono_crudo}
                        </span>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </td>
                    <td className="px-3 py-2">
                      <p>{f.motivo_legible}</p>
                      {f.detalle && <p className="text-muted-foreground">{f.detalle}</p>}
                    </td>
                    {mora && (
                      <td className="px-3 py-2 text-right tabular whitespace-nowrap">
                        {f.datos?.[mora] ? comoPesos(f.datos[mora]) : '—'}
                      </td>
                    )}
                    {facturas && (
                      <td className="px-3 py-2 text-right tabular">{f.datos?.[facturas] || '—'}</td>
                    )}
                    <td className="px-3 py-2">
                      {abierta === f.destinatario_id ? (
                        <form
                          className="flex min-w-64 flex-col gap-1.5"
                          onSubmit={(e) => {
                            e.preventDefault();
                            correr(() => marcarGestionManual(envioId, f.destinatario_id, nota));
                          }}
                        >
                          <Input
                            autoFocus
                            value={nota}
                            onChange={(e) => setNota(e.target.value)}
                            maxLength={MAX_NOTA_GESTION}
                            placeholder="Nota (opcional): qué se habló"
                            className="h-8 rounded-lg text-xs"
                            aria-label="Nota de la gestión"
                          />
                          <div className="flex items-center gap-1.5">
                            <Button type="submit" size="sm" className="h-7 gap-1 rounded-lg text-xs" disabled={pendiente}>
                              {pendiente && <Loader2 className="size-3.5 animate-spin" />}
                              Guardar
                            </Button>
                            <Button
                              type="button"
                              size="sm"
                              variant="ghost"
                              className="h-7 rounded-lg text-xs"
                              onClick={() => setAbierta(null)}
                            >
                              Cancelar
                            </Button>
                          </div>
                        </form>
                      ) : f.gestionado ? (
                        <div className="flex flex-col gap-0.5">
                          <span className="flex items-center gap-1 font-medium text-emerald-700 dark:text-emerald-400">
                            <CheckCircle2 className="size-3.5" />
                            Gestionada
                          </span>
                          <span className="text-muted-foreground">
                            {f.gestionado_por_nombre ? `${f.gestionado_por_nombre} · ` : ''}
                            {tiempoRelativo(f.gestionado_at)}
                          </span>
                          {f.gestion_nota && <span className="max-w-xs whitespace-pre-wrap">{f.gestion_nota}</span>}
                          <button
                            type="button"
                            disabled={pendiente}
                            onClick={() => correr(() => desmarcarGestionManual(envioId, f.destinatario_id))}
                            className="mt-0.5 inline-flex w-fit items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground"
                          >
                            <Undo2 className="size-3" />
                            Deshacer
                          </button>
                        </div>
                      ) : (
                        <Button
                          size="sm"
                          variant="outline"
                          className="h-7 rounded-lg text-xs whitespace-nowrap"
                          disabled={pendiente}
                          onClick={() => abrir(f.destinatario_id)}
                        >
                          Marcar gestionado
                        </Button>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {error && (
        <p className="flex items-start gap-2 rounded-xl border border-destructive/30 bg-destructive/10 p-3 text-xs text-destructive">
          <TriangleAlert className="mt-0.5 size-3.5 shrink-0" />
          {error}
        </p>
      )}
    </section>
  );
}
