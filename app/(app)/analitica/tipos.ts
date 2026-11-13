// La forma del jsonb que devuelve crm.analitica(periodo, embudo). Las
// definiciones de cada número están en la migración 20261113100001.

export type Periodo = 'hoy' | '7d' | '30d' | 'mes';

export const PERIODOS: { id: Periodo; etiqueta: string; contra: string }[] = [
  { id: 'hoy', etiqueta: 'Hoy', contra: 'ayer a esta hora' },
  { id: '7d', etiqueta: 'Última semana', contra: 'los 7 días anteriores' },
  { id: '30d', etiqueta: 'Últimos 30 días', contra: 'los 30 días anteriores' },
  { id: 'mes', etiqueta: 'Último mes', contra: 'el mes anterior' },
];

export const EMBUDOS = [
  { id: 'comercial', etiqueta: 'Comercial' },
  { id: 'captacion', etiqueta: 'Captación' },
  { id: 'administrativa', etiqueta: 'Administrativa' },
] as const;

export interface Kpis {
  leads_nuevos: number;
  conversaciones: number;
  atendidas: number;
  atendidas_humano: number;
  mediana_respuesta_min: number | null;
  mediana_respuesta_humana_min: number | null;
  citas_agendadas: number;
  citas_por_bot: number;
  avanzaron: number;
  avances: number;
  ganadas: number;
  perdidas: number;
}

export interface EtapaEmbudo {
  codigo: string;
  etiqueta: string;
  orden: number;
  alcanzaron: number;
}

export interface EtapaPerdidas {
  codigo: string;
  etiqueta: string;
  orden: number;
  perdidas: number;
}

export interface EtapaEstancada {
  codigo: string;
  etiqueta: string;
  orden: number;
  dias_pudricion: number | null;
  abiertas: number;
  estancadas: number;
}

export interface PuntoSerie {
  inicio: string; // hora local de Bogotá, 'YYYY-MM-DDTHH:MM'
  leads: number;
  conversaciones: number;
  mensajes_bot: number;
  mensajes_humano: number;
  citas: number;
}

export interface FilaAsesor {
  usuario_id: string;
  nombre: string;
  mensajes: number;
  contactos: number;
  notas_llamadas: number;
  avances: number;
  ganadas: number;
  perdidas: number;
}

export interface Flujo {
  desde: string;
  hasta: string;
  avance: boolean;
  cantidad: number;
  por_equipo: number;
}

export interface Analitica {
  periodo: { codigo: Periodo; desde: string; hasta: string; unidad: 'hour' | 'day' };
  embudo_codigo: string;
  kpis: { actual: Kpis; anterior: Kpis };
  embudo: EtapaEmbudo[];
  cohorte: { total: number; abiertas: number; ganadas: number; perdidas: number };
  perdidas_por_etapa: EtapaPerdidas[];
  perdidas_por_motivo: { motivo: string; cantidad: number }[];
  reclasificadas: { motivo: string; cantidad: number }[];
  estancadas: EtapaEstancada[];
  serie: PuntoSerie[];
  asesores: FilaAsesor[];
  flujos: Flujo[];
  mensajes: {
    entrantes: number;
    salientes_bot: number;
    salientes_humano: number;
    salientes_sistema: number;
  };
  visitas: {
    programadas: number;
    realizadas: number;
    canceladas: number;
    pendientes: number;
    sin_confirmar: number;
  };
}

export const MOTIVOS: Record<string, string> = {
  precio: 'Precio',
  zona: 'Zona',
  disponibilidad: 'Disponibilidad',
  requisitos: 'Requisitos',
  no_responde: 'No responde',
  arrendo_con_otro: 'Arrendó con otro',
  duplicado: 'Duplicado',
  otro: 'Otro',
  es_captacion: 'Pasó a captación',
  es_administrativa: 'Pasó a administrativa',
};

export function porcentaje(parte: number, total: number): number | null {
  if (!total) return null;
  return Math.round((parte / total) * 100);
}

/** 12 min · 1 h 20 min · 2 d 3 h */
export function duracion(minutos: number | null): string {
  if (minutos === null || minutos === undefined) return '—';
  if (minutos < 1) return 'menos de 1 min';
  if (minutos < 60) return `${Math.round(minutos)} min`;
  if (minutos < 60 * 24) {
    const h = Math.floor(minutos / 60);
    const m = Math.round(minutos % 60);
    return m ? `${h} h ${m} min` : `${h} h`;
  }
  const d = Math.floor(minutos / 1440);
  const h = Math.round((minutos % 1440) / 60);
  return h ? `${d} d ${h} h` : `${d} d`;
}

export const numero = (n: number) => n.toLocaleString('es-CO');
