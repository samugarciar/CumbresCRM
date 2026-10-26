import { CalendarCheck, CalendarClock, Home, MessageSquare } from 'lucide-react';
import { BotonMarcarAtendido } from '../BotonMarcarAtendido';

export interface Resumen {
  mensajes_cliente: number | null;
  mensajes_bot: number | null;
  esperando_segundos: number | null;
  visitas_agendadas: number | null;
  visitas_realizadas: number | null;
  visitas_canceladas: number | null;
  solicitudes_horario: number | null;
  inmuebles: string[] | null;
  actividades_total: number | null;
  sin_leer: number | null;
  visto_hasta: string | null;
}

export function esperaLegible(segundos: number): string {
  const min = Math.round(segundos / 60);
  if (min < 60) return `${min} min`;
  const horas = Math.round(min / 60);
  if (horas < 48) return `${horas} h`;
  return `${Math.round(horas / 24)} días`;
}

/**
 * Los hechos duros de un contacto, para ponerse al día en cuatro segundos.
 *
 * Todo lo que se muestra aquí está CONTADO CON SQL, no redactado: cuántos
 * mensajes, qué visitas, qué inmuebles, cuánto lleva esperando. Cero
 * riesgo de que diga algo que no pasó, y cero costo por abrir la ficha.
 *
 * Si la persona está esperando respuesta, el bloque se vuelve EL aviso de
 * la ficha, con su botón. Antes había un aviso naranja arriba y otra línea
 * «Esperando respuesta hace…» justo debajo: lo mismo dos veces.
 */
export function PonerseAlDia({ resumen, contactoId }: { resumen: Resumen; contactoId: string }) {
  const hechos: { icono: typeof Home; texto: string }[] = [];

  const mensajes = (resumen.mensajes_cliente ?? 0) + (resumen.mensajes_bot ?? 0);
  if (mensajes > 0) {
    hechos.push({
      icono: MessageSquare,
      texto: `${mensajes} mensajes · ${resumen.mensajes_cliente ?? 0} suyos`,
    });
  }

  const visitas: string[] = [];
  if (resumen.visitas_realizadas) visitas.push(`${resumen.visitas_realizadas} realizada${resumen.visitas_realizadas > 1 ? 's' : ''}`);
  if (resumen.visitas_agendadas) visitas.push(`${resumen.visitas_agendadas} agendada${resumen.visitas_agendadas > 1 ? 's' : ''}`);
  if (resumen.visitas_canceladas) visitas.push(`${resumen.visitas_canceladas} cancelada${resumen.visitas_canceladas > 1 ? 's' : ''}`);
  if (visitas.length) {
    hechos.push({ icono: CalendarCheck, texto: `Visitas: ${visitas.join(' · ')}` });
  }

  if (resumen.solicitudes_horario) {
    hechos.push({
      icono: CalendarClock,
      texto: `Pidió horario ${resumen.solicitudes_horario} ${resumen.solicitudes_horario > 1 ? 'veces' : 'vez'}`,
    });
  }

  const inmuebles = resumen.inmuebles ?? [];
  if (inmuebles.length) {
    hechos.push({
      icono: Home,
      texto:
        inmuebles.length <= 2
          ? inmuebles.join(' · ')
          : `${inmuebles.slice(0, 2).join(' · ')} y ${inmuebles.length - 2} más`,
    });
  }

  const esperando =
    resumen.esperando_segundos !== null && resumen.esperando_segundos > 0
      ? resumen.esperando_segundos
      : null;

  // En el celular los hechos se esconden: ahí manda la conversación, y
  // ocupaban media pantalla antes de llegar al primer mensaje.
  const lista = hechos.length > 0 && (
    <ul className="hidden flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted-foreground sm:flex">
      {hechos.map((h, i) => {
        const Icono = h.icono;
        return (
          <li key={i} className="inline-flex items-center gap-1.5">
            <Icono className="size-3.5 shrink-0" />
            {h.texto}
          </li>
        );
      })}
    </ul>
  );

  if (esperando !== null) {
    return (
      // Una sola franja: cada renglón de más aquí es altura que pierde el chat.
      <div
        className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1.5 rounded-xl border border-amber-500/30 bg-amber-500/10 px-4 py-2"
        title="Si ya lo atendiste por llamada o en persona, márcalo como respondido."
      >
        <div className="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1">
          <p className="flex items-center gap-2 text-sm font-semibold text-foreground">
            <span className="size-2 shrink-0 rounded-full bg-amber-500" aria-hidden />
            Está esperando tu respuesta hace {esperaLegible(esperando)}
          </p>
          {lista}
        </div>
        <BotonMarcarAtendido contactoId={contactoId} variante="completo" />
      </div>
    );
  }

  if (!lista) return null;

  return <div className="hidden rounded-xl border bg-card px-4 py-2.5 sm:block">{lista}</div>;
}
