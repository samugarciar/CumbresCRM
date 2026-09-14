'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { useTransition, useRef } from 'react';
import { Search, X, Loader2, Flame } from 'lucide-react';
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
    <div className="flex flex-wrap items-center gap-2">
      <div className="relative min-w-56 flex-1">
        <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          defaultValue={params.get('q') ?? ''}
          onChange={(e) => buscar(e.target.value)}
          placeholder="Nombre o teléfono…"
          className="pl-9"
          aria-label="Buscar en el tablero"
        />
        {navegando && (
          <Loader2 className="absolute right-3 top-1/2 size-4 -translate-y-1/2 animate-spin text-muted-foreground" />
        )}
      </div>

      <div className="flex flex-wrap items-center gap-1">
        {/* El filtro que convierte el tablero en una lista de trabajo:
            solo lo que espera a una persona o lleva demasiado quieto. */}
        <Button
          variant={soloPendiente ? 'default' : 'outline'}
          size="sm"
          onClick={() => aplicar({ pendiente: soloPendiente ? null : '1' })}
          title="Las que piden una persona y las que llevan demasiado tiempo quietas"
        >
          <Flame className="size-3.5" />
          Lo que urge
        </Button>

        {/* Las zonas salen de los datos, no de una lista inventada: son
            lo que las "etapas" BELLO y MEDELLIN de Kommo eran de verdad. */}
        {zonas.map((z) =>
          z.zona ? (
            <Button
              key={z.zona}
              variant={zona === z.zona ? 'default' : 'outline'}
              size="sm"
              onClick={() => aplicar({ zona: zona === z.zona ? null : z.zona })}
            >
              {z.zona}
              <span className="ml-1.5 tabular opacity-70">{z.oportunidades}</span>
            </Button>
          ) : null
        )}

        {hayFiltros && (
          <Button
            variant="ghost"
            size="sm"
            onClick={() => iniciarNavegacion(() => router.push('/tablero'))}
          >
            <X className="size-4" />
            Limpiar
          </Button>
        )}
      </div>
    </div>
  );
}
