'use client';

import { useMemo, useState } from 'react';
import {
  Bot,
  CalendarCheck,
  CalendarClock,
  CalendarX,
  MessageCircle,
  MessageSquare,
  Send,
  StickyNote,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { fechaLarga, tiempoRelativo } from '@/lib/formato';

export interface Actividad {
  // Anulable porque viene de una vista: aunque crm.actividades.id sea
  // NOT NULL, PostgREST no puede garantizarlo a través de la vista y el
  // tipo generado lo refleja. Se usa el índice como llave de respaldo.
  id: number | null;
  tipo: string | null;
  origen: string | null;
  cuerpo: string | null;
  ocurrido_at: string | null;
  inmueble_titulo: string | null;
  inmueble_barrio: string | null;
}

const ASPECTO: Record<
  string,
  { icono: typeof MessageCircle; etiqueta: string; clase: string }
> = {
  mensaje_entrante: { icono: MessageCircle, etiqueta: 'Mensaje del cliente', clase: 'bg-accent text-accent-foreground' },
  mensaje_saliente: { icono: Send, etiqueta: 'Respuesta enviada', clase: 'bg-muted text-muted-foreground' },
  nota: { icono: StickyNote, etiqueta: 'Nota', clase: 'bg-primary/10 text-primary' },
  llamada: { icono: MessageSquare, etiqueta: 'Llamada', clase: 'bg-muted text-muted-foreground' },
  visita_agendada: { icono: CalendarClock, etiqueta: 'Visita agendada', clase: 'bg-primary/10 text-primary' },
  visita_realizada: { icono: CalendarCheck, etiqueta: 'Visita realizada', clase: 'bg-primary/10 text-primary' },
  visita_cancelada: { icono: CalendarX, etiqueta: 'Visita cancelada', clase: 'bg-destructive/10 text-destructive' },
  solicitud_apertura: { icono: CalendarClock, etiqueta: 'Pidió un horario', clase: 'bg-primary/10 text-primary' },
  sistema: { icono: MessageSquare, etiqueta: 'Sistema', clase: 'bg-muted text-muted-foreground' },
};

const MENSAJES = ['mensaje_entrante', 'mensaje_saliente'];
const VISITAS = ['visita_agendada', 'visita_realizada', 'visita_cancelada', 'solicitud_apertura'];
const NOTAS = ['nota', 'llamada'];

type Vista = 'todo' | 'conversacion' | 'visitas' | 'notas';

export function Historial({
  actividades,
  vistoHasta,
}: {
  actividades: Actividad[];
  /** Hasta dónde había leído esta persona ANTES de abrir la ficha. */
  vistoHasta?: string | null;
}) {
  const [vista, setVista] = useState<Vista>('todo');

  const grupos = useMemo(
    () => ({
      todo: actividades,
      conversacion: actividades.filter((a) => MENSAJES.includes(a.tipo ?? '')),
      visitas: actividades.filter((a) => VISITAS.includes(a.tipo ?? '')),
      notas: actividades.filter((a) => NOTAS.includes(a.tipo ?? '')),
    }),
    [actividades]
  );

  const pestanas: { id: Vista; texto: string }[] = [
    { id: 'todo', texto: 'Todo' },
    { id: 'conversacion', texto: 'Conversación' },
    { id: 'visitas', texto: 'Visitas' },
    { id: 'notas', texto: 'Notas' },
  ];

  const visibles = grupos[vista];

  return (
    <section className="flex min-w-0 flex-col gap-4">
      <div className="flex flex-wrap items-center gap-1 rounded-lg border bg-card p-1">
        {pestanas.map((p) => {
          const activa = vista === p.id;
          const n = grupos[p.id].length;
          return (
            <button
              key={p.id}
              type="button"
              onClick={() => setVista(p.id)}
              disabled={n === 0 && p.id !== 'todo'}
              aria-pressed={activa}
              className={`flex items-center gap-2 rounded-md px-3 py-1.5 text-sm transition-colors disabled:opacity-40 ${
                activa
                  ? 'bg-primary text-primary-foreground'
                  : 'hover:bg-muted disabled:hover:bg-transparent'
              }`}
            >
              {p.texto}
              <span className="tabular text-xs opacity-70">{n}</span>
            </button>
          );
        })}
      </div>

      {visibles.length === 0 ? (
        <p className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
          Todavía no ha pasado nada con esta persona.
        </p>
      ) : vista === 'conversacion' ? (
        <Conversacion mensajes={visibles} />
      ) : (
        <Linea actividades={visibles} vistoHasta={vistoHasta} />
      )}
    </section>
  );
}

/**
 * La conversación se lee como un chat, y por eso va en orden
 * CRONOLÓGICO: de lo más viejo arriba a lo más reciente abajo, igual que
 * WhatsApp. El timeline hace lo contrario —lo último primero— porque ahí
 * la pregunta es "¿qué pasó últimamente?" y aquí es "¿qué se dijeron?".
 */
function Conversacion({ mensajes }: { mensajes: Actividad[] }) {
  const enOrden = [...mensajes].reverse();

  return (
    <div className="flex flex-col gap-3 rounded-lg border bg-card p-4">
      {enOrden.map((m, i) => {
        const delCliente = m.tipo === 'mensaje_entrante';
        const anterior = enOrden[i - 1];
        const dia = m.ocurrido_at ? new Date(m.ocurrido_at).toDateString() : '';
        const diaAnterior = anterior?.ocurrido_at
          ? new Date(anterior.ocurrido_at).toDateString()
          : null;

        return (
          <div key={m.id ?? i} className="flex flex-col gap-3">
            {dia !== diaAnterior && (
              <div className="flex items-center gap-3 py-1">
                <span className="h-px flex-1 bg-border" />
                <span className="text-xs text-muted-foreground">
                  {fechaLarga(m.ocurrido_at).split(',')[0]}
                </span>
                <span className="h-px flex-1 bg-border" />
              </div>
            )}

            <div className={`flex ${delCliente ? 'justify-start' : 'justify-end'}`}>
              <div
                className={`flex max-w-[75%] flex-col gap-1 rounded-2xl px-3.5 py-2 ${
                  delCliente
                    ? 'rounded-bl-sm bg-muted text-foreground'
                    : 'rounded-br-sm bg-primary text-primary-foreground'
                }`}
              >
                <p className="whitespace-pre-wrap break-words text-sm">{m.cuerpo}</p>
                <span
                  className={`self-end text-[10px] ${
                    delCliente ? 'text-muted-foreground' : 'text-primary-foreground/70'
                  }`}
                  title={fechaLarga(m.ocurrido_at)}
                >
                  {m.origen === 'agente_ia' ? 'agente · ' : ''}
                  {new Date(m.ocurrido_at ?? '').toLocaleTimeString('es-CO', {
                    hour: '2-digit',
                    minute: '2-digit',
                  })}
                </span>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

function Linea({
  actividades,
  vistoHasta,
}: {
  actividades: Actividad[];
  vistoHasta?: string | null;
}) {
  // El corte entre lo que ya viste y lo que llegó después. Se calcula una
  // vez: es el primer índice cuya actividad es ANTERIOR a tu última
  // visita — como la lista va de lo más nuevo a lo más viejo, todo lo que
  // está encima de ese índice es nuevo.
  const corte =
    vistoHasta == null
      ? -1
      : actividades.findIndex(
          (a) => a.ocurrido_at != null && new Date(a.ocurrido_at) <= new Date(vistoHasta)
        );
  const nuevas = corte === -1 ? 0 : corte;

  return (
    <ol className="flex flex-col">
      {actividades.map((a, i) => {
        const aspecto = ASPECTO[a.tipo ?? 'sistema'] ?? ASPECTO.sistema;
        const Icono = aspecto.icono;
        const ultimo = i === actividades.length - 1;

        const marcarCorte = nuevas > 0 && i === nuevas;

        return (
          <li key={a.id ?? i} className="flex flex-col">
            {marcarCorte && (
              <div className="flex items-center gap-3 pb-4">
                <span className="h-px flex-1 bg-primary/40" />
                <span className="text-xs font-medium text-primary">
                  {nuevas === 1 ? '1 hecho nuevo' : `${nuevas} hechos nuevos`} desde tu última visita
                </span>
                <span className="h-px flex-1 bg-primary/40" />
              </div>
            )}

            <div className="flex gap-3">
            <div className="flex flex-col items-center">
              <span className={`grid size-8 shrink-0 place-items-center rounded-full ${aspecto.clase}`}>
                <Icono className="size-4" />
              </span>
              {!ultimo && <span className="w-px flex-1 bg-border" />}
            </div>

            <div className={`min-w-0 flex-1 ${ultimo ? '' : 'pb-5'}`}>
              <div className="flex flex-wrap items-baseline gap-x-2">
                <span className="text-sm font-medium">{aspecto.etiqueta}</span>

                {a.origen === 'agente_ia' && (
                  <Badge variant="outline" className="gap-1 text-[10px]">
                    <Bot className="size-3" />
                    Agente
                  </Badge>
                )}

                <span className="text-xs text-muted-foreground" title={fechaLarga(a.ocurrido_at)}>
                  {tiempoRelativo(a.ocurrido_at)}
                </span>
              </div>

              {a.cuerpo && (
                <p className="mt-1 whitespace-pre-wrap break-words text-sm text-muted-foreground">
                  {a.cuerpo}
                </p>
              )}

              {a.inmueble_titulo && (
                <p className="mt-1 text-xs text-muted-foreground">
                  {a.inmueble_titulo}
                  {a.inmueble_barrio ? ` · ${a.inmueble_barrio}` : ''}
                </p>
              )}
              </div>
            </div>
          </li>
        );
      })}
    </ol>
  );
}
