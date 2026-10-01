import 'server-only';

import { createClient } from '@/lib/supabase/server';
import { elegirLinea, type EleccionLinea, type LineaEnvio } from '@/lib/lineas';

/**
 * Las líneas por las que se le puede escribir a este contacto.
 *
 * La llaman la ficha, para enseñar la línea en la caja de escribir, y la
 * acción de enviar, que la recalcula en el servidor en vez de fiarse del
 * embudo que mande el navegador. Lee con el token del usuario: la RLS
 * solo le deja ver las líneas y las oportunidades de su inmobiliaria.
 */
export async function lineaDeEnvio(contactoId: string): Promise<EleccionLinea> {
  const supabase = await createClient();
  const crm = supabase.schema('crm');

  const [{ data: lineas }, { data: oportunidades }] = await Promise.all([
    crm
      .from('lineas')
      .select('embudo, nombre, wa_phone_number_id, telefono_e164, token_invalido_at')
      .eq('activa', true)
      .not('wa_phone_number_id', 'is', null),
    // La de actividad más reciente primero: si la persona está en dos
    // embudos, lo más probable es que se le escriba por lo último que pasó.
    crm
      .from('oportunidades')
      .select('embudo')
      .eq('contacto_id', contactoId)
      .eq('estado', 'abierta')
      .order('updated_at', { ascending: false }),
  ]);

  return elegirLinea(
    (lineas ?? []) as LineaEnvio[],
    (oportunidades ?? []).map((o) => o.embudo),
  );
}
