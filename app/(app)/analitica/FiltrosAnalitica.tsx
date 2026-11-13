'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { useTransition } from 'react';
import { Loader2 } from 'lucide-react';
import { EMBUDOS, PERIODOS } from './tipos';

// Como en el tablero: los filtros viven en la URL. Una vista de analítica
// se puede mandar por chat («mira la semana de captación»).
export function FiltrosAnalitica() {
  const router = useRouter();
  const params = useSearchParams();
  const [navegando, iniciar] = useTransition();

  const periodo = params.get('periodo') || '30d';
  const embudo = params.get('embudo') || 'comercial';

  const aplicar = (clave: string, valor: string, porDefecto: string) => {
    const sig = new URLSearchParams(params.toString());
    if (valor === porDefecto) sig.delete(clave);
    else sig.set(clave, valor);
    const qs = sig.toString();
    iniciar(() => router.push(qs ? `/analitica?${qs}` : '/analitica'));
  };

  return (
    <div className="flex flex-wrap items-center gap-3">
      <Segmentos
        etiqueta="Periodo"
        opciones={PERIODOS.map((p) => ({ id: p.id, etiqueta: p.etiqueta }))}
        activo={periodo}
        onElegir={(id) => aplicar('periodo', id, '30d')}
      />
      <Segmentos
        etiqueta="Embudo"
        opciones={EMBUDOS.map((e) => ({ id: e.id, etiqueta: e.etiqueta }))}
        activo={embudo}
        onElegir={(id) => aplicar('embudo', id, 'comercial')}
      />
      {navegando && (
        <Loader2 className="size-4 animate-spin text-muted-foreground" aria-label="Cargando" />
      )}
    </div>
  );
}

function Segmentos({
  etiqueta,
  opciones,
  activo,
  onElegir,
}: {
  etiqueta: string;
  opciones: { id: string; etiqueta: string }[];
  activo: string;
  onElegir: (id: string) => void;
}) {
  return (
    <div
      role="radiogroup"
      aria-label={etiqueta}
      className="flex w-fit max-w-full items-center gap-1 overflow-x-auto rounded-xl border border-border/50 bg-muted/60 p-1 shadow-2xs"
    >
      {opciones.map((o) => {
        const sel = o.id === activo;
        return (
          <button
            key={o.id}
            type="button"
            role="radio"
            aria-checked={sel}
            onClick={() => !sel && onElegir(o.id)}
            className={`h-8 shrink-0 rounded-lg px-3.5 text-xs transition-all ${
              sel
                ? 'bg-background font-semibold text-foreground shadow-2xs'
                : 'font-medium text-muted-foreground hover:text-foreground'
            }`}
          >
            {o.etiqueta}
          </button>
        );
      })}
    </div>
  );
}
