'use client';

import { useState, useTransition } from 'react';
import Link from 'next/link';
import {
  AlarmClock,
  BotOff,
  MailWarning,
  CalendarCheck,
  CalendarClock,
  Check,
  ClipboardList,
  MessageCircle,
  UserRoundCheck,
} from 'lucide-react';
import { tiempoRelativo, enlaceWhatsApp } from '@/lib/formato';
import { Button } from '@/components/ui/button';
import { completarTarea } from './acciones';

export interface Renglon {
  prioridad: number;
  tipo: string;
  titulo: string | null;
  detalle: string | null;
  cuando: string | null;
  contacto_id: string | null;
  nombre: string | null;
  telefono_e164: string | null;
  tarea_id: string | null;
  cita_id: string | null;
}

const ICONO: Record<string, typeof Check> = {
  envio_fallido: MailWarning,
  escalado: UserRoundCheck,
  visita_hoy: CalendarClock,
  tarea_vencida: AlarmClock,
  visita_sin_cerrar: CalendarCheck,
  tarea_hoy: ClipboardList,
  tarea_plataforma: ClipboardList,
  bot_callado: BotOff,
  estancada: AlarmClock,
};

// Tres bloques, no siete. El asesor no necesita saber de cuántas fuentes
// sale su día: necesita saber qué se pierde si no lo hace ahora, qué toca
// hoy, y qué se está enfriando.
const BLOQUES = [
  {
    clave: 'ahora',
    titulo: 'Alguien está esperando',
    ayuda: 'Pidieron una persona, o un mensaje nuestro no llegó',
    de: (p: number) => p === 1,
  },
  {
    clave: 'hoy',
    titulo: 'Hoy',
    ayuda: 'Tiene hora, o se prometió para hoy',
    de: (p: number) => p >= 2 && p <= 6,
  },
  {
    clave: 'frio',
    titulo: 'Se está enfriando',
    ayuda: 'Seguirá ahí mañana, pero cada día vale menos',
    de: (p: number) => p === 7,
  },
];

export function MiDia({ renglones }: { renglones: Renglon[] }) {
  const [hechas, setHechas] = useState<Set<string>>(new Set());
  const [pendiente, startTransition] = useTransition();

  function completar(id: string) {
    startTransition(async () => {
      const r = await completarTarea(id);
      // Optimista solo si funcionó: tachar algo que no se guardó sería
      // peor que no tacharlo.
      if (r.ok) setHechas((s) => new Set(s).add(id));
    });
  }

  const visibles = renglones.filter(
    (r) => !(r.tarea_id && hechas.has(r.tarea_id))
  );

  if (visibles.length === 0) {
    return (
      <div className="flex flex-col items-center gap-2 rounded-lg border border-dashed py-16 text-center">
        <Check className="size-8 text-muted-foreground" />
        <p className="font-medium">No hay nada pendiente</p>
        <p className="max-w-sm text-sm text-muted-foreground">
          Ni gente esperando, ni visitas hoy, ni nada enfriándose. Buen día
          para llamar a alguien de Coincidencias.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      {BLOQUES.map((b) => {
        const suyos = visibles.filter((r) => b.de(r.prioridad));
        if (suyos.length === 0) return null;

        return (
          <section key={b.clave} className="flex flex-col gap-2">
            <header className="flex items-baseline gap-2">
              <h2 className="text-sm font-semibold">{b.titulo}</h2>
              <span className="tabular text-xs text-muted-foreground">
                {suyos.length}
              </span>
              <span className="hidden text-xs text-muted-foreground sm:inline">
                · {b.ayuda}
              </span>
            </header>

            <ul className="overflow-hidden rounded-lg border bg-card">
              {suyos.map((r, i) => {
                const Icono = ICONO[r.tipo] ?? ClipboardList;
                const wa = enlaceWhatsApp(r.telefono_e164);
                // El rojo se reserva para lo que se pierde por no mirarlo.
                const urge = r.prioridad === 1;

                return (
                  <li
                    key={`${r.tipo}-${r.tarea_id ?? r.cita_id ?? r.contacto_id ?? i}`}
                    className={`flex flex-wrap items-center gap-x-3 gap-y-1 border-b px-3 py-2.5 last:border-b-0 ${
                      pendiente ? 'opacity-60' : ''
                    }`}
                  >
                    <Icono
                      className={`size-4 shrink-0 ${
                        urge ? 'text-destructive' : 'text-muted-foreground'
                      }`}
                    />

                    <div className="min-w-0 flex-1">
                      <p
                        className={`truncate text-sm ${
                          urge ? 'font-medium text-destructive' : 'font-medium'
                        }`}
                      >
                        {r.titulo}
                      </p>
                      <p className="truncate text-xs text-muted-foreground">
                        {r.detalle}
                        {r.cuando && ` · ${tiempoRelativo(r.cuando)}`}
                      </p>
                    </div>

                    {wa && (
                      <Button size="xs" variant="outline" asChild>
                        <a href={wa} target="_blank" rel="noopener noreferrer">
                          <MessageCircle className="size-3" />
                          WhatsApp
                        </a>
                      </Button>
                    )}

                    {r.contacto_id && (
                      <Button size="xs" variant="ghost" asChild>
                        <Link href={`/contactos/${r.contacto_id}`}>Abrir</Link>
                      </Button>
                    )}

                    {r.tarea_id && (
                      <Button
                        size="xs"
                        variant="ghost"
                        onClick={() => completar(r.tarea_id!)}
                        disabled={pendiente}
                      >
                        <Check className="size-3" />
                        Hecha
                      </Button>
                    )}
                  </li>
                );
              })}
            </ul>
          </section>
        );
      })}
    </div>
  );
}
