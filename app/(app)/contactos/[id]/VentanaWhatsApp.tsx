import { Clock, TriangleAlert } from 'lucide-react';

/**
 * Si se le puede escribir libremente a esta persona, y hasta cuándo.
 *
 * WhatsApp solo deja mandar texto libre durante 24 horas desde el último
 * mensaje DEL CLIENTE. Pasadas, únicamente plantillas aprobadas por Meta:
 * cualquier otra cosa la rechaza con el error 131047 y **el cliente no
 * recibe nada**, sin que el asesor se entere.
 *
 * Por eso esto se enseña ANTES de escribir y no después de fallar. Se usa
 * en la calle, en un celular, con alguien delante.
 *
 * Nuestros mensajes no cuentan: la ventana la abre el cliente. Un asesor
 * que ve "le escribí hace un rato" y deduce que hay margen se equivoca.
 *
 * `ahora` llega como dato del servidor en vez de leerse aquí con
 * Date.now(): así el render es puro —mismas props, mismo resultado— que
 * es lo que React 19 exige. Y de paso el reloj es el del servidor, no el
 * del celular del asesor, que puede estar desajustado.
 */
export function VentanaWhatsApp({
  cierraAt,
  ahora,
  compacto = false,
}: {
  cierraAt: string | null;
  ahora: string;
  compacto?: boolean;
}) {
  const cierra = cierraAt ? new Date(cierraAt) : null;
  const t = new Date(ahora).getTime();
  const abierta = cierra !== null && cierra.getTime() > t;

  const horas = cierra
    ? Math.max(0, Math.round((cierra.getTime() - t) / 3_600_000))
    : 0;

  const hora = cierra
    ? new Intl.DateTimeFormat('es-CO', {
        hour: '2-digit',
        minute: '2-digit',
        hour12: true,
        timeZone: 'America/Bogota',
      }).format(cierra)
    : null;

  if (abierta) {
    const texto =
      horas >= 1
        ? `Puedes escribirle libremente ${horas} h más, hasta las ${hora}.`
        : `Te queda menos de una hora, hasta las ${hora}.`;
    return (
      <p
        className={`flex items-start gap-1.5 text-xs text-muted-foreground ${
          compacto ? '' : 'px-1'
        }`}
      >
        <Clock className="mt-0.5 size-3.5 shrink-0" />
        {texto}
      </p>
    );
  }

  return (
    <p
      className={`flex items-start gap-1.5 text-xs text-warning ${
        compacto ? '' : 'px-1'
      }`}
    >
      <TriangleAlert className="mt-0.5 size-3.5 shrink-0" />
      {cierra === null
        ? 'Esta persona nunca nos ha escrito, así que WhatsApp no deja mandarle texto libre: solo una plantilla aprobada.'
        : 'Pasaron más de 24 h desde su último mensaje. El texto libre no le llegará — solo una plantilla aprobada.'}
    </p>
  );
}
