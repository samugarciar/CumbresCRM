'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { useTransition, useRef } from 'react';
import { Search, X, Loader2, PhoneOff, Users } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';

interface Props {
  sinTelefono: number;
}

// Los filtros viven en la URL, no en estado de React. Así una búsqueda se
// puede compartir por chat, recargar sin perderse y volver atrás con el
// botón del navegador — que es como la gente usa un CRM de verdad.
export function FiltrosContactos({ sinTelefono }: Props) {
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
    // Cualquier filtro nuevo invalida el cursor: si no, la página 3 de la
    // búsqueda anterior se mezclaría con los resultados de la nueva.
    siguientes.delete('cursor_at');
    siguientes.delete('cursor_id');
    iniciarNavegacion(() => router.push(`/contactos?${siguientes.toString()}`));
  };

  const buscar = (texto: string) => {
    if (temporizador.current) clearTimeout(temporizador.current);
    temporizador.current = setTimeout(() => aplicar({ q: texto }), 350);
  };

  const tipo = params.get('tipo');
  const soloSinTelefono = params.get('sin_telefono') === '1';
  const hayFiltros = Boolean(params.get('q') || tipo || params.get('sin_telefono'));

  return (
    <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-border/60 bg-card/60 p-2 shadow-2xs backdrop-blur-xs">
      <div className="relative min-w-64 flex-1">
        <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          defaultValue={params.get('q') ?? ''}
          onChange={(e) => buscar(e.target.value)}
          placeholder="Buscar por nombre o teléfono…"
          className="h-9 rounded-xl border-border/60 bg-background/70 pl-9 text-sm focus-visible:bg-background"
          aria-label="Buscar contactos"
        />
        {navegando && (
          <Loader2 className="absolute right-3 top-1/2 size-4 -translate-y-1/2 animate-spin text-muted-foreground" />
        )}
      </div>

      <div className="flex flex-wrap items-center gap-1.5">
        <div className="flex items-center gap-1">
          {(['cliente', 'propietario'] as const).map((t) => (
            <Button
              key={t}
              variant={tipo === t ? 'default' : 'outline'}
              size="sm"
              onClick={() => aplicar({ tipo: tipo === t ? null : t })}
              className={`h-9 rounded-xl text-xs font-medium capitalize transition-all ${
                tipo === t ? 'shadow-xs' : ''
              }`}
            >
              <Users className="size-3.5 opacity-60" />
              {t}s
            </Button>
          ))}
        </div>

        <div className="mx-1 hidden h-5 w-px bg-border/60 sm:block" />

        <Button
          variant={soloSinTelefono ? 'default' : 'outline'}
          size="sm"
          onClick={() => aplicar({ sin_telefono: soloSinTelefono ? null : '1' })}
          className={`h-9 rounded-xl text-xs font-medium transition-all ${
            soloSinTelefono
              ? 'bg-amber-600 text-white hover:bg-amber-700 dark:bg-amber-700 shadow-xs'
              : 'hover:border-amber-500/40 hover:text-amber-600 dark:hover:text-amber-400'
          }`}
          title="Personas reales con conversación, pero sin un número al que llamar"
        >
          <PhoneOff className="size-3.5" />
          <span>Sin teléfono</span>
          <span className={`ml-1.5 rounded-full px-1.5 py-0.2 tabular text-[11px] font-semibold ${
            soloSinTelefono ? 'bg-black/20 text-white' : 'bg-muted text-muted-foreground'
          }`}>
            {sinTelefono}
          </span>
        </Button>

        {hayFiltros && (
          <Button
            variant="ghost"
            size="sm"
            onClick={() => iniciarNavegacion(() => router.push('/contactos'))}
            className="h-9 rounded-xl text-xs text-muted-foreground hover:text-foreground"
          >
            <X className="size-3.5" />
            Limpiar
          </Button>
        )}
      </div>
    </div>
  );
}
