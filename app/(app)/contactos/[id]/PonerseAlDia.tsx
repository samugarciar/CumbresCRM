import { CalendarCheck, CalendarClock, Clock, Home, MessageSquare } from 'lucide-react';

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

function esperaLegible(segundos: number): string {
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
 * El resumen redactado por el agente vendrá después y será otra cosa:
 * se generará en el momento de escalar y se guardará inmutable.
 */
export function PonerseAlDia({ resumen }: { resumen: Resumen }) {
  const hechos: { icono: typeof Clock; texto: string; alerta?: boolean }[] = [];

  // Lo primero es lo que exige acción: alguien escribió y nadie del
  // equipo le ha contestado.
  if (resumen.esperando_segundos !== null && resumen.esperando_segundos > 0) {
    hechos.push({
      icono: Clock,
      texto: `Esperando respuesta hace ${esperaLegible(resumen.esperando_segundos)}`,
      alerta: true,
    });
  }

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

  if (hechos.length === 0) return null;

  return (
    <div className="flex flex-wrap items-center gap-x-4 gap-y-2 rounded-lg border bg-card px-4 py-3 text-sm">
      {hechos.map((h, i) => {
        const Icono = h.icono;
        return (
          <span
            key={i}
            className={`inline-flex items-center gap-1.5 ${
              h.alerta ? 'font-medium text-destructive' : 'text-muted-foreground'
            }`}
          >
            <Icono className="size-3.5 shrink-0" />
            {h.texto}
          </span>
        );
      })}
    </div>
  );
}
