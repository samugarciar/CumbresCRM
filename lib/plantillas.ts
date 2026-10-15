/**
 * Lo que el navegador y el servidor saben de una plantilla sin preguntarle
 * a la base: qué variables usa un cuerpo y cómo enseñarlo con ejemplos.
 *
 * El relleno con datos de verdad NO vive aquí: es crm.valores_plantilla y
 * crm.rellenar_cuerpo, en la base, para que el texto que ve el asesor y
 * los parámetros que recibe Meta salgan de la misma fuente.
 */

/**
 * Un valor de muestra por variable. Sirven para dos cosas: la vista previa
 * del gestor y los ejemplos que Meta exige al revisar una plantilla con
 * variables con nombre. Tienen que parecer datos reales: un ejemplo que no
 * se entiende es un motivo habitual de rechazo.
 */
export const EJEMPLOS_VARIABLES: Record<string, string> = {
  nombre: 'María Restrepo',
  telefono: '+57 300 123 4567',
  asesor: 'Alejandro Rojas',
  inmueble: 'Apto Poblado 401',
  barrio: 'El Poblado',
  ciudad: 'Medellín',
  precio: '$2.800.000',
  habitaciones: '3',
  // De cartera: los llena el archivo de un envío masivo
  monto: '$1.250.000',
  fecha_limite: '5 de noviembre',
  dias_mora: '12',
  referencia: 'CTO-2026-0147',
};

const VARIABLE = /\{\{\s*([a-z_]+)\s*\}\}/g;

/** Las variables que usa un cuerpo, sin repetir y en el orden en que aparecen. */
export function variablesDe(cuerpo: string): string[] {
  const vistas: string[] = [];
  for (const m of cuerpo.matchAll(VARIABLE)) {
    if (!vistas.includes(m[1])) vistas.push(m[1]);
  }
  return vistas;
}

/** Los ejemplos para mandar a revisión: uno por variable, con su nombre. */
export function ejemplosPara(cuerpo: string): Record<string, string> {
  return Object.fromEntries(
    variablesDe(cuerpo).map((v) => [v, EJEMPLOS_VARIABLES[v] ?? 'Ejemplo'])
  );
}

/** El cuerpo con los ejemplos puestos, para enseñar cómo se verá. */
export function previsualizar(cuerpo: string): string {
  return cuerpo.replace(VARIABLE, (_, v: string) => EJEMPLOS_VARIABLES[v] ?? `[${v}]`);
}
