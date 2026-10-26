/**
 * Cómo se cuenta el estado del bot de una persona: el chip de la cabecera
 * de la ficha y el texto del panel «El bot».
 *
 * Vive en un módulo sin 'use client' a propósito: lo usan la página (en el
 * servidor) y ControlBot (en el navegador), y tienen que decir lo mismo.
 *
 * Las horas van SIEMPRE en hora de Colombia, con la zona puesta a mano: el
 * servidor corre en UTC y el celular del asesor puede estar en cualquier
 * parte. «Vuelve a las 5:38 a. m.» dicho en UTC es una mentira de 5 horas.
 */

const ZONA = 'America/Bogota';

const HORA = new Intl.DateTimeFormat('es-CO', {
  hour: 'numeric',
  minute: '2-digit',
  hour12: true,
  timeZone: ZONA,
});

const DIA = new Intl.DateTimeFormat('es-CO', {
  day: 'numeric',
  month: 'short',
  timeZone: ZONA,
});

/** AAAA-MM-DD del día en Colombia, para comparar días sin líos de zona. */
const CLAVE_DIA = new Intl.DateTimeFormat('en-CA', {
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  timeZone: ZONA,
});

/** «11:38 p. m.», sin el punto final que a veces trae Intl («p. m..»). */
export function horaColombia(fecha: string | Date): string {
  return HORA.format(new Date(fecha)).replace(/\s+/g, ' ').trim();
}

function diasEntre(desde: string | Date, hasta: string | Date): number {
  const a = Date.parse(CLAVE_DIA.format(new Date(desde)));
  const b = Date.parse(CLAVE_DIA.format(new Date(hasta)));
  return Math.round((b - a) / 86_400_000);
}

/**
 * La hora con el día cuando hace falta, mirado desde `ahora`:
 * «a las 11:38 p. m.», «mañana a las 6:00 a. m.», «ayer a las 9:10 p. m.»
 * o «el 24 oct. a las 10:21 p. m.».
 */
export function cuandoColombia(fecha: string | Date, ahora: string | Date): string {
  const hora = horaColombia(fecha);
  const dias = diasEntre(ahora, fecha);
  // A las 11:38 p. m., «vuelve a las 12:38 a. m.» no se presta a dudas:
  // el día solo se dice cuando faltan o pasaron más de 12 horas.
  const horas = Math.abs(new Date(fecha).getTime() - new Date(ahora).getTime()) / 3_600_000;
  // «a la 1:39», no «a las 1:39».
  const alas = /^1:/.test(hora) ? 'a la' : 'a las';
  if (dias === 0 || horas < 12) return `${alas} ${hora}`;
  if (dias === 1) return `mañana ${alas} ${hora}`;
  if (dias === -1) return `ayer ${alas} ${hora}`;
  return `el ${DIA.format(new Date(fecha))} ${alas} ${hora}`;
}

/** Cierra la frase con punto, sin duplicar el de «p. m.». */
function conPunto(frase: string): string {
  return frase.endsWith('.') ? frase : `${frase}.`;
}

/** «en 45 min», «en 1 h», «en 5 h». */
export function faltaPara(fecha: string | Date, ahora: string | Date): string {
  const min = Math.round((new Date(fecha).getTime() - new Date(ahora).getTime()) / 60_000);
  if (min <= 1) return 'en un momento';
  if (min < 60) return `en ${min} min`;
  return `en ${Math.round(min / 60)} h`;
}

export interface EstadoBotEntrada {
  activo: boolean;
  motivo: string | null;
  cambiadoAt: string | null;
  /** Cuándo vuelve solo, si vuelve. Puede llegar con cualquier motivo. */
  vuelveAt: string | null;
  ahora: string;
}

export interface EstadoBot {
  /** Para el chip de la cabecera. Nulo cuando el bot está respondiendo. */
  chip: string | null;
  /** Por qué está callado y desde cuándo, en una frase. */
  porQue: string | null;
  /** Cuándo vuelve, en una frase. Nulo si no vuelve solo. */
  vuelve: string | null;
}

export function describirBot({ activo, motivo, cambiadoAt, vuelveAt, ahora }: EstadoBotEntrada): EstadoBot {
  if (activo) return { chip: null, porQue: null, vuelve: null };

  const desde = cambiadoAt ? ` ${cuandoColombia(cambiadoAt, ahora)}` : '';

  // La vuelta corre cada pocos minutos: pasada la hora, «vuelve a las
  // 11:38» ya sería mentira, y lo honesto es «en unos minutos».
  const yaToca = vuelveAt !== null && new Date(vuelveAt).getTime() <= new Date(ahora).getTime();

  let vuelve: string | null = null;
  let chipVuelve: string | null = null;
  if (vuelveAt) {
    if (yaToca) {
      vuelve = 'Vuelve a responder en unos minutos.';
      chipVuelve = 'vuelve en unos minutos';
    } else {
      const cuando = cuandoColombia(vuelveAt, ahora);
      const condicion = motivo === 'relevo' ? ' si nadie más le escribe' : '';
      vuelve = `Vuelve a responder solo ${cuando} (${faltaPara(vuelveAt, ahora)})${condicion}.`;
      chipVuelve = `vuelve ${cuando.replace(/^a las? /, '').replace(/ a las? /, ' ')}`;
    }
  }

  if (motivo === 'relevo') {
    return {
      chip: `Bot callado · ${chipVuelve ?? 'le escribió el equipo'}`,
      porQue: conPunto(`Le escribió alguien del equipo${desde}`),
      vuelve,
    };
  }

  if (motivo === 'escalamiento') {
    return {
      chip: `Bot callado · ${chipVuelve ?? 'pidió una persona'}`,
      porQue: conPunto(`Esta persona pidió hablar con alguien del equipo${desde}`),
      vuelve,
    };
  }

  return {
    chip: vuelveAt ? `Bot callado · ${chipVuelve}` : 'Bot apagado a mano',
    porQue: conPunto(`Alguien del equipo lo apagó${desde}`),
    vuelve: vuelve ?? 'No vuelve solo: enciéndelo cuando quieras que le responda.',
  };
}
