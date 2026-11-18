'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { createClient } from '@/lib/supabase/server';

export interface Resultado {
  ok: boolean;
  error?: string;
}

// Forma de uuid y nada más: z.uuid() exige la variante RFC y rechaza ids
// válidos para Postgres (los de las semillas, por ejemplo).
const uuid = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i, 'Petición inválida.');

const esquema = z.object({
  lineaId: uuid,
  activo: z.boolean(),
  simulacion: z.boolean(),
  horasSilencio: z.number().int().min(1, 'Mínimo 1 hora').max(168, 'Máximo 168 horas (7 días)'),
  maxIntentos: z.number().int().min(1).max(3),
  diasAtras: z.number().int().min(1).max(30),
  topeDiario: z.number().int().min(1, 'El tope es de al menos 1').max(1000, 'El tope máximo es 1.000'),
  plantillaId: uuid.nullable(),
  incluirEsperando: z.boolean(),
});

export type Configuracion = z.infer<typeof esquema>;

/**
 * Guardar la configuración del reciclador.
 *
 * Todas las reglas viven en crm.configurar_reciclador (solo admin, solo
 * la línea comercial, plantilla de esa línea con {{nombre}} como única
 * variable, aprobada por Meta para enviar de verdad). Aquí solo se valida
 * la forma, y se traducen los errores de la base a algo legible.
 */
export async function guardarReciclador(c: Configuracion): Promise<Resultado> {
  const v = esquema.safeParse(c);
  if (!v.success) return { ok: false, error: v.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase.schema('crm').rpc('configurar_reciclador', {
    p_linea_id: v.data.lineaId,
    p_activo: v.data.activo,
    p_simulacion: v.data.simulacion,
    p_horas_silencio: v.data.horasSilencio,
    p_max_intentos: v.data.maxIntentos,
    p_dias_atras: v.data.diasAtras,
    p_tope_diario: v.data.topeDiario,
    // La firma de la base acepta NULL («sin plantilla todavía»); el tipo
    // generado no lo dice.
    p_plantilla_id: v.data.plantillaId as string,
    p_incluir_esperando: v.data.incluirEsperando,
  });

  if (error) {
    // 42501 y 22023 traen un mensaje escrito para personas.
    if (error.code === '42501' || error.code === '22023') {
      return { ok: false, error: error.message };
    }
    console.error('[reciclador] No se pudo guardar:', error);
    return { ok: false, error: 'No se pudo guardar. Intenta de nuevo.' };
  }

  revalidatePath('/reactivacion/automatico');
  return { ok: true };
}
