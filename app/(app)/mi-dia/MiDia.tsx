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
  CheckCircle2,
  Sparkles,
  ArrowRight,
  Filter,
} from 'lucide-react';
import { tiempoRelativo, enlaceWhatsApp } from '@/lib/formato';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
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

const BLOQUES = [
  {
    clave: 'ahora',
    titulo: 'Alguien está esperando',
    ayuda: 'Pidieron una persona o un mensaje no llegó',
    de: (p: number) => p === 1,
    color: 'text-destructive',
    badgeVariant: 'destructive' as const,
  },
  {
    clave: 'hoy',
    titulo: 'Para hoy',
    ayuda: 'Tiene hora programada o se prometió para hoy',
    de: (p: number) => p >= 2 && p <= 6,
    color: 'text-primary',
    badgeVariant: 'default' as const,
  },
  {
    clave: 'frio',
    titulo: 'Se está enfriando',
    ayuda: 'Requiere seguimiento antes de que pierda interés',
    de: (p: number) => p === 7,
    color: 'text-muted-foreground',
    badgeVariant: 'secondary' as const,
  },
];

export function MiDia({ renglones }: { renglones: Renglon[] }) {
  const [hechas, setHechas] = useState<Set<string>>(new Set());
  const [pendiente, startTransition] = useTransition();
  const [filtroActivo, setFiltroActivo] = useState<string>('todos');

  function completar(id: string) {
    startTransition(async () => {
      const r = await completarTarea(id);
      if (r.ok) setHechas((s) => new Set(s).add(id));
    });
  }

  const visibles = renglones.filter(
    (r) => !(r.tarea_id && hechas.has(r.tarea_id))
  );

  const conteoAhora = visibles.filter((r) => r.prioridad === 1).length;
  const conteoHoy = visibles.filter((r) => r.prioridad >= 2 && r.prioridad <= 6).length;
  const conteoFrio = visibles.filter((r) => r.prioridad === 7).length;

  if (visibles.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center gap-3 rounded-2xl border border-dashed bg-card/60 p-12 text-center shadow-xs">
        <div className="flex size-14 items-center justify-center rounded-full bg-primary/10 text-primary">
          <CheckCircle2 className="size-7" />
        </div>
        <h2 className="text-lg font-bold text-foreground">¡Todo al día!</h2>
        <p className="max-w-md text-sm text-muted-foreground">
          No tienes clientes esperando, visitas pendientes ni tareas enfriándose por ahora.
          Es un excelente momento para revisar coincidencias de catálogo.
        </p>
        <Button variant="outline" size="sm" asChild className="mt-2 gap-1.5">
          <Link href="/coincidencias">
            <Sparkles className="size-4 text-primary" />
            Explorar coincidencias
          </Link>
        </Button>
      </div>
    );
  }

  // Filtrado según pastilla activa
  const renglonesFiltrados = visibles.filter((r) => {
    if (filtroActivo === 'todos') return true;
    if (filtroActivo === 'ahora') return r.prioridad === 1;
    if (filtroActivo === 'hoy') return r.prioridad >= 2 && r.prioridad <= 6;
    if (filtroActivo === 'frio') return r.prioridad === 7;
    return true;
  });

  return (
    <div className="flex flex-col gap-6">
      {/* ==============================================================
          KPIs Y FILTROS RÁPIDOS DE ENFOQUE
          ============================================================== */}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <button
          type="button"
          onClick={() => setFiltroActivo(filtroActivo === 'ahora' ? 'todos' : 'ahora')}
          className={`flex items-center justify-between rounded-xl border p-4 text-left transition-all cursor-pointer ${
            filtroActivo === 'ahora'
              ? 'border-destructive/50 bg-destructive/5 ring-2 ring-destructive/20 shadow-xs'
              : 'bg-card hover:bg-muted/50'
          }`}
        >
          <div>
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
              Esperando
            </p>
            <p className="text-2xl font-bold text-foreground mt-0.5 tabular">
              {conteoAhora}
            </p>
          </div>
          <div
            className={`flex size-10 items-center justify-center rounded-lg ${
              conteoAhora > 0
                ? 'bg-destructive/10 text-destructive'
                : 'bg-muted text-muted-foreground'
            }`}
          >
            <UserRoundCheck className="size-5" />
          </div>
        </button>

        <button
          type="button"
          onClick={() => setFiltroActivo(filtroActivo === 'hoy' ? 'todos' : 'hoy')}
          className={`flex items-center justify-between rounded-xl border p-4 text-left transition-all cursor-pointer ${
            filtroActivo === 'hoy'
              ? 'border-primary/50 bg-primary/5 ring-2 ring-primary/20 shadow-xs'
              : 'bg-card hover:bg-muted/50'
          }`}
        >
          <div>
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
              Para hoy
            </p>
            <p className="text-2xl font-bold text-foreground mt-0.5 tabular">
              {conteoHoy}
            </p>
          </div>
          <div className="flex size-10 items-center justify-center rounded-lg bg-primary/10 text-primary">
            <CalendarClock className="size-5" />
          </div>
        </button>

        <button
          type="button"
          onClick={() => setFiltroActivo(filtroActivo === 'frio' ? 'todos' : 'frio')}
          className={`flex items-center justify-between rounded-xl border p-4 text-left transition-all cursor-pointer ${
            filtroActivo === 'frio'
              ? 'border-muted-foreground/50 bg-muted/60 ring-2 ring-muted shadow-xs'
              : 'bg-card hover:bg-muted/50'
          }`}
        >
          <div>
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
              Enfriándose
            </p>
            <p className="text-2xl font-bold text-foreground mt-0.5 tabular">
              {conteoFrio}
            </p>
          </div>
          <div className="flex size-10 items-center justify-center rounded-lg bg-muted text-muted-foreground">
            <AlarmClock className="size-5" />
          </div>
        </button>
      </div>

      {/* Selector de pestañas secundario */}
      <div className="flex items-center gap-1.5 border-b pb-2 text-xs font-medium text-muted-foreground">
        <span className="flex items-center gap-1 mr-1">
          <Filter className="size-3.5" />
          Filtrar:
        </span>
        {[
          { clave: 'todos', etiqueta: `Todos (${visibles.length})` },
          { clave: 'ahora', etiqueta: `Esperando (${conteoAhora})` },
          { clave: 'hoy', etiqueta: `Hoy (${conteoHoy})` },
          { clave: 'frio', etiqueta: `Enfriándose (${conteoFrio})` },
        ].map((f) => (
          <button
            key={f.clave}
            onClick={() => setFiltroActivo(f.clave)}
            className={`rounded-md px-2.5 py-1 transition-colors cursor-pointer ${
              filtroActivo === f.clave
                ? 'bg-foreground text-background font-semibold shadow-2xs'
                : 'hover:bg-muted hover:text-foreground'
            }`}
          >
            {f.etiqueta}
          </button>
        ))}
      </div>

      {/* ==============================================================
          LISTA DE TAREAS AGRUPADAS
          ============================================================== */}
      <div className="flex flex-col gap-6">
        {BLOQUES.map((b) => {
          const suyos = renglonesFiltrados.filter((r) => b.de(r.prioridad));
          if (suyos.length === 0) return null;

          return (
            <section key={b.clave} className="flex flex-col gap-2.5">
              <header className="flex items-center justify-between">
                <div className="flex items-baseline gap-2">
                  <h2 className="text-sm font-bold tracking-tight text-foreground">
                    {b.titulo}
                  </h2>
                  <Badge variant={b.badgeVariant} className="text-[11px] h-4.5 px-2">
                    {suyos.length}
                  </Badge>
                  <span className="hidden text-xs text-muted-foreground md:inline">
                    · {b.ayuda}
                  </span>
                </div>
              </header>

              <div className="overflow-hidden rounded-xl border bg-card shadow-2xs divide-y">
                {suyos.map((r, i) => {
                  const Icono = ICONO[r.tipo] ?? ClipboardList;
                  const wa = enlaceWhatsApp(r.telefono_e164);
                  const urge = r.prioridad === 1;

                  return (
                    <div
                      key={`${r.tipo}-${r.tarea_id ?? r.cita_id ?? r.contacto_id ?? i}`}
                      className={`flex flex-wrap items-center justify-between gap-3 p-3.5 transition-colors hover:bg-muted/40 sm:flex-nowrap ${
                        pendiente ? 'opacity-60' : ''
                      }`}
                    >
                      {/* Lado izquierdo: Ícono + Título + Detalle */}
                      <div className="flex items-start gap-3 min-w-0 flex-1">
                        <div
                          className={`flex size-8 shrink-0 items-center justify-center rounded-lg mt-0.5 ${
                            urge
                              ? 'bg-destructive/10 text-destructive'
                              : 'bg-primary/10 text-primary'
                          }`}
                        >
                          <Icono className="size-4" />
                        </div>

                        <div className="min-w-0 flex-1 space-y-0.5">
                          <div className="flex items-center gap-2">
                            <p
                              className={`truncate text-sm ${
                                urge ? 'font-semibold text-destructive' : 'font-semibold text-foreground'
                              }`}
                            >
                              {r.titulo}
                            </p>
                            {r.nombre && (
                              <span className="hidden sm:inline text-xs text-muted-foreground font-medium">
                                · {r.nombre}
                              </span>
                            )}
                          </div>

                          <p className="truncate text-xs text-muted-foreground">
                            {r.detalle}
                            {r.cuando && (
                              <span className="ml-1 text-foreground/70 font-medium">
                                ({tiempoRelativo(r.cuando)})
                              </span>
                            )}
                          </p>
                        </div>
                      </div>

                      {/* Lado derecho: Acciones Rápidas Ergonómicas */}
                      <div className="flex items-center gap-2 shrink-0 w-full sm:w-auto justify-end pt-2 sm:pt-0 border-t sm:border-t-0">
                        {wa && (
                          <Button
                            size="sm"
                            variant="outline"
                            asChild
                            className="h-8 gap-1.5 text-xs font-semibold text-emerald-700 border-emerald-200 hover:bg-emerald-50 dark:border-emerald-900/60 dark:text-emerald-400 dark:hover:bg-emerald-950/30"
                          >
                            <a href={wa} target="_blank" rel="noopener noreferrer">
                              <MessageCircle className="size-3.5 fill-emerald-600/20" />
                              WhatsApp
                            </a>
                          </Button>
                        )}

                        {r.contacto_id && (
                          <Button
                            size="sm"
                            variant="secondary"
                            asChild
                            className="h-8 gap-1 text-xs font-medium"
                          >
                            <Link href={`/contactos/${r.contacto_id}`}>
                              Ficha
                              <ArrowRight className="size-3" />
                            </Link>
                          </Button>
                        )}

                        {r.tarea_id && (
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => completar(r.tarea_id!)}
                            disabled={pendiente}
                            className="h-8 gap-1 text-xs hover:text-emerald-600 hover:bg-emerald-50 dark:hover:bg-emerald-950/30"
                            title="Marcar como hecha"
                          >
                            <Check className="size-3.5" />
                            <span className="hidden md:inline">Hecha</span>
                          </Button>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            </section>
          );
        })}
      </div>
    </div>
  );
}
