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
  columnas: string[];
  filas: Record<string, string>[];
}

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

export async function leerArchivo(archivo: File): Promise<ArchivoLeido> {
  const extension = archivo.name.toLowerCase().split('.').pop();
  let tabla: string[][];

  if (extension === 'xlsx') {
    const { readSheet } = await import('read-excel-file/browser');
    const hoja = await readSheet(archivo);
    tabla = hoja.map((fila) => fila.map(celdaATexto));
  } else if (extension === 'csv' || extension === 'txt') {
    const Papa = (await import('papaparse')).default;
    // Excel en español separa con «;». Papa lo detecta solo.
    const resultado = Papa.parse<string[]>(await decodificar(archivo), { skipEmptyLines: 'greedy' });
    tabla = resultado.data.map((fila) => fila.map((c) => celdaATexto(c)));
  } else if (extension === 'xls') {
    throw new Error('Los .xls antiguos no se pueden leer. Ábrelo en Excel y guárdalo como .xlsx o .csv.');
  } else {
    throw new Error('Sube un archivo .xlsx o .csv.');
  }

  const inicio = tabla.findIndex((fila) => fila.some((c) => c !== ''));
  if (inicio === -1) throw new Error('El archivo está vacío.');

  const columnas = encabezados(tabla[inicio]);
  const filas = tabla
    .slice(inicio + 1)
    .filter((fila) => fila.some((c) => c !== ''))
    .map((fila) => Object.fromEntries(columnas.map((col, i) => [col, fila[i] ?? ''])));

  if (filas.length === 0) throw new Error('El archivo tiene encabezados, pero ninguna fila.');
  if (filas.length > MAX_FILAS) {
    throw new Error(
      `El archivo tiene ${filas.length.toLocaleString('es-CO')} filas; el máximo por envío es ${MAX_FILAS.toLocaleString('es-CO')}. Pártelo en varios.`
    );
  }

  return { nombre: archivo.name, columnas, filas };
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
  ]);

  const base = opciones.nombreArchivo.replace(/\.(xlsx|csv|txt)$/i, '');
  await writeXlsxFile([encabezado, ...filas]).toFile(`${base} - resultados WhatsApp.xlsx`);
}
