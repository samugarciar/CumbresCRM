'use client';

import { useState, useTransition } from 'react';
import { Bot, BotOff, Loader2, UsersRound } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cambiarBot } from './acciones';
import { describirBot } from './estadoBot';

/**
 * El interruptor del bot para ESTA persona.
 *
 * El bot es opt-out: contesta por defecto, porque hoy cubre casi todo el
 * volumen. Pero quien lidera la conversación con el cliente es el asesor,
 * así que tiene que poder callarlo en un clic y sin pedir permiso.
 *
 * Se apaga solo cuando el lead escala —pedir hablar con una persona es
 * exactamente eso— y cuando alguien del equipo le escribe (el relevo, que
 * vuelve solo si el equipo deja de escribir). Este botón es para los casos
 * que no pasan por ahí: una negociación delicada, un cliente que ya
 * conoce al asesor, un reclamo.
 *
 * Dice SIEMPRE por qué está como está, a qué hora pasó y a qué hora
 * vuelve, en hora de Colombia. "El bot está apagado" sin motivo ni fecha
 * obliga a adivinar si fue alguien, si fue solo, o si se rompió.
 *
 * En los embudos que el bot no atiende (administrativa y captación) no
 * hay interruptor: encenderlo ahí no haría nada y el botón diría lo
 * contrario.
 */
export function ControlBot({
  contactoId,
  activo,
  motivo,
  cambiadoAt,
  vuelveAt,
  ahora,
  noAtiende = false,
}: {
  contactoId: string;
  activo: boolean;
  motivo: string | null;
  cambiadoAt: string | null;
  /** Cuándo vuelve solo, con cualquier motivo (hoy, el relevo). */
  vuelveAt: string | null;
  /** El reloj del servidor, el mismo de toda la ficha. */
  ahora: string;
  /** Todas sus oportunidades abiertas son de embudos que el bot no atiende. */
  noAtiende?: boolean;
}) {
  const [error, setError] = useState<string | null>(null);
  const [pendiente, iniciar] = useTransition();

  if (noAtiende) {
    return (
      <section className="flex flex-col gap-2 rounded-xl border bg-card p-4">
        <h2 className="text-sm font-semibold">El bot</h2>
        <p className="flex items-start gap-1.5 text-xs text-muted-foreground">
          <UsersRound className="mt-0.5 size-3.5 shrink-0" />
          El bot no atiende la línea administrativa: le responde el equipo.
        </p>
      </section>
    );
  }

  const cambiar = () => {
    setError(null);
    iniciar(async () => {
      const r = await cambiarBot(contactoId, !activo);
      if (!r.ok) setError(r.error ?? 'No se pudo cambiar.');
    });
  };

  const estado = describirBot({ activo, motivo, cambiadoAt, vuelveAt, ahora });
  const apagadoAMano = !activo && motivo !== 'relevo' && motivo !== 'escalamiento' && !vuelveAt;

  return (
    <section className="flex flex-col gap-3 rounded-xl border bg-card p-4">
      <div className="flex items-center justify-between gap-2">
        <h2 className="text-sm font-semibold">El bot</h2>
        <span
          className={`inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium ${
            activo ? 'bg-muted text-muted-foreground' : 'bg-warning/10 text-warning'
          }`}
        >
          {activo ? <Bot className="size-3" /> : <BotOff className="size-3" />}
          {activo ? 'Respondiendo' : apagadoAMano ? 'Apagado' : 'Callado'}
        </span>
      </div>

      {activo ? (
        <p className="text-xs text-muted-foreground">
          Le contesta a esta persona por WhatsApp. Siléncialo si vas a atenderla tú.
        </p>
      ) : (
        <div className="flex flex-col gap-1 text-xs">
          {estado.porQue && <p className="text-muted-foreground">{estado.porQue}</p>}
          {estado.vuelve && <p className="font-medium text-foreground">{estado.vuelve}</p>}
        </div>
      )}

      <Button
        variant="outline"
        size="sm"
        onClick={cambiar}
        disabled={pendiente}
        className="h-8 w-fit rounded-lg text-xs"
      >
        {pendiente ? (
          <Loader2 className="size-3.5 animate-spin" />
        ) : activo ? (
          <BotOff className="size-3.5" />
        ) : (
          <Bot className="size-3.5" />
        )}
        {activo ? 'Silenciar el bot' : 'Que vuelva a responder ya'}
      </Button>

      {error && (
        <p role="alert" className="text-xs text-destructive">
          {error}
        </p>
      )}
    </section>
  );
}
