import { createClient } from '@/lib/supabase/server';
import { GestorPlantillas, type Plantilla } from './GestorPlantillas';

export default async function PaginaPlantillas() {
  const supabase = await createClient();
  const crm = supabase.schema('crm');

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const [{ data: plantillas, error }, { data: perfil }, { data: variables }] =
    await Promise.all([
      crm
        .from('plantillas')
        .select('id, nombre, cuerpo, categoria, estado_meta, nombre_meta, tipo, idioma, motivo_rechazo_meta')
        .eq('activa', true)
        .order('nombre'),
      user
        ? supabase.from('usuarios').select('rol').eq('id', user.id).single()
        : Promise.resolve({ data: null }),
      crm.rpc('variables_disponibles'),
    ]);

  if (error) {
    return (
      <div className="rounded-xl border border-destructive/30 bg-destructive/10 p-4 text-sm text-destructive">
        No se pudieron cargar las plantillas: {error.message}
      </div>
    );
  }

  return (
    <div className="mx-auto flex w-full max-w-5xl flex-col gap-5">
      <header>
        <h1 className="text-xl font-semibold tracking-tight text-foreground">Plantillas y Respuestas</h1>
        <p className="max-w-[70ch] text-sm text-muted-foreground mt-1">
          Gestiona las respuestas rápidas para el chat del día a día y las plantillas oficiales de WhatsApp
          (HSM) sincronizadas con Meta para abrir conversaciones fuera de la ventana de 24 horas.
        </p>
      </header>

      <GestorPlantillas
        plantillas={(plantillas ?? []) as Plantilla[]}
        variables={(variables ?? []) as string[]}
        puedeEditar={perfil?.rol === 'admin'}
      />
    </div>
  );
}
