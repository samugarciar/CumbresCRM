/**
 * Por qué línea de WhatsApp se le escribe a una persona.
 *
 * Hay una línea por embudo —comercial, administrativa, captación— y la
 * misma persona puede estar en dos: inquilina en administrativa y
 * compradora en comercial. Escribirle por la línea equivocada es hablarle
 * desde otro número, en otro hilo de su WhatsApp, con otra ventana de 24
 * horas. Por eso la línea la decide el embudo, y la decide esta función en
 * un solo sitio: la usan la ficha, para enseñarla, y el servidor, que la
 * vuelve a calcular antes de mandar en vez de fiarse de lo que diga el
 * navegador.
 *
 * Sin dependencias de servidor a propósito: es lógica pura.
 */

export interface LineaEnvio {
  embudo: string;
  nombre: string;
  wa_phone_number_id: string;
  telefono_e164: string | null;
  /** Desde cuándo Meta rechaza el token de esta línea. Ver la pantalla de líneas. */
  token_invalido_at: string | null;
}

export interface EleccionLinea {
  /** Por dónde se le puede escribir, la preferida primero. Vacío = no hay línea conectada. */
  opciones: LineaEnvio[];
  /**
   * true cuando la persona no tiene ninguna oportunidad abierta en un
   * embudo con línea, y se cae a la comercial (o a la única que haya).
   * La caja lo dice, para que nadie crea que se eligió por algo.
   */
  porDefecto: boolean;
}

/**
 * @param lineas Las líneas activas y conectadas de la inmobiliaria.
 * @param embudosDelContacto Los embudos donde la persona tiene una
 *   oportunidad abierta, la de actividad más reciente primero.
 * @param usaLineaDe Mapa de embudos que no tienen línea propia y usan la de otro embudo.
 */
export function elegirLinea(
  lineas: LineaEnvio[],
  embudosDelContacto: string[],
  usaLineaDe: Record<string, string> = { captacion: 'administrativa' },
): EleccionLinea {
  const vistos = new Set<string>();
  const opciones: LineaEnvio[] = [];
  for (const embudo of embudosDelContacto) {
    const embudoEfectivo = usaLineaDe[embudo] ?? embudo;
    if (vistos.has(embudoEfectivo)) continue;
    vistos.add(embudoEfectivo);
    const linea = lineas.find((l) => l.embudo === embudoEfectivo);
    if (linea) opciones.push(linea);
  }

  if (opciones.length > 0) return { opciones, porDefecto: false };

  // Sin oportunidad abierta en un embudo con línea: la comercial, que es
  // por donde entra la gente nueva. Si no hay comercial, la que haya.
  const respaldo = lineas.find((l) => l.embudo === 'comercial') ?? lineas[0];
  return respaldo
    ? { opciones: [respaldo], porDefecto: true }
    : { opciones: [], porDefecto: false };
}
