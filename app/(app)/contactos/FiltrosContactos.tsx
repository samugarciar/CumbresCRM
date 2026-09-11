'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { useTransition, useRef } from 'react';
import { Search, X, Loader2 } from 'lucide-react';
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
    <div className="flex flex-wrap items-center gap-2">
      <div className="relative min-w-56 flex-1">
        <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          defaultValue={params.get('q') ?? ''}
          onChange={(e) => buscar(e.target.value)}
          placeholder="Nombre o teléfono…"
          className="pl-9"
          aria-label="Buscar contactos"
        />
        {navegando && (
          <Loader2 className="absolute right-3 top-1/2 size-4 -translate-y-1/2 animate-spin text-muted-foreground" />
        )}
      </div>

      <div className="flex items-center gap-1">
        {(['cliente', 'propietario'] as const).map((t) => (
          <Button
            key={t}
            variant={tipo === t ? 'default' : 'outline'}
            size="sm"
            onClick={() => aplicar({ tipo: tipo === t ? null : t })}
            className="capitalize"
          >
            {t}s
          </Button>
        ))}

        <Button
          variant={soloSinTelefono ? 'default' : 'outline'}
          size="sm"
          onClick={() => aplicar({ sin_telefono: soloSinTelefono ? null : '1' })}
          title="Personas reales con conversación, pero sin un número al que llamar"
        >
          Sin teléfono
          <span className="ml-1.5 tabular opacity-70">{sinTelefono}</span>
        </Button>

        {hayFiltros && (
          <Button
            variant="ghost"
            size="sm"
            onClick={() => iniciarNavegacion(() => router.push('/contactos'))}
          >
            <X className="size-4" />
            Limpiar
          </Button>
        )}
      </div>
    </div>
  );
}
