'use client';

import { useState } from 'react';
import type { PuntoSerie } from './tipos';
import { numero } from './tipos';

type Metrica = 'conversaciones' | 'leads' | 'citas' | 'mensajes';

const METRICAS: { id: Metrica; etiqueta: string }[] = [
  { id: 'conversaciones', etiqueta: 'Conversaciones' },
  { id: 'leads', etiqueta: 'Leads nuevos' },
  { id: 'citas', etiqueta: 'Citas agendadas' },
  { id: 'mensajes', etiqueta: 'Respuestas: bot y equipo' },
];

const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

function rotulo(inicio: string, unidad: 'hour' | 'day', largo = false): string {
  // inicio ya viene en hora de Bogotá: se lee tal cual, sin pasar por Date.
  const [fecha, hora] = inicio.split('T');
  if (unidad === 'hour') {
    const h = Number(hora.slice(0, 2));
    const h12 = h % 12 === 0 ? 12 : h % 12;
    return `${h12} ${h < 12 ? 'a. m.' : 'p. m.'}`;
  }
  const [, m, d] = fecha.split('-').map(Number);
  return largo ? `${d} de ${MESES[m - 1]}` : `${d} ${MESES[m - 1]}`;
}

export function GraficoActividad({
  serie,
  unidad,
  mostrarCitas,
}: {
  serie: PuntoSerie[];
  unidad: 'hour' | 'day';
  mostrarCitas: boolean;
}) {
  const [metrica, setMetrica] = useState<Metrica>('conversaciones');
  const [foco, setFoco] = useState<number | null>(null);

  const metricas = METRICAS.filter((m) => mostrarCitas || m.id !== 'citas');
  const valor = (p: PuntoSerie) =>
    metrica === 'mensajes' ? p.mensajes_bot + p.mensajes_humano : p[metrica];
  const maximo = Math.max(1, ...serie.map(valor));
  const total = serie.reduce((s, p) => s + valor(p), 0);

  // Cuántos rótulos caben: uno de cada N para que no se pisen.
  const cada = Math.max(1, Math.ceil(serie.length / 8));
  const punto = foco !== null ? serie[foco] : null;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap gap-1.5" role="tablist" aria-label="Qué graficar">
          {metricas.map((m) => (
            <button
              key={m.id}
              type="button"
              role="tab"
              aria-selected={metrica === m.id}
              onClick={() => setMetrica(m.id)}
              className={`rounded-full border px-3 py-1 text-xs transition-colors ${
                metrica === m.id
                  ? 'border-primary bg-primary text-primary-foreground font-semibold'
                  : 'border-border bg-background text-muted-foreground hover:text-foreground'
              }`}
            >
              {m.etiqueta}
            </button>
          ))}
        </div>
        <p className="text-xs text-muted-foreground tabular-nums" aria-live="polite">
          {punto ? (
            <>
              <span className="font-semibold text-foreground">{rotulo(punto.inicio, unidad, true)}</span>
              {' · '}
              {metrica === 'mensajes'
                ? `${numero(punto.mensajes_bot)} del bot · ${numero(punto.mensajes_humano)} del equipo`
                : numero(valor(punto))}
            </>
          ) : (
            <>
              Total del periodo:{' '}
              <span className="font-semibold text-foreground">{numero(total)}</span>
            </>
          )}
        </p>
      </div>

      {metrica === 'mensajes' && (
        <div className="flex gap-4 text-xs text-muted-foreground">
          <span className="flex items-center gap-1.5">
            <span className="size-2.5 rounded-sm bg-chart-3" /> Bot
          </span>
          <span className="flex items-center gap-1.5">
            <span className="size-2.5 rounded-sm bg-chart-1" /> Equipo
          </span>
        </div>
      )}

      <div
        className="flex h-48 items-end gap-[2px] border-b border-border sm:gap-1"
        onMouseLeave={() => setFoco(null)}
      >
        {serie.map((p, i) => {
          const v = valor(p);
          const alto = (v / maximo) * 100;
          const altoBot = metrica === 'mensajes' ? (p.mensajes_bot / maximo) * 100 : 0;
          return (
            <button
              key={p.inicio}
              type="button"
              className="group relative flex h-full min-w-0 flex-1 flex-col justify-end focus:outline-none"
              onMouseEnter={() => setFoco(i)}
              onFocus={() => setFoco(i)}
              onBlur={() => setFoco(null)}
              aria-label={`${rotulo(p.inicio, unidad, true)}: ${numero(v)}`}
            >
              {metrica === 'mensajes' ? (
                <>
                  <span
                    className={`w-full bg-chart-1 transition-opacity ${foco !== null && foco !== i ? 'opacity-40' : ''}`}
                    style={{ height: `${alto - altoBot}%` }}
                  />
                  <span
                    className={`w-full rounded-b-none bg-chart-3 transition-opacity ${foco !== null && foco !== i ? 'opacity-40' : ''}`}
                    style={{ height: `${altoBot}%` }}
                  />
                </>
              ) : (
                <span
                  className={`w-full rounded-t-sm bg-chart-1 transition-opacity ${foco !== null && foco !== i ? 'opacity-40' : ''} ${v === 0 ? 'h-px! bg-border' : ''}`}
                  style={{ height: `${alto}%` }}
                />
              )}
            </button>
          );
        })}
      </div>
      <div className="-mt-2 flex gap-[2px] sm:gap-1">
        {serie.map((p, i) => (
          <span key={p.inicio} className="relative h-4 min-w-0 flex-1">
            {i % cada === 0 && (
              <span className="absolute left-1/2 -translate-x-1/2 whitespace-nowrap text-[10px] text-muted-foreground">
                {rotulo(p.inicio, unidad)}
              </span>
            )}
          </span>
        ))}
      </div>
    </div>
  );
}
