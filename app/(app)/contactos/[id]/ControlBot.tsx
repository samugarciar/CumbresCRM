'use client';

import { useState, useTransition } from 'react';
import { Bot, BotOff, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { tiempoRelativo } from '@/lib/formato';
import { cambiarBot } from './acciones';

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
 * Dice SIEMPRE por qué está como está. "El bot está apagado" sin motivo
 * ni fecha obliga a adivinar si fue alguien, si fue solo, o si se rompió.
 */
export function ControlBot({
  contactoId,
  activo,
  motivo,
  cambiadoAt,
  vuelveAt,
  ahora,
}: {
  contactoId: string;
  activo: boolean;
  motivo: string | null;
  cambiadoAt: string | null;
  /** Solo en el relevo: cuándo vuelve el bot si nadie más escribe. */
  vuelveAt: string | null;
  /** El reloj del servidor, el mismo de toda la ficha. */
  ahora: string;
}) {
  const [error, setError] = useState<string | null>(null);
  const [pendiente, iniciar] = useTransition();

  const cambiar = () => {
    setError(null);
    iniciar(async () => {
      const r = await cambiarBot(contactoId, !activo);
      if (!r.ok) setError(r.error ?? 'No se pudo cambiar.');
    });
  };

  // Sin punto final: la frase sigue con «hace 2 horas».
  const porQue =
    motivo === 'escalamiento'
      ? 'Se calló solo: esta persona pidió hablar con alguien'
      : motivo === 'relevo'
        ? 'Se calló solo: alguien del equipo le escribió'
        : 'Alguien del equipo lo silenció para atender en persona';

  // La vuelta corre cada 5 minutos: si ya pasó la hora y todavía no
  // volvió, «hace 2 minutos» sería una frase sin sentido.
  const vuelvePronto =
    vuelveAt !== null && new Date(vuelveAt).getTime() <= new Date(ahora).getTime();

  return (
    <section className="flex flex-col gap-3 rounded-lg border bg-card p-4">
      <div className="flex items-center justify-between gap-2">
        <h2 className="font-medium">El bot</h2>
        <span
          className={`inline-flex items-center gap-1.5 rounded-4xl px-2 py-0.5 text-xs font-medium ${
            activo
              ? 'bg-muted text-muted-foreground'
              : 'bg-warning/10 text-warning'
          }`}
        >
          {activo ? <Bot className="size-3" /> : <BotOff className="size-3" />}
          {activo ? 'Respondiendo' : 'Callado'}
        </span>
      </div>

      <p className="text-xs text-muted-foreground">
        {activo ? (
          'Le contesta a esta persona por WhatsApp. Siléncialo si vas a atenderla tú.'
        ) : (
          <>
            {porQue}{' '}
            <span className="whitespace-nowrap">{tiempoRelativo(cambiadoAt)}</span>.
            {/* El relevo vuelve solo. Decirlo evita que alguien lo encienda
                a mano sin necesidad, o que se sorprenda cuando vuelva. */}
            {motivo === 'relevo' && vuelveAt && (
              vuelvePronto ? (
                <> Vuelve a responder en unos minutos.</>
              ) : (
                <>
                  {' '}Vuelve a responder{' '}
                  <span className="whitespace-nowrap">{tiempoRelativo(vuelveAt)}</span> si
                  nadie más le escribe.
                </>
              )
            )}
          </>
        )}
      </p>

      <Button
        variant={activo ? 'outline' : 'default'}
        size="sm"
        onClick={cambiar}
        disabled={pendiente}
        className="w-fit"
      >
        {pendiente ? (
          <Loader2 className="animate-spin" />
        ) : activo ? (
          <BotOff className="size-3.5" />
        ) : (
          <Bot className="size-3.5" />
        )}
        {activo ? 'Silenciar el bot' : 'Que vuelva a responder'}
      </Button>

      {error && (
        <p role="alert" className="text-xs text-destructive">
          {error}
        </p>
      )}
    </section>
  );
}
