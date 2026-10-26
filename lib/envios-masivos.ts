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

// ---------------------------------------------------------------------
// La gestión manual (migración 20261026150001)
// ---------------------------------------------------------------------

/** Una persona que hay que gestionar a mano (crm.pendientes_gestion_envio). */
export interface FilaGestion {
  destinatario_id: string;
  fila: number;
  nombre: string | null;
  telefono_crudo: string | null;
  telefono_e164: string | null;
  contacto_id: string | null;
  datos: Record<string, string> | null;
  resultado: string;
  motivo: string;
  motivo_legible: string;
  detalle: string | null;
  gestionado: boolean;
  gestionado_at: string | null;
  gestionado_por: string | null;
  gestionado_por_nombre: string | null;
  gestion_nota: string | null;
}

/** Lo que cabe en la nota de una gestión: lo mismo que exige la base. */
export const MAX_NOTA_GESTION = 500;

/** «Total_En_Mora», «total en mora», «TOTAL EN MORA ($)» → «totalenmora». */
function normalizarColumna(nombre: string): string {
  return nombre
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
}

/**
 * Las columnas de cartera que sirven para llamar a alguien con la deuda a
 * la mano, si el archivo las trae. Se buscan por nombre, sin importar
 * mayúsculas, tildes, espacios ni guiones bajos.
 */
export function columnasDeCartera(columnas: string[]): { mora: string | null; facturas: string | null } {
  const buscar = (patron: RegExp) => columnas.find((c) => patron.test(normalizarColumna(c))) ?? null;
  return {
    mora: buscar(/total.*mora|mora.*total|saldo.*mora/),
    facturas: buscar(/factura.*vencid|vencid.*factura/),
  };
}

/**
 * PostgREST corta en 1.000 filas (max_rows). Un envío puede tener hasta
 * 5.000: se piden por partes, en orden, hasta que una parte llegue corta.
 */
export async function leerPorPartes<T>(
  pedir: (desde: number, hasta: number) => PromiseLike<{ data: T[] | null; error: { message: string } | null }>,
  tamano = 1000
): Promise<{ data: T[]; error: { message: string } | null }> {
  const todas: T[] = [];
  // El tope de 20.000 es solo un seguro: un envío no pasa de MAX_FILAS.
  for (let desde = 0; desde < 20_000; desde += tamano) {
    const { data, error } = await pedir(desde, desde + tamano - 1);
    if (error) return { data: todas, error };
    todas.push(...(data ?? []));
    if ((data ?? []).length < tamano) break;
  }
  return { data: todas, error: null };
}
