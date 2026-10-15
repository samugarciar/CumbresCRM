/**
 * Lo que la pantalla y el servidor comparten sobre los envíos masivos.
 * Las reglas de verdad viven en la base (migración 20261015190001); esto
 * solo las nombra en español y las enseña.
 */

/** Lo mismo que exige crm.crear_envio_masivo: más filas, en varios envíos. */
export const MAX_FILAS = 5000;

export type EstadoEnvioMasivo = 'borrador' | 'en_curso' | 'pausado' | 'terminado' | 'cancelado';

export const ESTADOS: Record<EstadoEnvioMasivo, { texto: string; estilo: string }> = {
  borrador: { texto: 'Borrador', estilo: 'bg-muted text-muted-foreground' },
  en_curso: { texto: 'Enviando', estilo: 'bg-primary/10 text-primary' },
  pausado: { texto: 'En pausa', estilo: 'bg-warning/10 text-warning' },
  terminado: { texto: 'Terminado', estilo: 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-400' },
  cancelado: { texto: 'Cancelado', estilo: 'bg-destructive/10 text-destructive' },
};

/** Por qué una fila no sale (crm.envios_masivos_destinatarios.motivo). */
export const MOTIVOS: Record<string, string> = {
  sin_telefono: 'La fila no tiene teléfono',
  telefono_invalido: 'El teléfono no es un número válido',
  repetido: 'El mismo teléfono está en otra fila',
  faltan_datos: 'Le faltan datos para la plantilla',
  baja: 'Pidió no recibir más mensajes',
  frecuencia: 'Ya recibió un envío masivo hace poco',
  cancelado: 'El envío se canceló antes de llegarle',
};

/** Qué pasó con cada fila (crm.resultados_envio_masivo.resultado). */
export const RESULTADOS: Record<string, string> = {
  en_cola: 'En cola',
  enviando: 'Enviando',
  sin_confirmar: 'Sin confirmar',
  enviado: 'Enviado',
  entregado: 'Entregado',
  leido: 'Leído',
  fallido: 'Falló',
  excluido: 'No se envió',
  cancelado: 'Cancelado',
};

// ---------------------------------------------------------------------
// El horario
// ---------------------------------------------------------------------

/** Por día ISO (1 = lunes … 7 = domingo), la franja [desde, hasta). */
export interface Horario {
  zona: string;
  franjas: Record<string, [string, string]>;
}

export const HORARIO_POR_DEFECTO: Horario = {
  zona: 'America/Bogota',
  franjas: {
    '1': ['08:00', '18:00'],
    '2': ['08:00', '18:00'],
    '3': ['08:00', '18:00'],
    '4': ['08:00', '18:00'],
    '5': ['08:00', '18:00'],
    '6': ['08:00', '13:00'],
  },
};

/** El horario que se arma en la pantalla: una franja entre semana y otra (o ninguna) el sábado. */
export function horarioDesdeFormulario(
  semana: { desde: string; hasta: string },
  sabado: { desde: string; hasta: string } | null
): Horario {
  const franjas: Horario['franjas'] = {};
  for (const dia of ['1', '2', '3', '4', '5']) franjas[dia] = [semana.desde, semana.hasta];
  if (sabado) franjas['6'] = [sabado.desde, sabado.hasta];
  return { zona: 'America/Bogota', franjas };
}

const DIAS = ['', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábados', 'domingos'];

function hora(h: string): string {
  return h.replace(/^0(\d)/, '$1');
}

/** «Lunes a viernes de 8:00 a 18:00 · sábados de 8:00 a 13:00 · nunca domingos ni festivos». */
export function describirHorario(h: Horario): string {
  const f = h.franjas;
  const partes: string[] = [];
  const semana = ['1', '2', '3', '4', '5'];
  const igualEntreSemana =
    semana.every((d) => f[d]) && semana.every((d) => f[d][0] === f['1'][0] && f[d][1] === f['1'][1]);

  if (igualEntreSemana) {
    partes.push(`Lunes a viernes de ${hora(f['1'][0])} a ${hora(f['1'][1])}`);
  } else {
    for (const d of semana) if (f[d]) partes.push(`${DIAS[+d]} de ${hora(f[d][0])} a ${hora(f[d][1])}`);
  }
  if (f['6']) partes.push(`sábados de ${hora(f['6'][0])} a ${hora(f['6'][1])}`);
  if (f['7']) partes.push(`domingos de ${hora(f['7'][0])} a ${hora(f['7'][1])}`);

  const nunca = [!f['6'] ? 'sábados' : null, !f['7'] ? 'domingos' : null, 'festivos'].filter(Boolean);
  partes.push(`nunca ${nunca.join(', ').replace(/, ([^,]*)$/, ' ni $1')}`);

  const texto = partes.join(' · ');
  return texto.charAt(0).toUpperCase() + texto.slice(1);
}

// ---------------------------------------------------------------------
// Lo que cuesta
// ---------------------------------------------------------------------

/**
 * Lo que cobra Meta por mensaje entregado en Colombia, en dólares. NO está
 * verificado contra la tarjeta oficial: es la banda que encontró la nota 7
 * del vault en fuentes de terceros. Sirve para el orden de magnitud.
 */
export const TARIFA_USD: Record<'utilidad' | 'marketing', [number, number]> = {
  utilidad: [0.0008, 0.0034],
  marketing: [0.0125, 0.014],
};

export function costoEstimado(cuantos: number, categoria: string): [number, number] {
  const [min, max] = TARIFA_USD[categoria === 'marketing' ? 'marketing' : 'utilidad'];
  return [cuantos * min, cuantos * max];
}

export function dolares(valor: number): string {
  if (valor > 0 && valor < 0.01) return 'menos de US$0,01';
  return `US$${valor.toLocaleString('es-CO', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}
