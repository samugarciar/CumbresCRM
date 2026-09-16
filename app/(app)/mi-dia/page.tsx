import { createClient } from '@/lib/supabase/server';
import { MiDia, type Renglon } from './MiDia';
import { TareaNueva } from './TareaNueva';

export default async function PaginaMiDia() {
  const supabase = await createClient();
  const { data, error } = await supabase.schema('crm').rpc('mi_dia', {
    p_limite: 60,
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
  const hoy = new Date().toLocaleDateString('es-CO', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });

  return (
    <div className="mx-auto flex w-full max-w-3xl flex-col gap-5">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Mi día</h1>
          <p className="text-sm capitalize text-muted-foreground">
            {hoy}
            <span className="normal-case">
              {' · '}
              {renglones.length === 0
                ? 'nada pendiente'
                : `${renglones.length} ${renglones.length === 1 ? 'cosa' : 'cosas'}`}
            </span>
          </p>
        </div>
        <TareaNueva />
      </header>

      <MiDia renglones={renglones} />
    </div>
  );
}
