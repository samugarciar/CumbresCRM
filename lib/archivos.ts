/**
 * Leer el archivo de cartera y escribir el de resultados, en el navegador.
 *
 * El archivo no viaja al servidor: se lee aquí, se convierte en filas de
 * texto (encabezado → valor) y solo eso se manda. Las librerías se cargan
 * cuando hacen falta, para no pesarle a ninguna otra pantalla.
 *
 * Solo para componentes de cliente.
 */
import { MAX_FILAS } from '@/lib/envios-masivos';

export interface ArchivoLeido {
  nombre: string;
  /** La hoja de donde salen columnas y filas; null en un CSV. */
  hoja: string | null;
  columnas: string[];
  filas: Record<string, string>[];
}

/**
 * Un archivo abierto: todas sus hojas, con las celdas ya como texto. Un
 * .xlsx de cartera trae varias (la de los envíos es la quinta); un CSV es
 * una sola hoja sin nombre.
 */
export interface LibroLeido {
  nombre: string;
  hojas: { nombre: string | null; tabla: string[][] }[];
}

/** Cómo se llama la hoja de cartera con los números de WhatsApp («Envios WhatsApp»). */
const HOJA_DE_ENVIOS = /env[ií]os?\s*whats/i;

/**
 * Una celda de Excel, como texto. Un teléfono guardado como número llega
 * como 3001234567 y tiene que quedar «3001234567», no «3001234567.0»: con
 * el punto, la base lo leería como un número de once dígitos y lo
 * descartaría.
 */
function celdaATexto(celda: unknown): string {
  if (celda === null || celda === undefined) return '';
  if (typeof celda === 'number') {
    return Number.isInteger(celda) ? String(celda) : String(celda).replace('.', ',');
  }
  if (typeof celda === 'boolean') return celda ? 'Sí' : 'No';
  if (celda instanceof Date) {
    const d = String(celda.getUTCDate()).padStart(2, '0');
    const m = String(celda.getUTCMonth() + 1).padStart(2, '0');
    return `${d}/${m}/${celda.getUTCFullYear()}`;
  }
  return String(celda).trim();
}

/** UTF-8 si lo es; si no, lo que guarda Excel en español: Windows-1252. */
async function decodificar(archivo: File): Promise<string> {
  const bytes = new Uint8Array(await archivo.arrayBuffer());
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes).replace(/^﻿/, '');
  } catch {
    return new TextDecoder('windows-1252').decode(bytes);
  }
}

/** Encabezados utilizables: sin vacíos y sin repetidos. */
function encabezados(fila: string[]): string[] {
  const vistos = new Map<string, number>();
  return fila.map((crudo, i) => {
    const base = crudo.trim() || `Columna ${i + 1}`;
    const n = (vistos.get(base) ?? 0) + 1;
    vistos.set(base, n);
    return n === 1 ? base : `${base} (${n})`;
  });
}

/**
 * Abre el archivo y lee todas sus hojas de una vez: el export por defecto
 * de read-excel-file 9 devuelve `[{ sheet, data }]` con todas (ya no hay
 * una función solo para los nombres). Así, cambiar de hoja después no
 * vuelve a descomprimir el archivo.
 */
export async function abrirArchivo(archivo: File): Promise<LibroLeido> {
  const extension = archivo.name.toLowerCase().split('.').pop();

  if (extension === 'xlsx') {
    const readXlsxFile = (await import('read-excel-file/browser')).default;
    const hojas = await readXlsxFile(archivo);
    return {
      nombre: archivo.name,
      hojas: hojas.map((h) => ({ nombre: h.sheet, tabla: h.data.map((fila) => fila.map(celdaATexto)) })),
    };
  }
  if (extension === 'csv' || extension === 'txt') {
    const Papa = (await import('papaparse')).default;
    // Excel en español separa con «;». Papa lo detecta solo.
    const resultado = Papa.parse<string[]>(await decodificar(archivo), { skipEmptyLines: 'greedy' });
    return {
      nombre: archivo.name,
      hojas: [{ nombre: null, tabla: resultado.data.map((fila) => fila.map((c) => celdaATexto(c))) }],
    };
  }
  if (extension === 'xls') {
    throw new Error('Los .xls antiguos no se pueden leer. Ábrelo en Excel y guárdalo como .xlsx o .csv.');
  }
  throw new Error('Sube un archivo .xlsx o .csv.');
}

/** La hoja que se propone al abrir: la de «Envios WhatsApp» si la hay; si no, la primera. */
export function hojaPropuesta(libro: LibroLeido): string | null {
  const nombres = libro.hojas.map((h) => h.nombre);
  return nombres.find((n) => n !== null && HOJA_DE_ENVIOS.test(n)) ?? nombres[0] ?? null;
}

/** Las columnas y las filas de una hoja. Falla si está vacía o se pasa del máximo. */
export function leerHoja(libro: LibroLeido, hoja: string | null): ArchivoLeido {
  const elegida = libro.hojas.find((h) => h.nombre === hoja) ?? libro.hojas[0];
  const tabla = elegida?.tabla ?? [];
  // Con varias hojas, el error dice cuál: la siguiente puede servir.
  const deVarias = Boolean(elegida?.nombre) && libro.hojas.length > 1;
  const cual = deVarias ? `La hoja «${elegida?.nombre}»` : 'El archivo';

  const inicio = tabla.findIndex((fila) => fila.some((c) => c !== ''));
  if (inicio === -1) throw new Error(deVarias ? `${cual} está vacía.` : 'El archivo está vacío.');

  const columnas = encabezados(tabla[inicio]);
  const filas = tabla
    .slice(inicio + 1)
    .filter((fila) => fila.some((c) => c !== ''))
    .map((fila) => Object.fromEntries(columnas.map((col, i) => [col, fila[i] ?? ''])));

  if (filas.length === 0) throw new Error(`${cual} tiene encabezados, pero ninguna fila.`);
  if (filas.length > MAX_FILAS) {
    throw new Error(
      `${cual} tiene ${filas.length.toLocaleString('es-CO')} filas; el máximo por envío es ${MAX_FILAS.toLocaleString('es-CO')}. Pártelo en varios.`
    );
  }

  return { nombre: libro.nombre, hoja: elegida?.nombre ?? null, columnas, filas };
}

/** «1250000» o «1.250.000» → «$1.250.000». Si no es un número, queda como venía. */
export function comoPesos(valor: string): string {
  const limpio = valor.replace(/[$\s]/g, '');
  const entero = /^\d{1,3}(\.\d{3})+$/.test(limpio)
    ? Number(limpio.replace(/\./g, ''))
    : /^\d+$/.test(limpio)
      ? Number(limpio)
      : null;
  return entero === null ? valor : `$${entero.toLocaleString('es-CO')}`;
}

export interface FilaResultado {
  fila: number;
  datos: Record<string, string> | null;
  resultado: string;
  motivo: string | null;
  detalle: string | null;
  enviado_at: string | null;
  entregado_at: string | null;
  leido_at: string | null;
  fallido_at: string | null;
  error: string | null;
  respondio_at: string | null;
  baja: boolean;
  /** «Pendiente», «Gestionada el … por …» o vacío si no fue a gestión manual. */
  gestion: string;
  gestion_nota: string | null;
}

/**
 * El mismo archivo, de vuelta para cartera: sus columnas, en su orden, y
 * a la derecha lo que pasó con cada fila.
 */
export async function descargarResultados(opciones: {
  nombreArchivo: string;
  columnas: string[];
  filas: FilaResultado[];
  etiquetaResultado: (r: string) => string;
  etiquetaMotivo: (m: string) => string;
}) {
  const writeXlsxFile = (await import('write-excel-file/browser')).default;

  const fecha = (iso: string | null) => (iso ? new Date(iso) : null);
  const titulo = (valor: string) => ({ value: valor, fontWeight: 'bold' as const });

  const encabezado = [
    ...opciones.columnas.map(titulo),
    titulo('Resultado WhatsApp'),
    titulo('Motivo'),
    titulo('Enviado'),
    titulo('Entregado'),
    titulo('Leído'),
    titulo('Falló'),
    titulo('Error'),
    titulo('Respondió'),
    titulo('Pidió no recibir más'),
    titulo('Gestión manual'),
    titulo('Nota de gestión'),
  ];

  const conFecha = (iso: string | null) =>
    iso ? { value: fecha(iso) as Date, type: Date, format: 'dd/mm/yyyy hh:mm' } : null;

  const filas = opciones.filas.map((f) => [
    ...opciones.columnas.map((c) => f.datos?.[c] ?? ''),
    opciones.etiquetaResultado(f.resultado),
    f.motivo ? [opciones.etiquetaMotivo(f.motivo), f.detalle].filter(Boolean).join(': ') : '',
    conFecha(f.enviado_at),
    conFecha(f.entregado_at),
    conFecha(f.leido_at),
    conFecha(f.fallido_at),
    f.error ?? '',
    f.respondio_at ? 'Sí' : 'No',
    f.baja ? 'Sí' : 'No',
    f.gestion,
    f.gestion_nota ?? '',
  ]);

  const base = opciones.nombreArchivo.replace(/\.(xlsx|csv|txt)$/i, '');
  await writeXlsxFile([encabezado, ...filas]).toFile(`${base} - resultados WhatsApp.xlsx`);
}
