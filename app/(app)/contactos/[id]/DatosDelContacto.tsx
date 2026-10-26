'use client';

import { useState } from 'react';
import { ChevronDown, IdCard } from 'lucide-react';

/**
 * La columna de datos de la ficha (responsable, bot, datos, casos,
 * recomendaciones).
 *
 * En el escritorio está siempre abierta, a la izquierda. En el celular va
 * DESPUÉS de la conversación y plegada en «Datos del contacto»: lo primero
 * que busca quien abre una ficha en la calle es qué le escribieron y la
 * caja para contestar, no seis tarjetas de datos.
 */
export function DatosDelContacto({
  children,
  className = '',
}: {
  children: React.ReactNode;
  className?: string;
}) {
  const [abierto, setAbierto] = useState(false);

  return (
    <div className={`flex flex-col gap-3 ${className}`}>
      <button
        type="button"
        onClick={() => setAbierto((v) => !v)}
        aria-expanded={abierto}
        className="flex w-full items-center gap-2 rounded-xl border bg-card px-4 py-3 text-left text-sm font-semibold lg:hidden"
      >
        <IdCard className="size-4 shrink-0 text-muted-foreground" />
        <span className="flex-1">Datos del contacto</span>
        <ChevronDown
          className={`size-4 shrink-0 text-muted-foreground transition-transform ${
            abierto ? 'rotate-180' : ''
          }`}
        />
      </button>

      <div className={`${abierto ? 'flex' : 'hidden'} flex-col gap-4 lg:flex`}>{children}</div>
    </div>
  );
}
