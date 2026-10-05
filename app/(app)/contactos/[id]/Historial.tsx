'use client';

import { useMemo, useState } from 'react';
import {
  Bot,
  CalendarCheck,
  CalendarClock,
  CalendarX,
  Clock,
  Layers,
  MessageCircle,
  MessageSquare,
  Send,
  StickyNote,
  User,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { fechaLarga, tiempoRelativo } from '@/lib/formato';
import { CajaDeEscribir } from './CajaDeEscribir';
import { NotaNueva } from './NotaNueva';
import type { EleccionLinea } from '@/lib/lineas';
import type { PlantillaResumen } from './UsarPlantilla';

export interface Actividad {
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

type Vista = 'conversacion' | 'todo' | 'visitas' | 'notas';

export function Historial({
  actividades,
  vistoHasta,
  contactoId,
  ventanaCierraAt,
  canalListo,
  linea,
  ahora,
  plantillas = [],
  asesor = null,
}: {
  actividades: Actividad[];
  vistoHasta?: string | null;
  contactoId: string;
  canalListo: boolean;
  linea: EleccionLinea;
  ventanaCierraAt: string | null;
  ahora: string;
  plantillas?: PlantillaResumen[];
  asesor?: string | null;
}) {
  const tieneMensajes = actividades.some((a) => MENSAJES.includes(a.tipo ?? ''));
  // Si la persona tiene chat de WhatsApp, el asesor busca de inmediato ver la conversación
  const [vista, setVista] = useState<Vista>(tieneMensajes ? 'conversacion' : 'todo');

  const ventanaAbierta =
    ventanaCierraAt !== null &&
    new Date(ventanaCierraAt).getTime() > new Date(ahora).getTime();

  const horasRestantes = ventanaCierraAt
    ? Math.max(
        0,
        Math.round(
          (new Date(ventanaCierraAt).getTime() - new Date(ahora).getTime()) / 3_600_000
        )
      )
    : 0;

  const grupos = useMemo(
    () => ({
      conversacion: actividades.filter((a) => MENSAJES.includes(a.tipo ?? '')),
      todo: actividades,
      visitas: actividades.filter((a) => VISITAS.includes(a.tipo ?? '')),
      notas: actividades.filter((a) => NOTAS.includes(a.tipo ?? '')),
    }),
    [actividades]
  );

  const pestanas: { id: Vista; texto: string; icono: typeof MessageCircle }[] = [
    { id: 'conversacion', texto: 'Chat WhatsApp', icono: MessageCircle },
    { id: 'todo', texto: 'Historial', icono: Layers },
    { id: 'visitas', texto: 'Visitas', icono: CalendarClock },
    { id: 'notas', texto: 'Notas internas', icono: StickyNote },
  ];

  const visibles = grupos[vista];

  return (
    <section className="flex min-w-0 flex-col gap-4">
      {/* Selector de Pestañas Estilizado */}
      <div className="flex flex-wrap items-center gap-1.5 rounded-xl border bg-card/80 p-1.5 shadow-2xs">
        {pestanas.map((p) => {
          const activa = vista === p.id;
          const n = grupos[p.id].length;
          const Icono = p.icono;

          return (
            <button
              key={p.id}
              type="button"
              onClick={() => setVista(p.id)}
              disabled={n === 0 && p.id !== 'todo' && p.id !== 'notas'}
              aria-pressed={activa}
              className={`flex items-center gap-2 rounded-lg px-3 py-1.5 text-xs font-semibold transition-all cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed ${
                activa
                  ? 'bg-primary text-primary-foreground shadow-xs'
                  : 'text-muted-foreground hover:bg-muted hover:text-foreground'
              }`}
            >
              <Icono className="size-3.5" />
              <span>{p.texto}</span>
              <span
                className={`tabular text-[11px] rounded-full px-1.5 py-0.2 ${
                  activa ? 'bg-primary-foreground/20 text-primary-foreground' : 'bg-muted text-muted-foreground'
                }`}
              >
                {n}
              </span>
            </button>
          );
        })}
      </div>

      {/* Vista de Notas Internas: añade el editor de notas arriba del listado */}
      {vista === 'notas' && (
        <div className="rounded-xl border bg-card p-4 shadow-2xs">
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2.5">
            Nueva nota interna para el equipo
          </p>
          <NotaNueva contactoId={contactoId} />
        </div>
      )}

      {/* Contenido según pestaña */}
      {visibles.length === 0 ? (
        <div className="flex flex-col items-center justify-center gap-2 rounded-xl border border-dashed p-10 text-center bg-card/50">
          <Clock className="size-6 text-muted-foreground/60" />
          <p className="text-sm font-medium text-foreground">Sin registros en esta vista</p>
          <p className="text-xs text-muted-foreground max-w-sm">
            {vista === 'notas'
              ? 'No hay notas registradas. Usa el formulario de arriba para dejar un apunte sobre esta persona.'
              : 'Aún no se registran actividades para esta categoría.'}
          </p>
        </div>
      ) : vista === 'conversacion' ? (
        <div className="flex flex-col gap-4">
          {/* Indicador de estado de la ventana en el chat */}
          {ventanaAbierta ? (
            <div className="flex items-center justify-between gap-2 px-3.5 py-2 rounded-xl bg-emerald-500/10 border border-emerald-500/20 text-xs text-emerald-800 dark:text-emerald-300">
              <div className="flex items-center gap-2">
                <span className="relative flex size-2">
                  <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                  <span className="relative inline-flex rounded-full size-2 bg-emerald-500"></span>
                </span>
                <span className="font-semibold">Ventana de WhatsApp abierta</span>
              </div>
              <span className="tabular font-medium text-emerald-700 dark:text-emerald-400">
                {horasRestantes >= 1 ? `Quedan ~${horasRestantes} h de texto libre` : 'Menos de 1 h de ventana'}
              </span>
            </div>
          ) : (
            <div className="flex items-center justify-between gap-2 px-3.5 py-2 rounded-xl bg-amber-500/10 border border-amber-500/20 text-xs text-amber-900 dark:text-amber-300">
              <div className="flex items-center gap-2">
                <span className="size-2 rounded-full bg-amber-500"></span>
                <span className="font-semibold">Ventana de 24 horas cerrada</span>
              </div>
              <span className="text-[11px] text-amber-800/90 dark:text-amber-300/90">
                Solo admite plantillas oficiales de WhatsApp (Meta HSM)
              </span>
            </div>
          )}

          <Conversacion mensajes={visibles} />

          {/* Caja de escribir WhatsApp debajo del chat */}
          <CajaDeEscribir
            contactoId={contactoId}
            canalListo={canalListo}
            linea={linea}
            ventanaAbierta={ventanaAbierta}
            cierraAt={ventanaCierraAt}
            nuncaEscribio={ventanaCierraAt === null}
            ahora={ahora}
            plantillas={plantillas}
            asesor={asesor}
          />
        </div>
      ) : (
        <div className="rounded-xl border bg-card p-4 shadow-2xs">
          <Linea actividades={visibles} vistoHasta={vistoHasta} />
        </div>
      )}
    </section>
  );
}

/**
 * Chat WhatsApp con burbujas modernas y claras.
 */
function Conversacion({ mensajes }: { mensajes: Actividad[] }) {
  const enOrden = [...mensajes].reverse();

  return (
    <div className="flex flex-col gap-3 rounded-xl border bg-card p-4 shadow-2xs">
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
              <div className="flex items-center gap-3 py-1.5">
                <span className="h-px flex-1 bg-border/60" />
                <span className="text-[11px] font-medium text-muted-foreground uppercase tracking-wider bg-muted/60 px-2 py-0.5 rounded-full border">
                  {fechaLarga(m.ocurrido_at).split(',')[0]}
                </span>
                <span className="h-px flex-1 bg-border/60" />
              </div>
            )}

            <div className={`flex ${delCliente ? 'justify-start' : 'justify-end'}`}>
              <div
                className={`flex max-w-[80%] flex-col gap-1 rounded-2xl px-4 py-2.5 shadow-2xs ${
                  delCliente
                    ? 'rounded-bl-xs bg-muted/80 text-foreground border border-border/50'
                    : 'rounded-br-xs bg-primary text-primary-foreground'
                }`}
              >
                <p className="whitespace-pre-wrap break-words text-sm leading-relaxed">{m.cuerpo}</p>
                <div
                  className={`flex items-center justify-end gap-1 text-[10px] ${
                    delCliente ? 'text-muted-foreground' : 'text-primary-foreground/75'
                  }`}
                  title={fechaLarga(m.ocurrido_at)}
                >
                  {m.origen === 'agente_ia' && (
                    <span className="inline-flex items-center gap-0.5 font-medium">
                      <Bot className="size-2.5" />
                      Bot
                      <span>·</span>
                    </span>
                  )}
                  {m.origen === 'asesor' && (
                    <span className="inline-flex items-center gap-0.5 font-medium">
                      <User className="size-2.5" />
                      Asesor
                      <span>·</span>
                    </span>
                  )}
                  <span>
                    {new Date(m.ocurrido_at ?? '').toLocaleTimeString('es-CO', {
                      hour: '2-digit',
                      minute: '2-digit',
                    })}
                  </span>
                </div>
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
                <span className="text-xs font-semibold text-primary bg-primary/10 px-2 py-0.5 rounded-full">
                  {nuevas === 1 ? '1 hecho nuevo' : `${nuevas} hechos nuevos`} desde tu última visita
                </span>
                <span className="h-px flex-1 bg-primary/40" />
              </div>
            )}

            <div className="flex gap-3">
              <div className="flex flex-col items-center">
                <span className={`grid size-6 shrink-0 place-items-center rounded-full ${aspecto.clase}`}>
                  <Icono className="size-3.5" />
                </span>
                {!ultimo && <span className="w-px flex-1 bg-border my-1" />}
              </div>

              <div className={`min-w-0 flex-1 ${ultimo ? '' : 'pb-3.5'}`}>
                <div className="flex flex-wrap items-baseline gap-x-2">
                  <span className="text-sm font-semibold text-foreground">{aspecto.etiqueta}</span>

                  {a.origen === 'agente_ia' && (
                    <Badge variant="outline" className="gap-1 text-[10px] h-4 px-1.5">
                      <Bot className="size-2.5" />
                      Bot
                    </Badge>
                  )}

                  <span className="text-xs text-muted-foreground" title={fechaLarga(a.ocurrido_at)}>
                    {tiempoRelativo(a.ocurrido_at)}
                  </span>
                </div>

                {a.cuerpo && (
                  <p className="mt-1 line-clamp-3 whitespace-pre-wrap break-words text-xs text-muted-foreground leading-relaxed">
                    {a.cuerpo}
                  </p>
                )}

                {a.inmueble_titulo && (
                  <p className="mt-1 text-xs text-foreground/80 font-medium">
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
