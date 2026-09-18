'use client';

import { useState, useTransition } from 'react';
import { Loader2, UserRound, UserRoundPlus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { asignarLead } from './acciones';

/**
 * Quién lleva esta conversación.
 *
 * Ser responsable NO es ser el único que puede: cualquiera sigue viendo y
 * tocando cualquier lead. Lo único que cambia es de quién es el día — y
 * que si entras a una ficha ajena, lo sabes antes de escribir.
 *
 * Un bloqueo por dueño, en un negocio donde el cliente llama al que le
 * contestó el teléfono, es una función que se salta por WhatsApp personal.
 * Y entonces el CRM vuelve a estar ciego, que es peor que el problema.
 *
 * Por eso aquí no hay candado: hay un nombre y, si no hay nadie, un botón.
 */
export function Responsable({
  contactoId,
  nombre,
  esMio,
}: {
  contactoId: string;
  nombre: string | null;
  esMio: boolean;
}) {
  const [error, setError] = useState<string | null>(null);
  const [pendiente, iniciar] = useTransition();

  const encargarme = () => {
    setError(null);
    iniciar(async () => {
      const r = await asignarLead(contactoId);
      if (!r.ok) setError(r.error ?? 'No se pudo asignar.');
    });
  };

  return (
    <section className="flex flex-col gap-2 rounded-lg border bg-card p-4">
      <div className="flex items-center justify-between gap-2">
        <h2 className="font-medium">Responsable</h2>
        {nombre && (
          <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
            <UserRound className="size-3.5" />
            {esMio ? 'Tú' : nombre}
          </span>
        )}
      </div>

      {nombre ? (
        !esMio && (
          <p className="text-xs text-muted-foreground">
            {nombre} lleva esta conversación. Puedes escribirle igual — solo
            conviene que lo sepas antes.
          </p>
        )
      ) : (
        <>
          <p className="text-xs text-muted-foreground">
            Nadie lo lleva todavía. Se asigna solo al primero que deje una
            nota, lo mueva de etapa o le ponga una tarea.
          </p>
          <Button
            size="sm"
            variant="outline"
            className="w-fit"
            onClick={encargarme}
            disabled={pendiente}
          >
            {pendiente ? (
              <Loader2 className="animate-spin" />
            ) : (
              <UserRoundPlus className="size-3.5" />
            )}
            Me encargo yo
          </Button>
        </>
      )}

      {error && (
        <p role="alert" className="text-xs text-destructive">
          {error}
        </p>
      )}
    </section>
  );
}
