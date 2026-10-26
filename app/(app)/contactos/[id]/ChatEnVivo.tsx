'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { createClient } from '@/lib/supabase/client';
import { marcarLeido } from './acciones';

// El bot contesta en varias partes seguidas (response.part_N): una sola
// recarga para todas, no una por burbuja.
const AGRUPAR_MS = 400;

/**
 * Mantiene la ficha al día mientras está abierta. No pinta nada.
 *
 * Escucha por Realtime las actividades NUEVAS de esta persona —el mensaje
 * del cliente, la respuesta del bot, el envío de otro asesor, una nota— y
 * cuando llega una pide al servidor la ficha otra vez con router.refresh().
 *
 * NO PEGA LA FILA QUE LLEGA, y es deliberado: con un mensaje entrante
 * también cambian la ventana de 24 h, el aviso de «está esperando» y el
 * resumen, que se calculan en la base. Pegar la burbuja y dejar lo demás
 * viejo sería enseñar una ficha que se contradice. La recarga conserva lo
 * que se está escribiendo en la caja y la pestaña elegida.
 *
 * La RLS decide qué llega: Realtime pasa cada fila por la política de
 * lectura con el token de quien mira, así que el filtro por contacto es
 * para no despertar a todas las fichas abiertas, no para proteger nada.
 */
export function ChatEnVivo({ contactoId }: { contactoId: string }) {
  const router = useRouter();

  useEffect(() => {
    const supabase = createClient();
    let temporizador: ReturnType<typeof setTimeout> | undefined;
    let yaSuscrito = false;
    // Lo que llegó con la pestaña oculta no lo vio nadie todavía.
    let leerAlVolver = false;

    const refrescar = () => {
      if (temporizador) return;
      temporizador = setTimeout(async () => {
        temporizador = undefined;
        // Si la ficha está a la vista, lo que acaba de entrar ya se leyó:
        // sin esto, la bandeja lo daría por no leído aunque el asesor lo
        // tuviera delante.
        if (document.visibilityState === 'visible') {
          await marcarLeido(contactoId);
        } else {
          leerAlVolver = true;
        }
        router.refresh();
      }, AGRUPAR_MS);
    };

    // Se une en el siguiente tick, no ahora. Un montaje que se deshace en
    // el acto (el doble montaje de React en desarrollo, saltar de una ficha
    // a otra) nunca llega a unirse: despedirse de un canal y unirse a otro
    // en el mismo instante dejaba al nuevo diciendo SUBSCRIBED sin
    // suscripción en el servidor (realtime.subscription vacía). Pasó en la
    // prueba local del 25 oct.
    let canal: RealtimeChannel | undefined;
    const arranque = setTimeout(() => {
      canal = supabase
        // Un nombre por montaje, no por contacto: el cliente del navegador
        // es uno para toda la app, y el canal viejo se despide sin esperar.
        .channel(`ficha:${contactoId}:${Math.random().toString(36).slice(2)}`)
        .on(
          'postgres_changes',
          {
            event: 'INSERT',
            schema: 'crm',
            table: 'actividades',
            filter: `contacto_id=eq.${contactoId}`,
          },
          refrescar
        )
        .subscribe((estado) => {
          if (estado !== 'SUBSCRIBED') return;
          // Tras una reconexión (el portátil se durmió, se fue la red)
          // pudo entrar algo mientras no había canal: se recarga.
          if (yaSuscrito) refrescar();
          yaSuscrito = true;
        });
    }, 0);

    const alCambiarVisibilidad = () => {
      if (document.visibilityState === 'visible' && leerAlVolver) {
        leerAlVolver = false;
        marcarLeido(contactoId);
      }
    };
    document.addEventListener('visibilitychange', alCambiarVisibilidad);

    return () => {
      clearTimeout(arranque);
      clearTimeout(temporizador);
      document.removeEventListener('visibilitychange', alCambiarVisibilidad);
      if (canal) supabase.removeChannel(canal);
    };
  }, [contactoId, router]);

  return null;
}
