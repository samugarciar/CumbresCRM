'use client';

import { useState } from 'react';
import { Check, ChevronDown, Copy, Home } from 'lucide-react';
import { tiempoRelativo } from '@/lib/formato';
import { Button } from '@/components/ui/button';
import { UsarPlantilla, type PlantillaResumen } from './UsarPlantilla';

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
 */
export function Recomendaciones({
  inmuebles,
  plantillas,
  contactoId,
  asesor,
}: {
  inmuebles: Recomendable[];
  plantillas: PlantillaResumen[];
  contactoId: string;
  asesor: string | null;
}) {
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
    <section className="overflow-hidden rounded-lg border bg-card">
      <button
        type="button"
        onClick={() => setAbierto((v) => !v)}
        aria-expanded={abierto}
        className="flex w-full items-center gap-2 px-3 py-2.5 text-left text-sm hover:bg-muted"
      >
        <Home className="size-4 shrink-0 text-muted-foreground" />
        <span className="flex-1 font-medium">
          {inmuebles.length} para recomendarle
        </span>
        <ChevronDown
          className={`size-4 shrink-0 text-muted-foreground transition-transform ${
            abierto ? 'rotate-180' : ''
          }`}
        />
      </button>

      {abierto && (
        <ul className="divide-y border-t">
          {inmuebles.map((i) => (
            <li key={i.inmueble_id} className="flex flex-col gap-1 px-3 py-2.5">
              <div className="flex items-start gap-2">
                <span
                  className="tabular shrink-0 text-xs font-semibold text-muted-foreground"
                  title={`Cumple el ${i.puntaje}% de lo que pidió`}
                >
                  {i.puntaje}
                </span>
                <p className="min-w-0 flex-1 text-sm font-medium leading-tight">
                  {i.titulo ?? 'Sin título'}
                </p>
              </div>

              <p className="flex flex-wrap items-center gap-x-2 pl-6 text-xs text-muted-foreground">
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

              <div className="flex items-center gap-2 pl-6">
                {/* El dato que explica el orden. Sin él, que arriba salga
                    el de hace cuatro meses parece un error. */}
                <span className="flex-1 text-xs text-muted-foreground">
                  disponible {tiempoRelativo(i.disponible_desde)}
                </span>
                {/* La plantilla es el camino principal: sale con el
                    nombre de la persona y el del asesor, no como una ficha
                    técnica pegada de golpe. El copiar crudo se queda al
                    lado para cuando alguien solo quiere los datos. */}
                <UsarPlantilla
                  plantillas={plantillas}
                  contactoId={contactoId}
                  inmuebleId={i.inmueble_id}
                  asesor={asesor}
                  etiqueta="Plantilla"
                />
                <Button size="xs" variant="ghost" onClick={() => copiar(i)}>
                  {copiado === i.inmueble_id ? (
                    <>
                      <Check className="size-3" />
                      Copiado
                    </>
                  ) : (
                    <>
                      <Copy className="size-3" />
                      Datos
                    </>
                  )}
                </Button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
