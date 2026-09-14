'use client';

import { useEffect } from 'react';
import { marcarLeido } from './acciones';

/**
 * Marca la ficha como leída al abrirla. No pinta nada.
 *
 * Va en un componente cliente a propósito: así solo cuenta como "leído"
 * cuando un navegador de verdad monta la página, no cuando el servidor
 * la prerenderiza o alguien la precarga al pasar el cursor por encima.
 */
export function MarcarLeido({ contactoId }: { contactoId: string }) {
  useEffect(() => {
    marcarLeido(contactoId);
  }, [contactoId]);

  return null;
}
