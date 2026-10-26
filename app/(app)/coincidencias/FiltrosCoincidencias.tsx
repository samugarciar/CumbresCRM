'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { useTransition } from 'react';
import { Loader2 } from 'lucide-react';

// Tres niveles y no un deslizador: un asesor no quiere calibrar un
// porcentaje, quiere decidir cuánto ruido aguanta hoy. Los nombres dicen
// lo que hacen; el número está en el title por si alguien lo busca.
const NIVELES = [
  { valor: 80, etiqueta: 'Solo lo que encaja', ayuda: 'Puntaje 80 o más' },
  { valor: 50, etiqueta: 'Razonable', ayuda: 'Puntaje 50 o más' },
  { valor: 30, etiqueta: 'Amplio', ayuda: 'Puntaje 30 o más — más nombres, menos precisión' },
];

/**
 * Qué tan exigente es el cruce. «Rebuscar en el histórico» ya no va aquí:
 * es un enlace aparte en la página, porque no es otro nivel de exigencia
 * sino otra lista (gente que lleva más de un mes sin hablar).
 */
export function FiltrosCoincidencias({ minimo }: { minimo: number }) {
  const router = useRouter();
  const params = useSearchParams();
  const [navegando, iniciarNavegacion] = useTransition();

  const aplicar = (valor: number) => {
    const siguientes = new URLSearchParams(params.toString());
    siguientes.set('min', String(valor));
    // Cambiar la exigencia devuelve a la lista completa: quedarse dentro
    // de un inmueble con otro umbral confunde más de lo que ayuda.
    siguientes.delete('inmueble');
    iniciarNavegacion(() => router.push(`/coincidencias?${siguientes.toString()}`));
  };

  return (
    <div className="flex flex-wrap items-center gap-2">
      <span className="text-sm text-muted-foreground">Qué tan exigente:</span>
      <div className="flex items-center gap-1 rounded-lg bg-muted/60 p-1">
        {NIVELES.map((n) => (
          <button
            key={n.valor}
            type="button"
            onClick={() => aplicar(n.valor)}
            title={n.ayuda}
            aria-pressed={minimo === n.valor}
            className={`h-7 rounded-md px-2.5 text-xs font-medium transition-colors ${
              minimo === n.valor
                ? 'bg-background text-foreground shadow-2xs'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            {n.etiqueta}
          </button>
        ))}
      </div>

      {navegando && <Loader2 className="size-4 animate-spin text-muted-foreground" />}
    </div>
  );
}
