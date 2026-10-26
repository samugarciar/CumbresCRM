'use client';

import { useState } from 'react';
import { Check, ChevronDown, Copy, Home } from 'lucide-react';
import { tiempoRelativo } from '@/lib/formato';
import { Button } from '@/components/ui/button';

export interface Recomendable {
  inmueble_id: string;
  titulo: string | null;
  barrio: string | null;
  ciudad: string | null;
  precio: number | null;
  habitaciones: number | null;
  tipo_inmueble: string | null;
  puntaje: number;
  disponible_desde: string | null;
}

function pesos(n: number | null): string {
  if (n === null) return 'Sin precio';
  return '$' + n.toLocaleString('es-CO', { maximumFractionDigits: 0 });
}

/** Lo que el asesor pega en WhatsApp. Sin emojis ni adornos: lo escribe
 *  una persona y tiene que poder editarlo antes de mandarlo. */
function comoMensaje(i: Recomendable): string {
  return [
    i.titulo ?? 'Inmueble',
    [i.barrio, i.ciudad].filter(Boolean).join(', '),
    [
      i.habitaciones !== null ? `${i.habitaciones} habitaciones` : null,
      pesos(i.precio),
    ]
      .filter(Boolean)
      .join(' · '),
  ]
    .filter(Boolean)
    .join('\n');
}

/**
 * Lo que se le puede ofrecer a esta persona, según lo que dijo que busca.
 *
 * ORDENADO DE VIEJOS A NUEVOS, y va contra el instinto a propósito: lo
 * recién entrado se mueve solo; lo que lleva meses parado necesita salir.
 * El puntaje sigue filtrando —rotar no es ofrecer cualquier cosa— pero no
 * ordena. Por eso cada tarjeta dice cuánto lleva disponible: sin ese dato
 * el orden parecería arbitrario.
 *
 * Cerrado por defecto: la ficha es para leer la conversación, y esto es
 * una herramienta que se coge cuando hace falta. Pero la cabecera lleva
 * el número, así que se anuncia sola sin ocupar sitio.
 *
 * Solo copia los datos: se pegan en la caja de escribir de la ficha y
 * salen por la línea oficial. Nada aquí manda al asesor a otro WhatsApp.
 */
export function Recomendaciones({ inmuebles }: { inmuebles: Recomendable[] }) {
  const [abierto, setAbierto] = useState(false);
  const [copiado, setCopiado] = useState<string | null>(null);

  if (inmuebles.length === 0) return null;

  async function copiar(i: Recomendable) {
    try {
      await navigator.clipboard.writeText(comoMensaje(i));
      setCopiado(i.inmueble_id);
      setTimeout(() => setCopiado(null), 2000);
    } catch {
      // Sin permiso de portapapeles no se rompe nada: el asesor lo lee y
      // lo escribe. Avisar de esto sería ruido.
    }
  }

  return (
    <section className="overflow-hidden rounded-xl border bg-card">
      <button
        type="button"
        onClick={() => setAbierto((v) => !v)}
        aria-expanded={abierto}
        className="flex w-full items-center gap-2 px-4 py-3 text-left text-sm hover:bg-muted"
      >
        <Home className="size-4 shrink-0 text-muted-foreground" />
        <span className="flex-1 font-semibold">
          {inmuebles.length} para recomendarle
        </span>
        <ChevronDown
          className={`size-4 shrink-0 text-muted-foreground transition-transform ${
            abierto ? 'rotate-180' : ''
          }`}
        />
      </button>

      {abierto && (
        <>
        <p className="border-t px-4 pt-2.5 text-xs text-muted-foreground">
          Copia los datos del que te guste y pégalo en el mensaje de abajo.
        </p>
        <ul className="divide-y">
          {inmuebles.map((i) => (
            <li key={i.inmueble_id} className="flex flex-col gap-1 px-4 py-2.5">
              <p className="text-sm font-medium leading-tight">{i.titulo ?? 'Sin título'}</p>

              <p className="flex flex-wrap items-center gap-x-2 text-xs text-muted-foreground">
                <span>{[i.barrio, i.ciudad].filter(Boolean).join(' · ') || 'Sin zona'}</span>
                <span aria-hidden>·</span>
                <span className="tabular">{pesos(i.precio)}</span>
                {i.habitaciones !== null && (
                  <>
                    <span aria-hidden>·</span>
                    <span>{i.habitaciones} hab</span>
                  </>
                )}
              </p>

              <div className="flex items-center gap-2">
                {/* El dato que explica el orden. Sin él, que arriba salga
                    el de hace cuatro meses parece un error. */}
                <span className="flex-1 text-xs text-muted-foreground">
                  <span className="tabular font-medium text-foreground/80">
                    Coincide {i.puntaje} %
                  </span>
                  {' · '}disponible {tiempoRelativo(i.disponible_desde)}
                </span>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => copiar(i)}
                  className="h-8 rounded-lg text-xs"
                  title="Copia título, zona, habitaciones y precio para pegarlos en el mensaje"
                >
                  {copiado === i.inmueble_id ? (
                    <>
                      <Check className="size-3.5" />
                      Copiado
                    </>
                  ) : (
                    <>
                      <Copy className="size-3.5" />
                      Copiar datos
                    </>
                  )}
                </Button>
              </div>
            </li>
          ))}
        </ul>
        </>
      )}
    </section>
  );
}
