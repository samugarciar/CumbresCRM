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
  UserRoundCheck,
  CheckCircle2,
  Sparkles,
  Reply,
} from 'lucide-react';
import { tiempoRelativo } from '@/lib/formato';
import { Button } from '@/components/ui/button';
import { BandejaEnVivo } from '@/app/(app)/contactos/BandejaEnVivo';
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

/**
 * Los tres bloques. TODA prioridad que trae crm.mi_dia cae en uno: antes
 * la 8 (estancadas) no caía en ninguno, y el encabezado contaba asuntos
 * que la pantalla no enseñaba.
 *
 * 1 escalado y envío fallido, 7 bot callado sin atender → esperando
 * 2 a 6 visitas y tareas de hoy → para hoy
 * 8 estancadas → se está enfriando
 */
const BLOQUES = [
  {
    clave: 'ahora',
    titulo: 'Alguien está esperando',
    ayuda: 'Pidieron una persona, un mensaje no llegó o el bot está callado',
    de: (p: number) => p === 1 || p === 7,
  },
  {
    clave: 'hoy',
    titulo: 'Para hoy',
    ayuda: 'Visitas y tareas con fecha de hoy',
    de: (p: number) => p >= 2 && p <= 6,
  },
  {
    clave: 'frio',
    titulo: 'Se está enfriando',
    ayuda: 'Oportunidades quietas: un mensaje a tiempo las revive',
    de: (p: number) => p >= 8,
  },
] as const;

type Clave = (typeof BLOQUES)[number]['clave'];

/** Lo que hay que hacer con cada renglón, dicho en el botón. */
function accion(r: Renglon): { texto: string; href: string } | null {
  if (!r.contacto_id) return null;
  const ficha = `/contactos/${r.contacto_id}`;
  switch (r.tipo) {
    case 'escalado':
    case 'bot_callado':
    case 'envio_fallido':
    case 'estancada':
      return { texto: 'Responder', href: `${ficha}#escribir` };
    case 'visita_hoy':
      return { texto: 'Confirmar visita', href: `${ficha}#escribir` };
    case 'visita_sin_cerrar':
      return { texto: 'Ver ficha', href: ficha };
    default:
      return null;
  }
}

/** Una pista corta debajo del detalle cuando la acción no se hace aquí. */
function pista(r: Renglon): string | null {
  if (r.tipo === 'visita_sin_cerrar') return 'Márcala como realizada o cancelada en Citas de la plataforma.';
  if (r.tipo === 'tarea_plataforma') return 'Se resuelve en la plataforma de inventario.';
  return null;
}

export function MiDia({ renglones }: { renglones: Renglon[] }) {
  const [hechas, setHechas] = useState<Set<string>>(new Set());
  const [pendiente, startTransition] = useTransition();
  const [filtro, setFiltro] = useState<Clave | null>(null);

  function completar(id: string) {
    startTransition(async () => {
      const r = await completarTarea(id);
      if (r.ok) setHechas((s) => new Set(s).add(id));
    });
  }

  const visibles = renglones.filter((r) => !(r.tarea_id && hechas.has(r.tarea_id)));
  const conteo = (clave: Clave) =>
    visibles.filter((r) => BLOQUES.find((b) => b.clave === clave)!.de(r.prioridad)).length;

  if (visibles.length === 0) {
    return (
      <>
        <BandejaEnVivo />
        <div className="flex flex-col items-center justify-center gap-3 rounded-xl border border-dashed bg-card/60 p-12 text-center">
          <div className="flex size-12 items-center justify-center rounded-full bg-primary/10 text-primary">
            <CheckCircle2 className="size-6" />
          </div>
          <h2 className="text-lg font-semibold text-foreground">Todo al día</h2>
          <p className="max-w-md text-sm text-muted-foreground">
            Nadie está esperando y no hay visitas ni tareas pendientes. Buen momento para revisar
            las coincidencias del catálogo.
          </p>
          <Button variant="outline" size="sm" asChild className="mt-1 h-8 gap-1.5 rounded-lg">
            <Link href="/coincidencias">
              <Sparkles className="size-4 text-primary" />
              Ver coincidencias
            </Link>
          </Button>
        </div>
      </>
    );
  }

  const tarjetas: { clave: Clave; etiqueta: string; icono: typeof Check; alerta: string }[] = [
    { clave: 'ahora', etiqueta: 'Esperando', icono: UserRoundCheck, alerta: 'bg-destructive/10 text-destructive' },
    { clave: 'hoy', etiqueta: 'Para hoy', icono: CalendarClock, alerta: 'bg-primary/10 text-primary' },
    { clave: 'frio', etiqueta: 'Enfriándose', icono: AlarmClock, alerta: 'bg-muted text-muted-foreground' },
  ];

  return (
    <div className="flex flex-col gap-5">
      <BandejaEnVivo />

      {/* Resumen que también filtra: un toque enseña solo ese bloque */}
      <div className="grid grid-cols-3 gap-2 sm:gap-3">
        {tarjetas.map((t) => {
          const n = conteo(t.clave);
          const activa = filtro === t.clave;
          const Icono = t.icono;
          return (
            <button
              key={t.clave}
              type="button"
              onClick={() => setFiltro(activa ? null : t.clave)}
              aria-pressed={activa}
              className={`flex items-center justify-between gap-2 rounded-xl border p-3 text-left transition-colors sm:p-4 ${
                activa ? 'border-primary/50 bg-primary/5 ring-2 ring-primary/20' : 'bg-card hover:bg-muted/50'
              }`}
            >
              <div className="min-w-0">
                <p className="truncate text-xs font-medium text-muted-foreground">{t.etiqueta}</p>
                <p className="tabular text-xl font-semibold text-foreground sm:text-2xl">{n}</p>
              </div>
              <span
                className={`hidden size-9 shrink-0 items-center justify-center rounded-lg sm:flex ${
                  n > 0 ? t.alerta : 'bg-muted text-muted-foreground'
                }`}
              >
                <Icono className="size-4" />
              </span>
            </button>
          );
        })}
      </div>

      {filtro && (
        <p className="-mt-2 text-xs text-muted-foreground">
          Viendo solo «{tarjetas.find((t) => t.clave === filtro)?.etiqueta}».{' '}
          <button type="button" onClick={() => setFiltro(null)} className="font-medium text-primary hover:underline">
            Ver todo
          </button>
        </p>
      )}

      <div className="flex flex-col gap-5">
        {BLOQUES.map((b) => {
          if (filtro && filtro !== b.clave) return null;
          const suyos = visibles.filter((r) => b.de(r.prioridad));
          if (suyos.length === 0) return null;
          const urgente = b.clave === 'ahora';

          return (
            <section key={b.clave} className="flex flex-col gap-2">
              <header className="flex flex-wrap items-baseline gap-x-2">
                <h2 className="text-sm font-semibold text-foreground">{b.titulo}</h2>
                <span className="tabular text-sm text-muted-foreground">{suyos.length}</span>
                <span className="hidden text-xs text-muted-foreground md:inline">· {b.ayuda}</span>
              </header>

              <ul className="divide-y overflow-hidden rounded-xl border bg-card">
                {suyos.map((r, i) => {
                  const Icono = ICONO[r.tipo] ?? ClipboardList;
                  const a = accion(r);
                  const ayuda = pista(r);
                  const titulo = r.contacto_id ? (
                    <Link href={`/contactos/${r.contacto_id}`} className="hover:underline">
                      {r.titulo}
                    </Link>
                  ) : (
                    r.titulo
                  );

                  return (
                    <li
                      key={`${r.tipo}-${r.tarea_id ?? r.cita_id ?? r.contacto_id ?? i}`}
                      className={`flex items-center gap-3 p-3 transition-colors hover:bg-muted/40 ${
                        pendiente ? 'opacity-60' : ''
                      }`}
                    >
                      <span
                        className={`flex size-8 shrink-0 items-center justify-center rounded-lg ${
                          urgente ? 'bg-destructive/10 text-destructive' : 'bg-primary/10 text-primary'
                        }`}
                      >
                        <Icono className="size-4" />
                      </span>

                      <div className="min-w-0 flex-1">
                        <p
                          className={`truncate text-sm font-semibold ${
                            urgente ? 'text-destructive' : 'text-foreground'
                          }`}
                        >
                          {titulo}
                        </p>
                        <p className="line-clamp-2 text-xs text-muted-foreground sm:line-clamp-1">
                          {r.detalle}
                          {r.cuando && (
                            <span className="ml-1 text-foreground/70">· {tiempoRelativo(r.cuando)}</span>
                          )}
                        </p>
                        {ayuda && <p className="line-clamp-2 text-xs text-muted-foreground sm:line-clamp-1">{ayuda}</p>}
                      </div>

                      {r.tarea_id ? (
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => completar(r.tarea_id!)}
                          disabled={pendiente}
                          className="h-8 shrink-0 gap-1 rounded-lg text-xs"
                        >
                          <Check className="size-3.5" />
                          Hecha
                        </Button>
                      ) : a ? (
                        <Button size="sm" variant="outline" asChild className="h-8 shrink-0 gap-1 rounded-lg text-xs">
                          <Link href={a.href}>
                            {a.href.endsWith('#escribir') && <Reply className="size-3.5" />}
                            {a.texto}
                          </Link>
                        </Button>
                      ) : null}
                    </li>
                  );
                })}
              </ul>
            </section>
          );
        })}
      </div>
    </div>
  );
}
