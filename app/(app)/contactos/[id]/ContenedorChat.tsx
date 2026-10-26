'use client';

import { useEffect, useRef } from 'react';

/** A cuántos píxeles del fondo todavía cuenta como «estaba abajo». */
const CERCA_DEL_FONDO = 80;

/**
 * El marco de la conversación en la ficha: ocupa lo que queda de pantalla,
 * tiene su propio scroll y deja la caja de escribir siempre a la vista
 * (la caja es `sticky bottom-0` dentro de este marco).
 *
 * - Abre en el último mensaje.
 * - Cuando llega uno (ChatEnVivo hace router.refresh y React cambia lo de
 *   dentro), baja solo si quien mira ya estaba abajo: si subió a leer algo
 *   viejo, no se le arrastra.
 * - Lleva el id «escribir»: «Responder» en Mi día y en Coincidencias enlaza a
 *   /contactos/<id>#escribir, y al llegar así se pone el foco en la caja.
 *
 * La altura se mide en vez de adivinarse con CSS: la cabecera de la ficha
 * cambia de alto (el chip del bot, el aviso de espera, una o dos líneas en
 * el celular), y un `calc()` fijo dejaba la caja debajo del borde.
 */
export function ContenedorChat({ children }: { children: React.ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const pegadoAbajo = useRef(true);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const bajar = () => {
      el.scrollTop = el.scrollHeight;
    };

    const ajustarAltura = () => {
      const arriba = el.getBoundingClientRect().top + window.scrollY;
      const margen = window.matchMedia('(min-width: 768px)').matches ? 24 : 12;
      const alto = Math.max(360, Math.round(window.innerHeight - arriba - margen));
      if (el.style.height !== `${alto}px`) el.style.height = `${alto}px`;
      if (pegadoAbajo.current) bajar();
    };

    const alDesplazar = () => {
      pegadoAbajo.current = el.scrollHeight - el.scrollTop - el.clientHeight < CERCA_DEL_FONDO;
    };

    // Llega un mensaje, se carga una foto, se cambia de pestaña: si estaba
    // abajo, sigue abajo.
    const seguirAbajo = () => {
      if (pegadoAbajo.current) bajar();
    };
    const cambios = new MutationObserver(seguirAbajo);
    cambios.observe(el, { childList: true, subtree: true, characterData: true });
    const tamano = new ResizeObserver(seguirAbajo);
    for (const hijo of Array.from(el.children)) tamano.observe(hijo);

    // Lo de arriba puede crecer o encogerse (el aviso de espera se va al
    // marcar respondido): la altura se recalcula.
    const pagina = new ResizeObserver(ajustarAltura);
    pagina.observe(document.body);

    const enfocarSiToca = () => {
      if (window.location.hash !== '#escribir') return;
      const caja = el.querySelector<HTMLTextAreaElement>('textarea:not([disabled])');
      bajar();
      pegadoAbajo.current = true;
      el.scrollIntoView({ block: 'nearest' });
      caja?.focus({ preventScroll: true });
    };

    ajustarAltura();
    bajar();
    el.addEventListener('scroll', alDesplazar, { passive: true });
    window.addEventListener('resize', ajustarAltura);
    window.addEventListener('hashchange', enfocarSiToca);
    // La URL con #escribir puede quedar puesta justo después del montaje
    // cuando se llega navegando dentro de la app.
    const enfoque = setTimeout(enfocarSiToca, 50);

    return () => {
      clearTimeout(enfoque);
      cambios.disconnect();
      tamano.disconnect();
      pagina.disconnect();
      el.removeEventListener('scroll', alDesplazar);
      window.removeEventListener('resize', ajustarAltura);
      window.removeEventListener('hashchange', enfocarSiToca);
    };
  }, []);

  return (
    <div
      ref={ref}
      id="escribir"
      className="min-h-[360px] scroll-mt-4 overflow-y-auto overscroll-contain rounded-xl border bg-muted/20 p-3 pb-0 lg:h-[calc(100dvh-14rem)]"
    >
      {children}
    </div>
  );
}
