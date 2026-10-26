'use client';

import { useEffect, useRef, useState, useTransition } from 'react';
import Link from 'next/link';
import {
  AlarmClock,
  Check,
  MoreHorizontal,
  Undo2,
  UserRoundCheck,
  X,
  Phone,
  ArrowRight,
  ChevronRight,
  UserRound,
} from 'lucide-react';
import { tiempoRelativo, telefonoLegible, iniciales } from '@/lib/formato';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { moverEtapa } from './acciones';
import { CerrarOportunidad } from './CerrarOportunidad';

export interface Tarjeta {
  id: string;
  contacto_id: string;
  etapa: string;
  etapa_orden: number;
  nombre: string | null;
  telefono_e164: string | null;
  zona: string | null;
  ultima_actividad_at: string | null;
  etapa_at: string | null;
  escalado_at: string | null;
  escalado_sin_atender: boolean | null;
  escalado_atendido: boolean | null;
  estancada: boolean | null;
  visita_realizada_origen: string | null;
  total_en_etapa: number;
}

export interface Columna {
  codigo: string;
  etiqueta: string;
  diasPudricion: number | null;
  tarjetas: Tarjeta[];
  total: number;
}

interface Deshacer {
  oportunidadId: string;
  nombre: string;
  etapaAnterior: string;
  etiquetaNueva: string;
}

export function Tablero({
  columnas,
  porColumna,
}: {
  columnas: Columna[];
  porColumna: number;
}) {
  const [pendiente, startTransition] = useTransition();
  const [moviendo, setMoviendo] = useState<string | null>(null);
  const [deshacer, setDeshacer] = useState<Deshacer | null>(null);
  const [error, setError] = useState<string | null>(null);

  // ARRASTRAR ES EL ATAJO, NO EL MECANISMO. El menú de cada tarjeta sigue
  // siendo el camino completo: es el que funciona con teclado, con lector
  // de pantalla y en un teléfono, donde el tablero es una sola columna y
  // no hay a dónde arrastrar. Esto de aquí es comodidad de escritorio.
  const [arrastrando, setArrastrando] = useState<Tarjeta | null>(null);
  const [encima, setEncima] = useState<string | null>(null);

  // En móvil no hay siete columnas en paralelo: hay una a la vez y pastillas
  // cómodas para alternar rápidamente. Abre en la primera que tiene
  // tarjetas: abrir en «Nuevo» vacío hacía creer que no había nada.
  const [visible, setVisible] = useState(
    columnas.find((c) => c.total > 0)?.codigo ?? columnas[0]?.codigo ?? ''
  );

  // En el escritorio no caben todas: si quedan columnas a la derecha, se
  // dice con un degradado y una flecha, no solo con la barra de scroll.
  const carril = useRef<HTMLDivElement>(null);
  const [quedanALaDerecha, setQuedanALaDerecha] = useState(false);
  useEffect(() => {
    const el = carril.current;
    if (!el) return;
    const medir = () =>
      setQuedanALaDerecha(el.scrollLeft + el.clientWidth < el.scrollWidth - 8);
    medir();
    el.addEventListener('scroll', medir, { passive: true });
    const ro = new ResizeObserver(medir);
    ro.observe(el);
    return () => {
      el.removeEventListener('scroll', medir);
      ro.disconnect();
    };
  }, []);

  function mover(t: Tarjeta, destino: string, etiquetaDestino: string) {
    setMoviendo(t.id);
    setError(null);
    startTransition(async () => {
      const r = await moverEtapa(t.id, destino);
      setMoviendo(null);
      if (!r.ok) {
        setError(r.error ?? 'No se pudo mover la tarjeta.');
        return;
      }
      setDeshacer({
        oportunidadId: t.id,
        nombre: t.nombre || 'Sin nombre',
        etapaAnterior: t.etapa,
        etiquetaNueva: etiquetaDestino,
      });
    });
  }

  function soltar(destino: Columna) {
    const t = arrastrando;
    setArrastrando(null);
    setEncima(null);
    // Soltar una tarjeta en su propia columna no es un movimiento
    if (!t || t.etapa === destino.codigo) return;
    mover(t, destino.codigo, destino.etiqueta);
  }

  function revertir(d: Deshacer) {
    setMoviendo(d.oportunidadId);
    startTransition(async () => {
      await moverEtapa(d.oportunidadId, d.etapaAnterior, 'deshacer');
      setMoviendo(null);
      setDeshacer(null);
    });
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      {error && (
        <div role="alert" className="rounded-xl border border-destructive/30 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          {error}
        </div>
      )}

      {/* Deshacer toast notification */}
      {deshacer && (
        <div className="flex animate-in fade-in slide-in-from-top-2 items-center justify-between gap-3 rounded-xl border border-border/80 bg-card p-3 shadow-sm">
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <span className="inline-flex size-2 rounded-full bg-primary" />
            <span>
              <strong className="text-foreground">{deshacer.nombre}</strong> pasó a{' '}
              <span className="font-semibold text-primary">{deshacer.etiquetaNueva}</span>
            </span>
          </div>
          <div className="flex items-center gap-2">
            <Button size="xs" variant="outline" className="h-7 rounded-lg" onClick={() => revertir(deshacer)}>
              <Undo2 className="size-3.5" />
              Deshacer
            </Button>
            <button
              type="button"
              onClick={() => setDeshacer(null)}
              className="rounded-md p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
              aria-label="Cerrar aviso"
            >
              <X className="size-4" />
            </button>
          </div>
        </div>
      )}

      {/* Selector de etapa en móvil: pastillas limpias */}
      <div className="flex gap-1.5 overflow-x-auto rounded-xl bg-muted/40 p-1 md:hidden">
        {columnas.map((c) => (
          <button
            key={c.codigo}
            type="button"
            onClick={() => setVisible(c.codigo)}
            aria-pressed={visible === c.codigo}
            className={`flex shrink-0 items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium transition-all ${
              visible === c.codigo
                ? 'bg-background text-foreground shadow-xs'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            <span>{c.etiqueta}</span>
            <span className={`tabular rounded-full px-1.5 py-0.2 text-[11px] font-semibold ${
              visible === c.codigo ? 'bg-primary/10 text-primary' : 'bg-muted text-muted-foreground'
            }`}>
              {c.total}
            </span>
          </button>
        ))}
      </div>

      {/* Contenedor de columnas */}
      <div className="relative flex min-h-0 flex-1">
      <div ref={carril} className="flex min-h-0 flex-1 gap-3 md:overflow-x-auto md:pb-2">
        {columnas.map((c) => {
          const esDropTarget = encima === c.codigo && arrastrando && arrastrando.etapa !== c.codigo;
          // Vacía: en el escritorio se pliega en una franja con su contador,
          // y sigue aceptando tarjetas arrastradas.
          const vacia = c.total === 0;
          return (
            <section
              key={c.codigo}
              onDragOver={(e) => {
                if (!arrastrando) return;
                e.preventDefault();
                e.dataTransfer.dropEffect = 'move';
                if (encima !== c.codigo) setEncima(c.codigo);
              }}
              onDragLeave={(e) => {
                if (!e.currentTarget.contains(e.relatedTarget as Node)) {
                  setEncima((z) => (z === c.codigo ? null : z));
                }
              }}
              onDrop={(e) => {
                e.preventDefault();
                soltar(c);
              }}
              className={`min-h-0 w-full shrink-0 flex-col rounded-xl border transition-all md:flex ${
                vacia ? 'md:w-12 md:px-1' : 'md:w-64'
              } ${
                visible === c.codigo ? 'flex' : 'hidden'
              } ${
                esDropTarget
                  ? 'border-primary/50 bg-primary/5 ring-2 ring-primary/20'
                  : 'border-border/50 bg-muted/20'
              } p-2.5`}
              aria-label={c.etiqueta}
            >
              {/* Franja de la columna vacía (solo escritorio) */}
              {vacia && (
                <div
                  className="hidden flex-col items-center gap-2 py-1 md:flex"
                  title={`${c.etiqueta}: sin oportunidades`}
                >
                  <span className="tabular rounded-full border bg-background px-1.5 py-0.5 text-xs font-semibold text-muted-foreground">
                    0
                  </span>
                  <span className="rotate-180 text-xs font-medium text-muted-foreground [writing-mode:vertical-rl]">
                    {c.etiqueta}
                  </span>
                </div>
              )}

              <div className={`min-h-0 flex-1 flex-col ${vacia ? 'flex md:hidden' : 'flex'}`}>
              {/* Cabecera de Columna */}
              <header className="flex flex-col gap-0.5 border-b border-border/40 px-1 pb-2.5">
                <div className="flex items-center gap-2">
                  <h2 className="truncate text-sm font-semibold tracking-tight text-foreground">{c.etiqueta}</h2>
                  <span className="tabular rounded-full border bg-background px-2 py-0.5 text-xs font-semibold text-muted-foreground">
                    {c.total}
                  </span>
                </div>
                {c.diasPudricion && (
                  <span className="text-[11px] text-muted-foreground">
                    Se estanca a los {c.diasPudricion} días
                  </span>
                )}
              </header>

              {/* Lista de Tarjetas */}
              <div className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto pr-0.5 pt-2">
                {c.tarjetas.length === 0 && (
                  <div className="flex flex-col items-center justify-center rounded-xl border border-dashed border-border/60 bg-background/30 py-8 text-center text-xs text-muted-foreground">
                    <span>Sin oportunidades aquí</span>
                  </div>
                )}

                {c.tarjetas.map((t) => (
                  <TarjetaOportunidad
                    key={t.id}
                    tarjeta={t}
                    columnas={columnas}
                    atenuada={moviendo === t.id || pendiente}
                    arrastrandose={arrastrando?.id === t.id}
                    onMover={mover}
                    onArrastrar={setArrastrando}
                    onSoltarFuera={() => {
                      setArrastrando(null);
                      setEncima(null);
                    }}
                  />
                ))}

                {c.total > c.tarjetas.length && (
                  <div className="rounded-xl border border-dashed border-border/60 bg-background/20 px-2 py-2.5 text-center text-xs text-muted-foreground">
                    <span className="font-medium">{(c.total - c.tarjetas.length).toLocaleString('es-CO')} más</span> en esta etapa.
                    <p className="mt-0.5 text-[11px] opacity-80">Mostrando las {porColumna} prioritarias.</p>
                  </div>
                )}
              </div>
              </div>
            </section>
          );
        })}
      </div>

      {quedanALaDerecha && (
        <div className="pointer-events-none absolute inset-y-0 right-0 hidden w-16 items-center justify-end bg-gradient-to-l from-background to-transparent md:flex">
          <button
            type="button"
            onClick={() => carril.current?.scrollBy({ left: 300, behavior: 'smooth' })}
            className="pointer-events-auto mr-1 grid size-8 place-items-center rounded-full border bg-card text-muted-foreground shadow-sm hover:text-foreground"
            aria-label="Ver más columnas"
            title="Hay más etapas a la derecha"
          >
            <ChevronRight className="size-4" />
          </button>
        </div>
      )}
      </div>
    </div>
  );
}

function TarjetaOportunidad({
  tarjeta: t,
  columnas,
  atenuada,
  arrastrandose,
  onMover,
  onArrastrar,
  onSoltarFuera,
}: {
  tarjeta: Tarjeta;
  columnas: Columna[];
  atenuada: boolean;
  arrastrandose: boolean;
  onMover: (t: Tarjeta, destino: string, etiqueta: string) => void;
  onArrastrar: (t: Tarjeta) => void;
  onSoltarFuera: () => void;
}) {
  const urgente = Boolean(t.escalado_sin_atender);

  return (
    <article
      draggable
      onDragStart={(e) => {
        e.dataTransfer.effectAllowed = 'move';
        e.dataTransfer.setData('text/plain', t.id);
        onArrastrar(t);
      }}
      onDragEnd={onSoltarFuera}
      className={`group relative rounded-xl border border-border/70 bg-card shadow-2xs transition-all duration-150 md:cursor-grab md:active:cursor-grabbing hover:border-border hover:shadow-xs ${
        atenuada ? 'opacity-50' : ''
      } ${arrastrandose ? 'opacity-40 ring-2 ring-primary scale-[0.98] shadow-md' : ''}`}
    >
      <div className="flex items-start gap-2.5 p-3">
        {/* Avatar chip con iniciales */}
        <span className="grid size-7 shrink-0 place-items-center rounded-full bg-primary/10 text-primary text-[11px] font-semibold">
          {t.nombre?.trim() ? iniciales(t.nombre) : <UserRound className="size-3.5" aria-hidden />}
        </span>

        <Link
          href={`/contactos/${t.contacto_id}`}
          draggable={false}
          className="min-w-0 flex-1 outline-none group-hover:text-primary transition-colors"
        >
          {/* Sin nombre, el título es el teléfono y no se repite debajo */}
          <p className="truncate text-sm font-semibold tracking-tight text-foreground">
            {t.nombre?.trim() || telefonoLegible(t.telefono_e164) || (
              <span className="font-normal text-muted-foreground">Sin nombre</span>
            )}
          </p>
          {t.nombre?.trim() && (
            <div className="mt-0.5 flex items-center gap-1 text-xs text-muted-foreground">
              <Phone className="size-3 opacity-60 shrink-0" />
              <span className="tabular truncate">
                {telefonoLegible(t.telefono_e164) ?? 'Sin número'}
              </span>
            </div>
          )}
        </Link>

        {/* Menú de acciones / teclado */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              variant="ghost"
              size="icon-xs"
              className="text-muted-foreground/60 hover:text-foreground hover:bg-muted/80 rounded-md"
              aria-label={`Acciones de ${t.nombre || 'esta oportunidad'}`}
            >
              <MoreHorizontal className="size-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-54 rounded-xl">
            <DropdownMenuLabel className="text-xs text-muted-foreground font-normal">
              Mover a otra etapa
            </DropdownMenuLabel>
            {columnas
              .filter((c) => c.codigo !== t.etapa)
              .map((c) => (
                <DropdownMenuItem
                  key={c.codigo}
                  onSelect={() => onMover(t, c.codigo, c.etiqueta)}
                  className="text-xs font-medium cursor-pointer"
                >
                  <ArrowRight className="size-3.5 opacity-60" />
                  {c.etiqueta}
                </DropdownMenuItem>
              ))}
            <DropdownMenuSeparator />
            <CerrarOportunidad
              oportunidadId={t.id}
              nombre={t.nombre || 'Sin nombre'}
              contactoId={t.contacto_id}
            />
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      {/* Metadatos: zona, estancada, tiempo */}
      <div className="flex flex-wrap items-center gap-x-2 gap-y-1.5 px-3 pb-2.5 text-xs text-muted-foreground">
        {t.zona && (
          <span className="rounded-md bg-muted/80 px-1.5 py-0.5 text-[11px] font-medium text-foreground/80">
            {t.zona}
          </span>
        )}
        {t.estancada ? (
          <span
            className="inline-flex items-center gap-1 rounded-md bg-amber-500/10 px-1.5 py-0.5 text-[11px] font-medium text-amber-600 dark:text-amber-400"
            title="Lleva más días quieta de los que esta etapa tolera"
          >
            <AlarmClock className="size-3 shrink-0" />
            {tiempoRelativo(t.ultima_actividad_at)}
          </span>
        ) : (
          <span className="text-[11px]">{tiempoRelativo(t.ultima_actividad_at)}</span>
        )}
        {t.visita_realizada_origen === 'retroactiva' && (
          <span className="rounded-md bg-muted/50 px-1.5 py-0.5 text-[11px] text-muted-foreground" title="Se cerró en bloque el 14 sep 2026: nadie vio ocurrir la visita">
            visita sin confirmar
          </span>
        )}
      </div>

      {/* Alerta de urgencia: única banda viva */}
      {urgente && (
        <div className="flex items-center gap-1.5 rounded-b-xl border-t border-destructive/20 bg-destructive/10 px-3 py-2 text-xs font-medium text-destructive">
          <UserRoundCheck className="size-3.5 shrink-0" />
          <span>Pidió una persona {tiempoRelativo(t.escalado_at)}</span>
        </div>
      )}

      {/* Escalada previa informativa */}
      {!urgente && t.escalado_at && (
        <div className="flex items-center gap-1.5 rounded-b-xl border-t border-border/40 bg-muted/30 px-3 py-1.5 text-xs text-muted-foreground">
          {t.escalado_atendido ? (
            <>
              <Check className="size-3.5 shrink-0 text-emerald-600 dark:text-emerald-400" />
              <span>Escalada y atendida</span>
            </>
          ) : (
            <>
              <UserRoundCheck className="size-3.5 shrink-0 opacity-70" />
              <span>Pidió persona {tiempoRelativo(t.escalado_at)} · sin abrir ficha</span>
            </>
          )}
        </div>
      )}
    </article>
  );
}
