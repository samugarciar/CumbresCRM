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
            className={`min-h-0 w-full shrink-0 flex-col md:flex md:w-72 ${
              visible === c.codigo ? 'flex' : 'hidden'
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
                  onMover={mover}
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
  onMover,
}: {
  tarjeta: Tarjeta;
  columnas: Columna[];
  atenuada: boolean;
  onMover: (t: Tarjeta, destino: string, etiqueta: string) => void;
}) {
  // ACENTO ÚNICO: en una superficie que se repite decenas de veces solo
  // puede haber UN elemento con color saturado. Si una tarjeta está
  // esperando a una persona Y estancada, manda lo primero: lo segundo
  // seguirá ahí mañana, lo primero no.
  const alerta = t.escalado_sin_atender
    ? ('esperando' as const)
    : t.estancada
      ? ('estancada' as const)
      : null;

  return (
    <article
      className={`group rounded-lg border bg-card transition-opacity ${
        atenuada ? 'opacity-50' : ''
      }`}
    >
      <div className="flex items-start gap-1 p-3">
        <Link
          href={`/contactos/${t.contacto_id}`}
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
        <span>{tiempoRelativo(t.ultima_actividad_at)}</span>
        {t.visita_realizada_origen === 'retroactiva' && (
          <span title="Se cerró en bloque el 14 sep 2026: nadie vio ocurrir la visita">
            visita sin confirmar
          </span>
        )}
      </div>

      {alerta === 'esperando' && (
        <p className="flex items-center gap-1.5 rounded-b-lg bg-destructive/10 px-3 py-1.5 text-xs font-medium text-destructive">
          <UserRoundCheck className="size-3.5 shrink-0" />
          Pidió una persona {tiempoRelativo(t.escalado_at)}
        </p>
      )}

      {alerta === 'estancada' && (
        <p className="flex items-center gap-1.5 rounded-b-lg bg-warning/10 px-3 py-1.5 text-xs font-medium text-warning">
          <AlarmClock className="size-3.5 shrink-0" />
          Sin moverse desde {tiempoRelativo(t.ultima_actividad_at)}
        </p>
      )}

      {alerta === null && t.escalado_at && (
        <p className="flex items-center gap-1.5 rounded-b-lg px-3 pb-2 text-xs text-muted-foreground">
          <Check className="size-3.5 shrink-0" />
          Escalada y atendida
        </p>
      )}
    </article>
  );
}
