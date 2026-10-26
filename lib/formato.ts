const RELATIVO = new Intl.RelativeTimeFormat('es-CO', { numeric: 'auto' });

const ESCALAS: [Intl.RelativeTimeFormatUnit, number][] = [
  ['year', 365 * 24 * 60 * 60 * 1000],
  ['month', 30 * 24 * 60 * 60 * 1000],
  ['day', 24 * 60 * 60 * 1000],
  ['hour', 60 * 60 * 1000],
  ['minute', 60 * 1000],
];

/** "hace 3 días". En una bandeja de CRM la antigüedad importa más que la fecha exacta. */
export function tiempoRelativo(fecha: string | Date | null): string {
  if (!fecha) return '—';
  const ms = new Date(fecha).getTime() - Date.now();
  for (const [unidad, tamano] of ESCALAS) {
    if (Math.abs(ms) >= tamano) {
      return RELATIVO.format(Math.round(ms / tamano), unidad);
    }
  }
  return 'hace un momento';
}

const FECHA_LARGA = new Intl.DateTimeFormat('es-CO', {
  dateStyle: 'medium',
  timeStyle: 'short',
  timeZone: 'America/Bogota',
});

export function fechaLarga(fecha: string | Date | null): string {
  if (!fecha) return '—';
  return FECHA_LARGA.format(new Date(fecha));
}

/**
 * +573001234567 → +57 300 123 4567
 * Los números guardados están en E.164, que es correcto pero ilegible.
 * Lo que no sea un móvil colombiano se deja tal cual: inventar formatos
 * para otros países es peor que no formatear.
 */
export function telefonoLegible(e164: string | null): string | null {
  if (!e164) return null;
  const m = e164.match(/^\+57(3\d{2})(\d{3})(\d{4})$/);
  if (m) return `+57 ${m[1]} ${m[2]} ${m[3]}`;
  return e164;
}

/** Para enlazar a WhatsApp desde la ficha. */
export function enlaceWhatsApp(e164: string | null): string | null {
  if (!e164) return null;
  return `https://wa.me/${e164.replace(/\D/g, '')}`;
}

/**
 * «Paola Jiménez» → «PJ». Solo cuentan las letras: «Paola (prueba)» da
 * «PP» y no «P(», y un nombre sin letras cae a «?».
 */
export function iniciales(nombre: string | null): string {
  if (!nombre) return '?';
  const partes = nombre
    .trim()
    .split(/\s+/)
    .map((p) => p.replace(/[^\p{L}]/gu, ''))
    .filter(Boolean);
  if (partes.length === 0) return '?';
  if (partes.length === 1) return partes[0].slice(0, 2).toUpperCase();
  return (partes[0][0] + partes[partes.length - 1][0]).toUpperCase();
}

// ---------------------------------------------------------------------
// Horas y días en hora de Colombia
//
// Todo lo que pinta una hora o agrupa por día lleva la zona explícita.
// Sin ella, el servidor (en UTC) y el navegador (en Bogotá) escriben
// horas distintas para el mismo mensaje y React se queja de la
// hidratación; y desde las 7 p. m. el separador de día cambia de fecha.
// ---------------------------------------------------------------------
export const ZONA_COLOMBIA = 'America/Bogota';

const HORA_CORTA = new Intl.DateTimeFormat('es-CO', {
  hour: 'numeric',
  minute: '2-digit',
  timeZone: ZONA_COLOMBIA,
});

/** «10:11 p. m.», en hora de Colombia. */
export function horaCorta(fecha: string | Date | null): string {
  if (!fecha) return '';
  return HORA_CORTA.format(new Date(fecha));
}

const LLAVE_DIA = new Intl.DateTimeFormat('en-CA', { timeZone: ZONA_COLOMBIA });

/** «2026-10-24»: el día de Colombia, para agrupar y comparar. */
export function llaveDia(fecha: string | Date | null): string {
  if (!fecha) return '';
  return LLAVE_DIA.format(new Date(fecha));
}

const DIA_CORTO = new Intl.DateTimeFormat('es-CO', {
  weekday: 'short',
  day: 'numeric',
  month: 'short',
  timeZone: ZONA_COLOMBIA,
});

/**
 * El separador de día del chat: «Hoy», «Ayer» o «sáb 24 oct» (con el año
 * si no es el de `ahora`). `ahora` viene del servidor para que el servidor
 * y el navegador digan lo mismo.
 */
export function etiquetaDia(fecha: string | Date | null, ahora: string | Date = new Date()): string {
  if (!fecha) return '';
  const dia = llaveDia(fecha);
  const hoy = llaveDia(ahora);
  if (dia === hoy) return 'Hoy';
  const [a, m, d] = hoy.split('-').map(Number);
  const ayer = new Date(Date.UTC(a, m - 1, d - 1)).toISOString().slice(0, 10);
  if (dia === ayer) return 'Ayer';

  const partes = DIA_CORTO.formatToParts(new Date(fecha));
  const parte = (tipo: Intl.DateTimeFormatPartTypes) =>
    (partes.find((p) => p.type === tipo)?.value ?? '').replace(/\.$/, '');
  const texto = `${parte('weekday')} ${parte('day')} ${parte('month')}`;
  return dia.slice(0, 4) === hoy.slice(0, 4) ? texto : `${texto} ${dia.slice(0, 4)}`;
}
