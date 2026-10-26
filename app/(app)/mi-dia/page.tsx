import { createClient } from '@/lib/supabase/server';
import { MiDia, type Renglon } from './MiDia';
import { TareaNueva } from './TareaNueva';

export default async function PaginaMiDia() {
  const supabase = await createClient();

  // El día es de quien lo mira. La función enseña lo suyo MÁS lo que no
  // tiene dueño, y esconde lo que ya lleva otro: hoy casi nada tiene
  // responsable, así que filtrar en seco dejaría la pantalla vacía.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data, error } = await supabase.schema('crm').rpc('mi_dia', {
    p_limite: 60,
    p_asesor: user?.id,
  });

  if (error) {
    return (
      <p className="text-sm text-destructive">
        No se pudo cargar el día: {error.message}
      </p>
    );
  }

  const renglones = (data ?? []) as Renglon[];

  // Se formatea en el servidor para que el primer render ya traiga la
  // fecha bien: hacerlo en el cliente parpadea y en es-CO no da igual.
  // Con la zona de Colombia explícita: el servidor corre en UTC y desde
  // las 7 p. m. ya sería mañana. Mayúscula solo en la primera letra
  // («Domingo, 25 de octubre»), no en cada palabra.
  const fecha = new Date().toLocaleDateString('es-CO', {
    timeZone: 'America/Bogota',
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
  const hoy = fecha.charAt(0).toUpperCase() + fecha.slice(1);

  return (
    <div className="mx-auto flex w-full max-w-4xl flex-col gap-6">
      <header className="flex flex-wrap items-center justify-between gap-4 pb-2 border-b">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-foreground">Mi día</h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            {hoy}
            <span className="font-medium">
              {' · '}
              {renglones.length === 0
                ? 'nada pendiente'
                : `${renglones.length} ${renglones.length === 1 ? 'asunto pendiente' : 'asuntos pendientes'}`}
            </span>
          </p>
        </div>
        <TareaNueva />
      </header>

      <MiDia renglones={renglones} />
    </div>
  );
}
