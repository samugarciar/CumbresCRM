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
 *
 * Si lo que queda de pantalla es poco (una laptop con la cabecera y el aviso
 * de espera arriba), el marco no se encoge hasta el mínimo: toma casi toda
 * la ventana y la página baja un poco para verlo entero. Antes se quedaba
 * en 360 px y los mensajes vivían en una franja de ~130 px.
 */
const ALTO_COMODO = 480;
const ALTO_MAXIMO_PANTALLA = 720;
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
      const restante = Math.round(window.innerHeight - arriba - margen);
      const alto =
        restante >= ALTO_COMODO
          ? restante
          : Math.max(360, Math.min(window.innerHeight - 2 * margen - 56, ALTO_MAXIMO_PANTALLA));
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

    // Al cambiar de pestaña (Chat, Historial, Visitas, Notas internas): el
    // chat se lee desde el último mensaje; lo demás, desde arriba, que es
    // donde están lo más nuevo y el editor de notas. Va DESPUÉS de
    // `cambios`, para que este ajuste sea el último que se aplica.
    const pestanas = new MutationObserver((registros) => {
      const activa = registros
        .map((r) => r.target as HTMLElement)
        .find((b) => b.getAttribute('aria-pressed') === 'true');
      if (!activa) return;
      if (activa === activa.parentElement?.firstElementChild) {
        pegadoAbajo.current = true;
        bajar();
      } else {
        pegadoAbajo.current = false;
        el.scrollTop = 0;
      }
    });
    pestanas.observe(el, { subtree: true, attributes: true, attributeFilter: ['aria-pressed'] });

    // Lo de arriba puede crecer o encogerse (el aviso de espera se va al
    // marcar respondido): la altura se recalcula.
    const pagina = new ResizeObserver(ajustarAltura);
    pagina.observe(document.body);

    // La caja de texto; fuera de la ventana de 24 h no hay texto libre y
    // lo primero es elegir la plantilla. Puede tardar un momento en estar
    // lista (la plantilla se rellena en el servidor y mientras tanto el
    // select está deshabilitado): se reintenta unas veces, y se deja de
    // intentar si quien mira ya puso el foco en otra cosa.
    let intentos = 0;
    let reintento: ReturnType<typeof setTimeout> | undefined;
    const enfocarSiToca = () => {
      if (window.location.hash !== '#escribir') return;
      if (intentos === 0) {
        bajar();
        pegadoAbajo.current = true;
        el.scrollIntoView({ block: 'nearest' });
      }
      const caja =
        el.querySelector<HTMLElement>('textarea:not([disabled])') ??
        el.querySelector<HTMLElement>('#select-reactivacion:not([disabled])');
      if (caja) {
        caja.focus({ preventScroll: true });
        return;
      }
      const libre = !document.activeElement || document.activeElement === document.body;
      if (libre && ++intentos < 12) reintento = setTimeout(enfocarSiToca, 250);
    };

    ajustarAltura();
    bajar();
    // Al abrir la ficha en una pantalla baja, el marco no cabe entero: la
    // página baja lo justo para dejarlo completo a la vista, con la caja de
    // escribir abajo, como en WhatsApp Web. Solo al abrir y solo si nadie
    // ha movido la página: después, quien mira manda.
    const marco = el.getBoundingClientRect();
    const sobra = marco.bottom - window.innerHeight;
    if (sobra > 0 && window.scrollY === 0) {
      window.scrollTo({ top: Math.ceil(sobra) + 8, behavior: 'instant' });
    }
    el.addEventListener('scroll', alDesplazar, { passive: true });
    window.addEventListener('resize', ajustarAltura);
    window.addEventListener('hashchange', enfocarSiToca);
    // La URL con #escribir puede quedar puesta justo después del montaje
    // cuando se llega navegando dentro de la app.
    const enfoque = setTimeout(enfocarSiToca, 50);

    return () => {
      clearTimeout(enfoque);
      clearTimeout(reintento);
      cambios.disconnect();
      pestanas.disconnect();
      tamano.disconnect();
      pagina.disconnect();
      el.removeEventListener('scroll', alDesplazar);
      window.removeEventListener('resize', ajustarAltura);
      window.removeEventListener('hashchange', enfocarSiToca);
    };
  }, []);

  // En escritorio, la barra de pestañas de Historial (su primer hijo) queda
  // fija arriba del marco: el chat abre en el fondo y, sin esto, «Historial»
  // y «Notas internas» solo aparecían subiendo por toda la conversación.
  // En el celular no: ahí el marco es bajo y cada píxel es para mensajes.
  return (
    <div
      ref={ref}
      id="escribir"
      className="min-h-[360px] scroll-mt-4 overflow-y-auto overscroll-contain rounded-xl border bg-muted/20 p-3 pb-0 lg:h-[calc(100dvh-14rem)] lg:[&>section>div:first-child]:sticky lg:[&>section>div:first-child]:-top-3 lg:[&>section>div:first-child]:z-20 lg:[&>section>div:first-child]:bg-card"
    >
      {children}
    </div>
  );
}
