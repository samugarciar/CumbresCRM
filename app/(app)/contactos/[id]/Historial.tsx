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
import { etiquetaDia, fechaLarga, horaCorta, llaveDia, tiempoRelativo } from '@/lib/formato';
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
  metadata?: unknown;
  /** La foto, el audio o el documento, con su URL ya firmada (ver medios.ts). */
  medio?: MedioActividad | null;
  /** Quién del equipo lo escribió, si se sabe. Sin él, la burbuja dice «Equipo». */
  creado_por_nombre?: string | null;
}

/** `metadata.medio` de un mensaje de WhatsApp, como lo deja la plataforma. */
export interface MedioActividad {
  tipo: 'image' | 'audio' | 'video' | 'document' | 'sticker';
  mime: string | null;
  ruta: string | null;
  nombre: string | null;
  voz?: boolean;
  url?: string | null;
  /** Lo que escribió la persona junto al archivo. */
  caption?: string | null;
  /** La transcripción de la nota de voz o la descripción automática de la foto. */
  texto?: string | null;
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
  telefono,
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
  /**
   * El teléfono de la persona. Con teléfono hay chat aunque todavía no haya
   * mensajes: a quien solo recibió un envío masivo también se le escribe
   * (con plantilla). Si la página no lo pasa, el chat queda habilitado y es
   * enviarMensaje quien dice que no hay número.
   */
  telefono?: string | null;
}) {
  const tieneMensajes = actividades.some((a) => MENSAJES.includes(a.tipo ?? ''));
  const chatHabilitado = tieneMensajes || telefono !== null;
  // Si la persona tiene chat de WhatsApp, el asesor busca de inmediato ver la conversación
  const [vista, setVista] = useState<Vista>(chatHabilitado ? 'conversacion' : 'todo');

  const ventanaAbierta =
    ventanaCierraAt !== null &&
    new Date(ventanaCierraAt).getTime() > new Date(ahora).getTime();

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
              disabled={n === 0 && p.id !== 'todo' && p.id !== 'notas' && !(p.id === 'conversacion' && chatHabilitado)}
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
      {vista === 'conversacion' ? (
        // La caja se monta aunque no haya mensajes: a quien solo recibió un
        // envío masivo también hay que poder escribirle (con plantilla). El
        // estado de la ventana lo dice la caja; aquí no se repite.
        <div className="flex flex-col gap-4">
          {visibles.length === 0 ? (
            <div className="flex flex-col items-center justify-center gap-2 rounded-xl border border-dashed p-8 text-center bg-card/50">
              <MessageCircle className="size-6 text-muted-foreground/60" />
              <p className="text-sm font-medium text-foreground">Todavía no hay mensajes con esta persona</p>
              <p className="text-xs text-muted-foreground max-w-sm">
                Para escribirle primero hay que usar una plantilla aprobada por WhatsApp.
              </p>
            </div>
          ) : (
            <Conversacion mensajes={visibles} ahora={ahora} />
          )}

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
      ) : visibles.length === 0 ? (
        <div className="flex flex-col items-center justify-center gap-2 rounded-xl border border-dashed p-10 text-center bg-card/50">
          <Clock className="size-6 text-muted-foreground/60" />
          <p className="text-sm font-medium text-foreground">Sin registros en esta vista</p>
          <p className="text-xs text-muted-foreground max-w-sm">
            {vista === 'notas'
              ? 'No hay notas registradas. Usa el formulario de arriba para dejar un apunte sobre esta persona.'
              : 'Aún no se registran actividades para esta categoría.'}
          </p>
        </div>
      ) : (
        <div className="rounded-xl border bg-card p-4 shadow-2xs">
          <Linea actividades={visibles} vistoHasta={vistoHasta} />
        </div>
      )}
    </section>
  );
}

/** Quién habla en una burbuja que no es del cliente. */
function autor(m: Actividad): { texto: string; esBot: boolean } {
  if (m.origen === 'agente_ia') return { texto: 'Bot', esBot: true };
  if (m.origen === 'sistema') return { texto: 'Automático', esBot: false };
  // origen 'humano': alguien del equipo, desde el CRM o desde el celular.
  return { texto: m.creado_por_nombre?.trim() || 'Equipo', esBot: false };
}

/**
 * Lo que el chat enseña como texto de una burbuja con archivo. La
 * plataforma guarda «[foto] lo que escribió\n(La foto muestra: …)» para
 * que el bot lo entienda; aquí se enseña lo que escribió la persona y la
 * descripción va aparte, en pequeño.
 */
function textoDeBurbuja(m: Actividad): string {
  const cuerpo = m.cuerpo ?? '';
  if (!m.medio) return cuerpo;
  if (m.medio.caption != null) return m.medio.caption.trim();
  const limpio = cuerpo
    .replace(/^\[(foto|video|sticker|audio|nota de voz|documento)[^\]]*\]\s*/i, '')
    .replace(/\n?\(La foto muestra: [\s\S]*\)\s*$/, '')
    .trim();
  // La nota de voz guarda la transcripción como texto: va aparte, no dos veces.
  return limpio === (m.medio.texto ?? '').trim() ? '' : limpio;
}

/** Chat de WhatsApp: el cliente a la izquierda; el equipo y el bot a la derecha. */
function Conversacion({ mensajes, ahora }: { mensajes: Actividad[]; ahora: string }) {
  const enOrden = [...mensajes].reverse();

  return (
    <div className="flex flex-col gap-3 rounded-xl border bg-card p-4 shadow-2xs">
      {enOrden.map((m, i) => {
        const delCliente = m.tipo === 'mensaje_entrante';
        const quien = delCliente ? null : autor(m);
        const anterior = enOrden[i - 1];
        // El día de Colombia, no el del servidor ni el del navegador.
        const dia = llaveDia(m.ocurrido_at);
        const diaAnterior = anterior ? llaveDia(anterior.ocurrido_at) : null;
        const texto = textoDeBurbuja(m);
        const automatico = m.medio?.texto?.trim();

        const burbuja = delCliente
          ? 'rounded-bl-xs bg-muted/80 text-foreground border border-border/50'
          : quien?.esBot
            ? 'rounded-br-xs bg-primary/10 text-foreground border border-primary/20'
            : 'rounded-br-xs bg-primary text-primary-foreground';
        const tenue = delCliente || quien?.esBot ? 'text-muted-foreground' : 'text-primary-foreground/75';

        return (
          <div key={m.id ?? i} className="flex flex-col gap-3">
            {dia !== diaAnterior && (
              <div className="flex items-center gap-3 py-1.5">
                <span className="h-px flex-1 bg-border/60" />
                <span className="text-[11px] font-medium text-muted-foreground bg-muted/60 px-2 py-0.5 rounded-full border">
                  {etiquetaDia(m.ocurrido_at, ahora)}
                </span>
                <span className="h-px flex-1 bg-border/60" />
              </div>
            )}

            <div className={`flex ${delCliente ? 'justify-start' : 'justify-end'}`}>
              <div className={`flex max-w-[80%] flex-col gap-1 rounded-2xl px-4 py-2.5 shadow-2xs ${burbuja}`}>
                {m.medio && <Medio medio={m.medio} delCliente={delCliente || Boolean(quien?.esBot)} />}
                {texto && (
                  <p className="whitespace-pre-wrap break-words text-sm leading-relaxed">{texto}</p>
                )}
                {automatico && (
                  <p className={`text-xs italic leading-snug ${tenue}`}>
                    {m.medio?.tipo === 'audio' ? 'Transcripción: ' : 'Descripción automática: '}
                    {automatico}
                  </p>
                )}
                <div
                  className={`flex items-center justify-end gap-1 text-[10px] ${tenue}`}
                  title={fechaLarga(m.ocurrido_at)}
                >
                  {quien && (
                    <span className="inline-flex items-center gap-0.5 font-medium">
                      {quien.esBot ? <Bot className="size-2.5" /> : <User className="size-2.5" />}
                      {quien.texto}
                      <span>·</span>
                    </span>
                  )}
                  <span>{horaCorta(m.ocurrido_at)}</span>
                </div>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

/** La foto, el audio, el video o el documento de una burbuja del chat. */
function Medio({ medio, delCliente }: { medio: MedioActividad; delCliente: boolean }) {
  if (!medio.url) {
    return (
      <span className={`text-xs italic ${delCliente ? 'text-muted-foreground' : 'text-primary-foreground/75'}`}>
        El archivo no está disponible.
      </span>
    );
  }
  switch (medio.tipo) {
    case 'image':
    case 'sticker':
      // Al tocarla se abre en grande, en otra pestaña.
      return (
        <a href={medio.url} target="_blank" rel="noreferrer" className="block" title="Abrir la foto">
          {/* eslint-disable-next-line @next/next/no-img-element -- URL firmada de Supabase, sin optimizar */}
          <img
            src={medio.url}
            alt={medio.tipo === 'sticker' ? 'Sticker' : 'Foto que mandó el cliente'}
            className={`rounded-lg object-cover ${medio.tipo === 'sticker' ? 'max-h-28' : 'max-h-64 w-full max-w-xs'}`}
            loading="lazy"
          />
        </a>
      );
    case 'audio':
      // metadata: el navegador trae la duración sin bajar todo el audio.
      return <audio controls preload="metadata" src={medio.url} className="w-64 max-w-full" />;
    case 'video':
      return <video controls preload="metadata" src={medio.url} className="max-h-72 w-full max-w-xs rounded-lg" />;
    default:
      return (
        <a
          href={medio.url}
          target="_blank"
          rel="noreferrer"
          className={`text-sm font-medium underline underline-offset-2 ${delCliente ? '' : 'text-primary-foreground'}`}
        >
          Descargar {medio.nombre ?? 'documento'}
        </a>
      );
  }
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
