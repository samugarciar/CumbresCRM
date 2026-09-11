'use client';

import { useState, useTransition, useRef } from 'react';
import { Loader2 } from 'lucide-react';
import { agregarNota } from './acciones';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';

export function NotaNueva({ contactoId }: { contactoId: string }) {
  const [error, setError] = useState<string | null>(null);
  const [guardando, iniciar] = useTransition();
  const campo = useRef<HTMLTextAreaElement>(null);

  const enviar = (evento: React.FormEvent<HTMLFormElement>) => {
    evento.preventDefault();
    setError(null);
    const texto = campo.current?.value ?? '';

    iniciar(async () => {
      const resultado = await agregarNota(contactoId, texto);
      if (resultado.ok) {
        if (campo.current) campo.current.value = '';
      } else {
        setError(resultado.error ?? 'No se pudo guardar.');
      }
    });
  };

  return (
    <form onSubmit={enviar} className="flex flex-col gap-2">
      <Textarea
        ref={campo}
        name="cuerpo"
        rows={3}
        placeholder="Qué pasó en esta conversación…"
        disabled={guardando}
        aria-label="Nueva nota"
        // Registrar tiene que costar casi nada: si toma más de unos
        // segundos, los asesores no lo hacen y el CRM se queda vacío.
        onKeyDown={(e) => {
          if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
            e.currentTarget.form?.requestSubmit();
          }
        }}
      />

      {error && (
        <p role="alert" className="text-sm text-destructive">
          {error}
        </p>
      )}

      <div className="flex items-center justify-between">
        <span className="text-xs text-muted-foreground">⌘/Ctrl + Enter</span>
        <Button type="submit" size="sm" disabled={guardando}>
          {guardando && <Loader2 className="animate-spin" />}
          Guardar nota
        </Button>
      </div>
    </form>
  );
}
