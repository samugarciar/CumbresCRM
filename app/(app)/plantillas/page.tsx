import { createClient } from '@/lib/supabase/server';
import { GestorPlantillas, type LineaPlantilla, type Plantilla } from './GestorPlantillas';

export default async function PaginaPlantillas() {
  const supabase = await createClient();
  const crm = supabase.schema('crm');

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const [{ data: plantillas, error }, { data: perfil }, { data: variables }, { data: lineas }] =
    await Promise.all([
      crm
        .from('plantillas')
        .select(
          'id, nombre, cuerpo, categoria, estado_meta, nombre_meta, tipo, idioma, motivo_rechazo_meta, wa_phone_number_id'
        )
        .eq('activa', true)
        .order('nombre'),
      user
        ? supabase.from('usuarios').select('rol').eq('id', user.id).single()
        : Promise.resolve({ data: null }),
      crm.rpc('variables_disponibles'),
      // Solo las que ya están en Meta: una plantilla de WhatsApp vive en
      // la WABA de una línea conectada.
      crm
        .from('lineas')
        .select('wa_phone_number_id, nombre, embudo')
        .eq('activa', true)
        .not('wa_phone_number_id', 'is', null)
        .order('nombre'),
    ]);

  if (error) {
    return (
      <div className="rounded-xl border border-destructive/30 bg-destructive/10 p-4 text-sm text-destructive">
        No se pudieron cargar las plantillas: {error.message}
      </div>
    );
  }

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-5">
      <header>
        <h1 className="text-xl font-semibold tracking-tight text-foreground">Plantillas</h1>
        <p className="max-w-[70ch] text-sm text-muted-foreground">
          Las respuestas rápidas para el chat del día a día y las plantillas de WhatsApp de cada línea,
          que hay que hacer aprobar para escribirle a alguien pasadas 24 horas de su último mensaje.
        </p>
      </header>

      <GestorPlantillas
        plantillas={(plantillas ?? []) as Plantilla[]}
        variables={(variables ?? []) as string[]}
        lineas={(lineas ?? []) as LineaPlantilla[]}
        puedeEditar={perfil?.rol === 'admin'}
      />
    </div>
  );
}
