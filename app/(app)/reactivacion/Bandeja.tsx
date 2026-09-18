'use client';

import { useState, useTransition } from 'react';
import Link from 'next/link';
import { BellOff, Home, Loader2, MessageSquareText } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { tiempoRelativo, telefonoLegible } from '@/lib/formato';
import { UsarPlantilla, type PlantillaResumen } from '@/app/(app)/contactos/[id]/UsarPlantilla';
import { marcarOptOut } from './acciones';

export interface Reactivable {
  contacto_id: string;
  nombre: string | null;
  telefono_e164: string | null;
  dias_callado: number;
  ultima_actividad_at: string;
  busca: string | null;
  calzan: number;
}

/**
 * A quién escribirle hoy de los que se quedaron callados.
 *
 * El orden es del MÁS callado al menos, y va contra el instinto a
 * propósito: lo reciente se atiende solo, y al que lleva cuatro meses no
 * le escribe nadie nunca. Mismo criterio que la rotación de inmuebles.
 *
 * Lo que hace útil la lista no es quién está callado —eso es una fecha—
 * sino el cruce: **qué pidió** y **cuántos inmuebles le calzan hoy**. La
 * diferencia entre «hace mucho que no hablamos» y «apareció lo que
 * buscabas» es toda la diferencia.
 */
export function Bandeja({
  gente,
  plantillas,
  asesor,
  ahora,
}: {
  gente: Reactivable[];
  plantillas: PlantillaResumen[];
  asesor: string | null;
  ahora: string;
}) {
  const [pendiente, iniciar] = useTransition();
  const [saliendo, setSaliendo] = useState<string | null>(null);

  const sacar = (id: string) => {
    setSaliendo(id);
    iniciar(async () => {
      await marcarOptOut(id, 'Lo pidió el cliente');
      setSaliendo(null);
    });
  };

  if (gente.length === 0) {
    return (
      <div className="rounded-lg border border-dashed py-14 text-center">
        <p className="font-medium">No hay nadie dormido</p>
        <p className="text-sm text-muted-foreground">
          Todo el mundo ha tenido actividad reciente.
        </p>
      </div>
    );
  }

  return (
    <ul className="flex flex-col gap-2">
      {gente.map((p) => (
        <li key={p.contacto_id} className="rounded-lg border bg-card p-3.5">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-baseline gap-x-2">
                <Link
                  href={`/contactos/${p.contacto_id}`}
                  className="font-medium hover:underline"
                >
                  {p.nombre?.trim() || 'Sin nombre'}
                </Link>
                <span className="tabular text-xs text-muted-foreground">
                  {telefonoLegible(p.telefono_e164) ?? 'sin teléfono'}
                </span>
              </div>

              {/* Lo que pidió antes de callarse. Sin esto la lista es una
                  guía telefónica; con esto es una razón para escribir. */}
              <p className="mt-1 text-sm text-muted-foreground">
                {p.busca ? (
                  <>Buscaba {p.busca}</>
                ) : (
                  <span className="italic">Nunca dijo qué buscaba</span>
                )}
              </p>

              <p className="mt-1 flex flex-wrap items-center gap-x-2 text-xs text-muted-foreground">
                <span>callado {tiempoRelativo(p.ultima_actividad_at)}</span>
                {p.calzan > 0 && (
                  <>
                    <span aria-hidden>·</span>
                    <span className="inline-flex items-center gap-1 font-medium text-primary">
                      <Home className="size-3" />
                      {p.calzan} le calzan hoy
                    </span>
                  </>
                )}
              </p>
            </div>

            <div className="flex shrink-0 items-center gap-1">
              <UsarPlantilla
                plantillas={plantillas}
                contactoId={p.contacto_id}
                asesor={asesor}
                etiqueta="Escribirle"
                ventanaCierraAt={p.ultima_actividad_at}
                ahora={ahora}
              />
              <Button
                size="xs"
                variant="ghost"
                onClick={() => sacar(p.contacto_id)}
                disabled={pendiente}
                title="Pidió que no le escribamos más"
              >
                {pendiente && saliendo === p.contacto_id ? (
                  <Loader2 className="size-3 animate-spin" />
                ) : (
                  <BellOff className="size-3" />
                )}
              </Button>
            </div>
          </div>
        </li>
      ))}
    </ul>
  );
}

export function CabeceraVentana({ total }: { total: number }) {
  return (
    <p className="flex items-start gap-2 rounded-lg bg-warning/10 px-3.5 py-3 text-sm text-warning">
      <MessageSquareText className="mt-0.5 size-4 shrink-0" />
      <span>
        <b>Las {total} están fuera de la ventana de 24 horas</b>, por definición:
        llevan dos semanas o más sin escribir. WhatsApp solo deja mandarles una
        plantilla aprobada — el texto libre no les llega y nadie avisa.
      </span>
    </p>
  );
}
