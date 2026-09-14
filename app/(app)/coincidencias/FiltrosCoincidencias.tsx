'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { useTransition } from 'react';
import { Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';

// Tres niveles y no un deslizador: un asesor no quiere calibrar un
// porcentaje, quiere decidir cuánto ruido aguanta hoy. Los nombres dicen
// lo que hacen; el número está en el title por si alguien lo busca.
const NIVELES = [
  { valor: 80, etiqueta: 'Solo lo que encaja', ayuda: 'Puntaje 80 o más' },
  { valor: 50, etiqueta: 'Razonable', ayuda: 'Puntaje 50 o más' },
  { valor: 30, etiqueta: 'Amplio', ayuda: 'Puntaje 30 o más — más nombres, menos precisión' },
];

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
      {NIVELES.map((n) => (
        <Button
          key={n.valor}
          size="sm"
          variant={minimo === n.valor ? 'default' : 'outline'}
          onClick={() => aplicar(n.valor)}
          title={n.ayuda}
        >
          {n.etiqueta}
        </Button>
      ))}
      {navegando && <Loader2 className="size-4 animate-spin text-muted-foreground" />}
    </div>
  );
}
