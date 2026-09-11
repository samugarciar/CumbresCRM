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

export function iniciales(nombre: string | null): string {
  if (!nombre) return '?';
  const partes = nombre.trim().split(/\s+/).filter(Boolean);
  if (partes.length === 0) return '?';
  if (partes.length === 1) return partes[0].slice(0, 2).toUpperCase();
  return (partes[0][0] + partes[partes.length - 1][0]).toUpperCase();
}
