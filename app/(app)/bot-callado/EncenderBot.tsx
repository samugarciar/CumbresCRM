'use client';

import { useState, useTransition } from 'react';
import { Bot, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { encenderBotFreno } from './acciones';

/** El botón de las filas sin ficha: encender el bot por teléfono. */
export function EncenderBot({ telefono }: { telefono: string }) {
  const [error, setError] = useState<string | null>(null);
  const [pendiente, iniciar] = useTransition();

  const encender = () => {
    setError(null);
    iniciar(async () => {
      const r = await encenderBotFreno(telefono);
      if (!r.ok) setError(r.error ?? 'No se pudo encender.');
    });
  };

  return (
    <div className="flex flex-col items-start gap-1 sm:items-end">
      <Button size="sm" variant="outline" onClick={encender} disabled={pendiente}>
        {pendiente ? <Loader2 className="size-3.5 animate-spin" /> : <Bot className="size-3.5" />}
        Encender el bot
      </Button>
      {error && <span className="text-xs text-destructive">{error}</span>}
    </div>
  );
}
