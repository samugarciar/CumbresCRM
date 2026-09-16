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
        .select('id, nombre, cuerpo, categoria, estado_meta, nombre_meta')
        .eq('activa', true)
        .order('nombre'),
      user
        ? supabase.from('usuarios').select('rol').eq('id', user.id).single()
        : Promise.resolve({ data: null }),
      crm.rpc('variables_disponibles'),
    ]);

  if (error) {
    return (
      <p className="text-sm text-destructive">
        No se pudieron cargar las plantillas: {error.message}
      </p>
    );
  }

  return (
    <div className="mx-auto flex w-full max-w-3xl flex-col gap-5">
      <header>
        <h1 className="text-xl font-semibold tracking-tight">Plantillas</h1>
        <p className="max-w-[62ch] text-sm text-muted-foreground">
          Mensajes que se rellenan solos con los datos de cada persona.
          Pasadas 24 horas desde el último mensaje del cliente, WhatsApp solo
          deja mandar plantillas aprobadas — así que para reactivar a alguien
          dormido no hay otro camino.
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
