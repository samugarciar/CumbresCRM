'use client';

import { useState, useTransition } from 'react';
import { Loader2, Plus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import { crearTarea } from './acciones';

/** Los plazos que de verdad se usan. Escribir una fecha a mano para
 *  "llamarlo mañana" es más fricción de la que merece la tarea. */
const PLAZOS = [
  { etiqueta: 'Hoy', dias: 0 },
  { etiqueta: 'Mañana', dias: 1 },
  { etiqueta: 'En 3 días', dias: 3 },
  { etiqueta: 'En una semana', dias: 7 },
];

function enDias(dias: number): string {
  const d = new Date();
  d.setDate(d.getDate() + dias);
  // 9 de la mañana: una tarea que vence a medianoche aparece vencida
  // antes de que nadie haya empezado a trabajar.
  d.setHours(9, 0, 0, 0);
  return d.toISOString();
}

export function TareaNueva({
  contactoId = null,
  nombre,
}: {
  contactoId?: string | null;
  nombre?: string | null;
}) {
  const [abierto, setAbierto] = useState(false);
  const [titulo, setTitulo] = useState('');
  const [dias, setDias] = useState(1);
  const [error, setError] = useState<string | null>(null);
  const [pendiente, startTransition] = useTransition();

  function guardar() {
    setError(null);
    startTransition(async () => {
      const r = await crearTarea(contactoId, titulo, enDias(dias));
      if (!r.ok) {
        setError(r.error ?? 'No se pudo guardar.');
        return;
      }
      setTitulo('');
      setDias(1);
      setAbierto(false);
    });
  }

  return (
    <Dialog open={abierto} onOpenChange={setAbierto}>
      <DialogTrigger asChild>
        <Button size="sm" variant="outline">
          <Plus className="size-4" />
          {contactoId ? 'Recordarme algo' : 'Nueva tarea'}
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Nueva tarea</DialogTitle>
          <DialogDescription>
            {nombre
              ? `Sobre ${nombre}. Aparecerá en Mi día el día que elijas.`
              : 'Aparecerá en Mi día el día que elijas.'}
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-2">
          <Label htmlFor="titulo-tarea">Qué hay que hacer</Label>
          <Input
            id="titulo-tarea"
            value={titulo}
            onChange={(e) => setTitulo(e.target.value)}
            placeholder="Llamarlo para confirmar la visita"
            autoFocus
            disabled={pendiente}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && titulo.trim()) guardar();
            }}
          />
        </div>

        <fieldset className="flex flex-col gap-2">
          <legend className="pb-2 text-sm font-medium">Cuándo</legend>
          <div className="flex flex-wrap gap-1.5">
            {PLAZOS.map((p) => (
              <button
                key={p.dias}
                type="button"
                onClick={() => setDias(p.dias)}
                aria-pressed={dias === p.dias}
                className={`rounded-4xl border px-2.5 py-1 text-xs transition-colors ${
                  dias === p.dias
                    ? 'bg-primary text-primary-foreground'
                    : 'hover:bg-muted'
                }`}
              >
                {p.etiqueta}
              </button>
            ))}
          </div>
        </fieldset>

        {error && (
          <p role="alert" className="text-sm text-destructive">
            {error}
          </p>
        )}

        <DialogFooter>
          <Button variant="outline" onClick={() => setAbierto(false)}>
            Cancelar
          </Button>
          <Button onClick={guardar} disabled={pendiente || !titulo.trim()}>
            {pendiente && <Loader2 className="animate-spin" />}
            Guardar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
