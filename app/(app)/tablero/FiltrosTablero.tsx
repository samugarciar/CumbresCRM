'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { useTransition, useRef } from 'react';
import { Search, X, Loader2, Flame, MapPin } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';

interface Zona {
  zona: string | null;
  oportunidades: number;
}

// Mismo criterio que en /contactos: los filtros viven en la URL, no en
// estado de React. Un tablero filtrado se puede pasar por chat.
export function FiltrosTablero({ zonas }: { zonas: Zona[] }) {
  const router = useRouter();
  const params = useSearchParams();
  const [navegando, iniciarNavegacion] = useTransition();
  const temporizador = useRef<ReturnType<typeof setTimeout> | null>(null);

  const aplicar = (cambios: Record<string, string | null>) => {
    const siguientes = new URLSearchParams(params.toString());
    for (const [clave, valor] of Object.entries(cambios)) {
      if (valor === null || valor === '') siguientes.delete(clave);
      else siguientes.set(clave, valor);
    }
    iniciarNavegacion(() => router.push(`/tablero?${siguientes.toString()}`));
  };

  const buscar = (texto: string) => {
    if (temporizador.current) clearTimeout(temporizador.current);
    temporizador.current = setTimeout(() => aplicar({ q: texto }), 350);
  };

  const zona = params.get('zona');
  const soloPendiente = params.get('pendiente') === '1';
  const hayFiltros = Boolean(params.get('q') || zona || params.get('pendiente'));

  return (
    <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-border/60 bg-card/60 p-2 shadow-2xs backdrop-blur-xs">
      <div className="relative min-w-64 flex-1">
        <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          defaultValue={params.get('q') ?? ''}
          onChange={(e) => buscar(e.target.value)}
          placeholder="Buscar por nombre o teléfono…"
          className="h-9 rounded-xl border-border/60 bg-background/70 pl-9 text-sm focus-visible:bg-background"
          aria-label="Buscar en el tablero"
        />
        {navegando && (
          <Loader2 className="absolute right-3 top-1/2 size-4 -translate-y-1/2 animate-spin text-muted-foreground" />
        )}
      </div>

      <div className="flex flex-wrap items-center gap-1.5">
        {/* El filtro que convierte el tablero en una lista de trabajo:
            solo lo que espera a una persona o lleva demasiado quieto. */}
        <Button
          variant={soloPendiente ? 'default' : 'outline'}
          size="sm"
          onClick={() => aplicar({ pendiente: soloPendiente ? null : '1' })}
          className={`h-9 rounded-xl transition-all ${
            soloPendiente
              ? 'bg-destructive text-destructive-foreground hover:bg-destructive/90 shadow-xs'
              : 'hover:border-destructive/40 hover:text-destructive'
          }`}
          title="Las que piden una persona y las que llevan demasiado tiempo quietas"
        >
          <Flame className={`size-3.5 ${soloPendiente ? 'animate-pulse' : 'text-amber-500'}`} />
          <span>Lo que urge</span>
        </Button>

        {/* Separador sutil si hay zonas */}
        {zonas.filter((z) => z.zona).length > 0 && (
          <div className="mx-1 hidden h-5 w-px bg-border/60 sm:block" />
        )}

        {/* Las zonas salen de los datos */}
        <div className="flex flex-wrap items-center gap-1">
          {zonas.map((z) =>
            z.zona ? (
              <Button
                key={z.zona}
                variant={zona === z.zona ? 'default' : 'outline'}
                size="sm"
                onClick={() => aplicar({ zona: zona === z.zona ? null : z.zona })}
                className="h-9 rounded-xl text-xs font-medium"
              >
                <MapPin className="size-3 opacity-60" />
                {z.zona}
                <span className="ml-1 rounded-full bg-background/40 px-1.5 py-0.2 tabular text-[11px] font-semibold opacity-80">
                  {z.oportunidades}
                </span>
              </Button>
            ) : null
          )}
        </div>

        {hayFiltros && (
          <Button
            variant="ghost"
            size="sm"
            onClick={() => iniciarNavegacion(() => router.push('/tablero'))}
            className="h-9 rounded-xl text-xs text-muted-foreground hover:text-foreground"
          >
            <X className="size-3.5" />
            Limpiar filtros
          </Button>
        )}
      </div>
    </div>
  );
}
