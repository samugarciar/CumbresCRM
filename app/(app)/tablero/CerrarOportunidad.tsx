'use client';

import { useState, useTransition } from 'react';
import { Trophy, XCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { DropdownMenuItem } from '@/components/ui/dropdown-menu';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { cerrarOportunidad } from './acciones';

// Los mismos ocho del CHECK de la base. Si alguien añade uno allí, esta
// lista hay que tocarla: es el precio de no tener una tabla de motivos,
// y a cambio el motivo no se puede inventar desde el cliente.
const MOTIVOS: { valor: string; etiqueta: string }[] = [
  { valor: 'precio', etiqueta: 'Por precio' },
  { valor: 'zona', etiqueta: 'Por la zona' },
  { valor: 'disponibilidad', etiqueta: 'No había disponible lo que buscaba' },
  { valor: 'requisitos', etiqueta: 'No cumplió requisitos' },
  { valor: 'no_responde', etiqueta: 'Dejó de responder' },
  { valor: 'arrendo_con_otro', etiqueta: 'Arrendó con otra inmobiliaria' },
  { valor: 'duplicado', etiqueta: 'Está duplicado' },
  { valor: 'otro', etiqueta: 'Otro' },
];

export function CerrarOportunidad({
  oportunidadId,
  nombre,
  contactoId,
}: {
  oportunidadId: string;
  nombre: string;
  contactoId: string;
}) {
  const [abierto, setAbierto] = useState<'ganada' | 'perdida' | null>(null);
  const [motivo, setMotivo] = useState<string | null>(null);
  const [nota, setNota] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pendiente, startTransition] = useTransition();

  function cerrar() {
    if (!abierto) return;
    if (abierto === 'perdida' && !motivo) {
      setError('Elige por qué se perdió: sin motivo, el dato no sirve para nada.');
      return;
    }
    setError(null);
    startTransition(async () => {
      const r = await cerrarOportunidad(
        oportunidadId,
        abierto,
        abierto === 'perdida' ? motivo : null,
        null,
        nota || null
      );
      if (!r.ok) {
        setError(r.error ?? 'No se pudo cerrar.');
        return;
      }
      setAbierto(null);
      setMotivo(null);
      setNota('');
    });
  }

  return (
    <>
      <DropdownMenuItem
        onSelect={(e) => {
          e.preventDefault();
          setAbierto('ganada');
        }}
      >
        <Trophy />
        Marcar como ganada
      </DropdownMenuItem>
      <DropdownMenuItem
        variant="destructive"
        onSelect={(e) => {
          e.preventDefault();
          setAbierto('perdida');
        }}
      >
        <XCircle />
        Dar por perdida
      </DropdownMenuItem>

      <Dialog open={abierto !== null} onOpenChange={(o) => !o && setAbierto(null)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>
              {abierto === 'ganada' ? 'Cerrar como ganada' : 'Dar por perdida'}
            </DialogTitle>
            <DialogDescription>
              {abierto === 'ganada'
                ? `${nombre} arrendó. La oportunidad se cierra y queda en su historial.`
                : `${nombre} no siguió adelante. Decir por qué es lo que permite saber después si el problema es el precio, la zona o nosotros.`}
            </DialogDescription>
          </DialogHeader>

          {abierto === 'perdida' && (
            <fieldset className="flex flex-col gap-2">
              <legend className="pb-2 text-sm font-medium">¿Por qué?</legend>
              <div className="flex flex-wrap gap-1.5">
                {MOTIVOS.map((m) => (
                  <button
                    key={m.valor}
                    type="button"
                    onClick={() => setMotivo(m.valor)}
                    aria-pressed={motivo === m.valor}
                    className={`rounded-4xl border px-2.5 py-1 text-xs transition-colors ${
                      motivo === m.valor
                        ? 'bg-primary text-primary-foreground'
                        : 'hover:bg-muted'
                    }`}
                  >
                    {m.etiqueta}
                  </button>
                ))}
              </div>
            </fieldset>
          )}

          <div className="flex flex-col gap-1.5">
            <Label htmlFor={`nota-${oportunidadId}`}>
              Nota <span className="text-muted-foreground">(opcional)</span>
            </Label>
            <Textarea
              id={`nota-${oportunidadId}`}
              value={nota}
              onChange={(e) => setNota(e.target.value)}
              placeholder={
                abierto === 'ganada'
                  ? 'Qué inmueble, o cualquier cosa que convenga recordar'
                  : 'Lo que haga falta para entenderlo dentro de seis meses'
              }
              rows={3}
            />
          </div>

          {abierto === 'ganada' && (
            <p className="text-xs text-muted-foreground">
              El inmueble se vincula todavía a mano desde{' '}
              <a href={`/contactos/${contactoId}`} className="underline">
                la ficha
              </a>
              . Queda pendiente el selector.
            </p>
          )}

          {error && (
            <p role="alert" className="text-sm text-destructive">
              {error}
            </p>
          )}

          <DialogFooter>
            <Button variant="outline" onClick={() => setAbierto(null)}>
              Cancelar
            </Button>
            <Button onClick={cerrar} disabled={pendiente}>
              {pendiente ? 'Guardando…' : 'Cerrar oportunidad'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
