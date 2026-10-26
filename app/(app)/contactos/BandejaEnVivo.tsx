'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { createClient } from '@/lib/supabase/client';

// Un cliente que manda tres mensajes seguidos, o el bot que contesta por
// partes, son UNA recarga, no tres. Dos segundos agrupan eso y dejan el
// mensaje en pantalla bastante antes de cinco.
const AGRUPAR_MS = 2000;

/**
 * Mantiene la bandeja (y Mi día) al día mientras están abiertas. No pinta
 * nada.
 *
 * Escucha por Realtime los mensajes ENTRANTES nuevos —los de cualquier
 * cliente que la RLS le deje ver a quien mira— y pide la página otra vez
 * con router.refresh(). El orden, el 🔥 de «esperando», los «N nuevos» y
 * los conteos se calculan en la base: pegar la fila que llega dejaría todo
 * eso viejo.
 *
 * Mismo patrón que ChatEnVivo de la ficha: un nombre de canal por montaje
 * y la unión en el siguiente tick, porque despedirse de un canal y unirse a
 * otro en el mismo instante dejaba al nuevo «SUBSCRIBED» sin suscripción
 * en el servidor (prueba local del 25 oct).
 *
 * `pausado`: con un cursor de paginación («Cargar más») la página muestra
 * un tramo fijo de la lista; recargarla sola movería lo que se está leyendo.
 */
export function BandejaEnVivo({ pausado = false }: { pausado?: boolean }) {
  const router = useRouter();

  useEffect(() => {
    if (pausado) return;

    const supabase = createClient();
    let temporizador: ReturnType<typeof setTimeout> | undefined;
    let yaSuscrito = false;

    const refrescar = () => {
      if (temporizador) return;
      temporizador = setTimeout(() => {
        temporizador = undefined;
        router.refresh();
      }, AGRUPAR_MS);
    };

    let canal: RealtimeChannel | undefined;
    const arranque = setTimeout(() => {
      canal = supabase
        .channel(`bandeja:${Math.random().toString(36).slice(2)}`)
        .on(
          'postgres_changes',
          {
            event: 'INSERT',
            schema: 'crm',
            table: 'actividades',
            filter: 'tipo=eq.mensaje_entrante',
          },
          refrescar
        )
        .subscribe((estado) => {
          if (estado !== 'SUBSCRIBED') return;
          // Tras una reconexión pudo entrar algo mientras no había canal.
          if (yaSuscrito) refrescar();
          yaSuscrito = true;
        });
    }, 0);

    return () => {
      clearTimeout(arranque);
      clearTimeout(temporizador);
      if (canal) supabase.removeChannel(canal);
    };
  }, [pausado, router]);

  return null;
}
