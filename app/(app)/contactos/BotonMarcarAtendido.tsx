'use client';

import { useState, useTransition } from 'react';
import { Check, CheckCheck, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { marcarAtendido } from './[id]/acciones';

export function BotonMarcarAtendido({
  contactoId,
  variante = 'compacto',
  className = '',
}: {
  contactoId: string;
  variante?: 'compacto' | 'completo';
  className?: string;
}) {
  const [pendiente, startTransition] = useTransition();
  const [listo, setListo] = useState(false);

  const ejecutar = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (pendiente || listo) return;

    startTransition(async () => {
      const res = await marcarAtendido(contactoId);
      if (res.ok) {
        setListo(true);
      }
    });
  };

  if (listo) {
    return (
      <span className="inline-flex items-center gap-1 text-[11px] font-medium text-emerald-600 dark:text-emerald-400">
        <CheckCheck className="size-3.5" />
        Atendido
      </span>
    );
  }

  if (variante === 'compacto') {
    return (
      <Button
        variant="ghost"
        size="sm"
        onClick={ejecutar}
        disabled={pendiente}
        title="Marcar como respondido / al día"
        className={`h-7 px-2 text-[11px] font-medium text-muted-foreground hover:text-foreground hover:bg-muted/80 rounded-lg ${className}`}
      >
        {pendiente ? (
          <Loader2 className="size-3 animate-spin" />
        ) : (
          <Check className="size-3 text-muted-foreground" />
        )}
        <span>{pendiente ? 'Guardando…' : 'Al día'}</span>
      </Button>
    );
  }

  return (
    <Button
      variant="outline"
      size="sm"
      onClick={ejecutar}
      disabled={pendiente}
      className={`h-8 gap-1.5 text-xs font-medium rounded-xl border-border/70 hover:border-emerald-500/40 hover:text-emerald-600 transition-colors ${className}`}
    >
      {pendiente ? (
        <Loader2 className="size-3.5 animate-spin" />
      ) : (
        <Check className="size-3.5" />
      )}
      <span>{pendiente ? 'Marcando…' : 'Marcar como respondido'}</span>
    </Button>
  );
}
