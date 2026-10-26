'use client';

import { useState } from 'react';
import { Check, Copy } from 'lucide-react';

/**
 * Copia el número tal cual (E.164), por si hay que llamarlo o agendarlo.
 *
 * Reemplaza al botón verde «Abrir WhatsApp» de la cabecera, que sacaba al
 * asesor de la línea oficial a su WhatsApp personal: lo que se le escribe al
 * cliente sale por la caja de la ficha.
 */
export function CopiarNumero({ telefono }: { telefono: string }) {
  const [copiado, setCopiado] = useState(false);

  const copiar = async () => {
    try {
      await navigator.clipboard.writeText(telefono);
      setCopiado(true);
      setTimeout(() => setCopiado(false), 2000);
    } catch {
      // Sin permiso de portapapeles: el número está a la vista.
    }
  };

  return (
    <button
      type="button"
      onClick={copiar}
      className="inline-flex items-center gap-1 rounded-md px-1 py-0.5 text-xs text-muted-foreground hover:bg-muted hover:text-foreground"
      title="Copiar número"
    >
      {copiado ? <Check className="size-3" /> : <Copy className="size-3" />}
      {copiado ? 'Copiado' : 'Copiar número'}
    </button>
  );
}
