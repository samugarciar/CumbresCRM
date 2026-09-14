'use client';

import { useState, useTransition } from 'react';
import Link from 'next/link';
import { AlarmClock, Check, MoreHorizontal, Undo2, UserRoundCheck, X } from 'lucide-react';
import { tiempoRelativo, telefonoLegible } from '@/lib/formato';
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
  //
  // Se usa el arrastre NATIVO del navegador a propósito: no añade ni una
  // dependencia, y su limitación —que no responde al dedo— coincide
  // exactamente con el único sitio donde no hace falta.
  const [arrastrando, setArrastrando] = useState<Tarjeta | null>(null);
  const [encima, setEncima] = useState<string | null>(null);
  // En móvil no hay siete columnas: hay una, y unas pastillas para
  // cambiarla. El desplazamiento horizontal pelea con el de la página y
  // en un teléfono siempre gana el equivocado.
  const [visible, setVisible] = useState(columnas[0]?.codigo ?? '');

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
    // Soltar una tarjeta en su propia columna no es un movimiento, y
    // registrarlo ensuciaría el historial de etapas con ruido.
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
        <p role="alert" className="text-sm text-destructive">
          {error}
        </p>
      )}

      {/* Deshacer. Mover una tarjeta por error es cuestión de tiempo, y
          una acción que no se puede revertir se usa con miedo. */}
      {deshacer && (
        <div className="flex flex-wrap items-center gap-3 rounded-lg border bg-card px-3 py-2 text-sm">
          <span className="text-muted-foreground">
            <span className="font-medium text-foreground">{deshacer.nombre}</span> pasó a{' '}
            {deshacer.etiquetaNueva}
          </span>
          <Button size="xs" variant="outline" onClick={() => revertir(deshacer)}>
            <Undo2 className="size-3" />
            Deshacer
          </Button>
          <button
            type="button"
            onClick={() => setDeshacer(null)}
            className="ml-auto text-muted-foreground hover:text-foreground"
            aria-label="Cerrar aviso"
          >
            <X className="size-4" />
          </button>
        </div>
      )}

      {/* Pastillas de etapa: solo en móvil */}
      <div className="flex gap-1.5 overflow-x-auto pb-1 md:hidden">
        {columnas.map((c) => (
          <button
            key={c.codigo}
            type="button"
            onClick={() => setVisible(c.codigo)}
            aria-pressed={visible === c.codigo}
            className={`flex shrink-0 items-center gap-1.5 rounded-4xl border px-3 py-1.5 text-xs transition-colors ${
              visible === c.codigo
                ? 'bg-primary text-primary-foreground'
                : 'bg-card hover:bg-muted'
            }`}
          >
            {c.etiqueta}
            <span className="tabular opacity-70">{c.total}</span>
          </button>
        ))}
      </div>

      <div className="flex min-h-0 flex-1 gap-3 md:overflow-x-auto md:pb-2">
        {columnas.map((c) => (
          <section
            key={c.codigo}
            onDragOver={(e) => {
              if (!arrastrando) return;
              // Sin este preventDefault el navegador NO permite soltar:
              // por defecto ningún elemento es destino válido.
              e.preventDefault();
              e.dataTransfer.dropEffect = 'move';
              if (encima !== c.codigo) setEncima(c.codigo);
            }}
            onDragLeave={(e) => {
              // currentTarget vs target: sin esta comprobación, pasar por
              // encima de una tarjeta hija cuenta como salir de la columna
              // y el resaltado parpadea.
              if (!e.currentTarget.contains(e.relatedTarget as Node)) {
                setEncima((z) => (z === c.codigo ? null : z));
              }
            }}
            onDrop={(e) => {
              e.preventDefault();
              soltar(c);
            }}
            className={`min-h-0 w-full shrink-0 flex-col rounded-lg transition-colors md:flex md:w-72 ${
              visible === c.codigo ? 'flex' : 'hidden'
            } ${
              encima === c.codigo && arrastrando && arrastrando.etapa !== c.codigo
                ? 'bg-accent/60 outline-2 outline-dashed outline-primary/40'
                : ''
            }`}
            aria-label={c.etiqueta}
          >
            {/* La cabecera de columna NO lleva color. La identidad de una
                etapa es su posición y su nombre; el color se reserva para
                lo que está mal. */}
            <header className="flex items-baseline justify-between gap-2 px-1 pb-2">
              <h2 className="text-sm font-semibold">{c.etiqueta}</h2>
              <span className="tabular text-xs text-muted-foreground">{c.total}</span>
            </header>

            <div className="flex min-h-0 flex-1 flex-col gap-2 md:overflow-y-auto">
              {c.tarjetas.length === 0 && (
                <p className="rounded-lg border border-dashed px-3 py-6 text-center text-xs text-muted-foreground">
                  Vacía
                </p>
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
                <p className="px-1 py-2 text-center text-xs text-muted-foreground">
                  {(c.total - c.tarjetas.length).toLocaleString('es-CO')} más. Se
                  muestran las {porColumna} que más lo piden — filtra para ver otras.
                </p>
              )}
            </div>
          </section>
        ))}
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
  // ACENTO ÚNICO, Y NO SOLO DENTRO DE LA TARJETA.
  //
  // La primera versión pintaba una banda de color para "esperando" y
  // otra para "estancada". Por tarjeta la regla se cumplía, pero en una
  // columna de 824 en la que el 95% lleva más de tres días quieto, el
  // resultado era una pared ámbar donde las DOS que de verdad urgen no
  // se distinguían de nada.
  //
  // Así que la banda es solo para lo que exige acción hoy. Lo estancado
  // colorea la fecha que ya estaba ahí: se sigue viendo, no ocupa una
  // fila más, y deja que el rojo signifique algo.
  const urgente = Boolean(t.escalado_sin_atender);

  return (
    <article
      draggable
      onDragStart={(e) => {
        e.dataTransfer.effectAllowed = 'move';
        // Hace falta escribir ALGO o Firefox cancela el arrastre.
        e.dataTransfer.setData('text/plain', t.id);
        onArrastrar(t);
      }}
      onDragEnd={onSoltarFuera}
      className={`group rounded-lg border bg-card transition-opacity md:cursor-grab md:active:cursor-grabbing ${
        atenuada ? 'opacity-50' : ''
      } ${arrastrandose ? 'opacity-40 ring-2 ring-primary' : ''}`}
    >
      <div className="flex items-start gap-1 p-3">
        <Link
          href={`/contactos/${t.contacto_id}`}
          draggable={false}
          className="min-w-0 flex-1 outline-none focus-visible:underline"
        >
          <p className="truncate text-sm font-medium">
            {t.nombre || <span className="text-muted-foreground">Sin nombre</span>}
          </p>
          <p className="tabular truncate text-xs text-muted-foreground">
            {telefonoLegible(t.telefono_e164) ?? 'Sin número'}
          </p>
        </Link>

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              variant="ghost"
              size="icon-xs"
              aria-label={`Acciones de ${t.nombre || 'esta oportunidad'}`}
            >
              <MoreHorizontal />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-52">
            <DropdownMenuLabel>Mover a</DropdownMenuLabel>
            {columnas
              .filter((c) => c.codigo !== t.etapa)
              .map((c) => (
                <DropdownMenuItem
                  key={c.codigo}
                  onSelect={() => onMover(t, c.codigo, c.etiqueta)}
                >
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

      <div className="flex flex-wrap items-center gap-x-2 gap-y-1 px-3 pb-2 text-xs text-muted-foreground">
        {t.zona && (
          <span className="rounded-4xl bg-muted px-1.5 py-0.5">{t.zona}</span>
        )}
        {t.estancada ? (
          <span
            className="inline-flex items-center gap-1 font-medium text-warning"
            title="Lleva más días quieta de los que esta etapa tolera"
          >
            <AlarmClock className="size-3 shrink-0" />
            {tiempoRelativo(t.ultima_actividad_at)}
          </span>
        ) : (
          <span>{tiempoRelativo(t.ultima_actividad_at)}</span>
        )}
        {t.visita_realizada_origen === 'retroactiva' && (
          <span title="Se cerró en bloque el 14 sep 2026: nadie vio ocurrir la visita">
            visita sin confirmar
          </span>
        )}
      </div>

      {/* La ÚNICA banda de color de la tarjeta, y por eso se ve. */}
      {urgente && (
        <p className="flex items-center gap-1.5 rounded-b-lg bg-destructive/10 px-3 py-1.5 text-xs font-medium text-destructive">
          <UserRoundCheck className="size-3.5 shrink-0" />
          Pidió una persona {tiempoRelativo(t.escalado_at)}
        </p>
      )}

      {/* Escalada vieja: ya no es tarea, pero decir "atendida" cuando
          nadie la abrió sería mentir. Va en gris, que es lo que es:
          contexto. */}
      {!urgente && t.escalado_at && (
        <p className="flex items-center gap-1.5 rounded-b-lg px-3 pb-2 text-xs text-muted-foreground">
          {t.escalado_atendido ? (
            <>
              <Check className="size-3.5 shrink-0" />
              Escalada y atendida
            </>
          ) : (
            <>
              <UserRoundCheck className="size-3.5 shrink-0" />
              Pidió una persona {tiempoRelativo(t.escalado_at)} · nadie abrió la ficha
            </>
          )}
        </p>
      )}
    </article>
  );
}
