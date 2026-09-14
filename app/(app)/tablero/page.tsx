import { Suspense } from 'react';
import { KanbanSquare } from 'lucide-react';
import { createClient } from '@/lib/supabase/server';
import { Skeleton } from '@/components/ui/skeleton';
import { FiltrosTablero } from './FiltrosTablero';
import { Tablero, type Tarjeta, type Columna } from './Tablero';

// Cuántas tarjetas se piden por columna. "Contactado" tiene 845 en
// producción: pintarlas todas serían 845 nodos en una columna que nadie
// recorre entera. Se piden las primeras por urgencia y se dice cuántas hay.
const POR_COLUMNA = 40;

interface Busqueda {
  q?: string;
  zona?: string;
  pendiente?: string;
}

export default async function PaginaTablero({
  searchParams,
}: {
  searchParams: Promise<Busqueda>;
}) {
  const sp = await searchParams;
  const supabase = await createClient();
  const crm = supabase.schema('crm');

  const [{ data: etapas }, { data: filas, error }, { data: zonas }] =
    await Promise.all([
      crm.from('etapas').select('codigo, orden, etiqueta, dias_pudricion').order('orden'),
      crm.rpc('tablero', {
        p_limite: POR_COLUMNA,
        p_texto: sp.q || undefined,
        p_zona: sp.zona || undefined,
        p_solo_pendiente: sp.pendiente === '1' ? true : undefined,
      }),
      crm.rpc('zonas'),
    ]);

  if (error) {
    return (
      <p className="text-sm text-destructive">
        No se pudo cargar el tablero: {error.message}
      </p>
    );
  }

  const tarjetas = (filas ?? []) as Tarjeta[];

  // Se agrupa aquí y no en la base porque la base ya hizo lo caro —el
  // límite y el orden por columna—; repartir un array de 240 elementos
  // es gratis.
  const columnas: Columna[] = (etapas ?? []).map((e) => {
    const suyas = tarjetas.filter((t) => t.etapa === e.codigo);
    return {
      codigo: e.codigo,
      etiqueta: e.etiqueta,
      diasPudricion: e.dias_pudricion,
      tarjetas: suyas,
      total: Number(suyas[0]?.total_en_etapa ?? 0),
    };
  });

  const totalAbiertas = columnas.reduce((n, c) => n + c.total, 0);
  const sinAtender = tarjetas.filter((t) => t.escalado_sin_atender).length;

  return (
    <div className="flex h-full w-full flex-col gap-4">
      <header>
        <h1 className="text-xl font-semibold tracking-tight">Tablero</h1>
        <p className="text-sm text-muted-foreground">
          {totalAbiertas > 0 ? (
            <>
              <span className="tabular">{totalAbiertas.toLocaleString('es-CO')}</span>{' '}
              {totalAbiertas === 1 ? 'oportunidad abierta' : 'oportunidades abiertas'}
              {sinAtender > 0 && (
                <>
                  {' · '}
                  <span className="font-medium text-destructive">
                    {sinAtender} {sinAtender === 1 ? 'espera' : 'esperan'} a una persona
                  </span>
                </>
              )}
            </>
          ) : (
            'Una oportunidad abierta por persona'
          )}
        </p>
      </header>

      <Suspense fallback={<Skeleton className="h-9 w-full" />}>
        <FiltrosTablero zonas={zonas ?? []} />
      </Suspense>

      {totalAbiertas === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-lg border border-dashed py-16 text-center">
          <KanbanSquare className="size-8 text-muted-foreground" />
          <p className="font-medium">
            {sp.q || sp.zona || sp.pendiente
              ? 'Nada coincide con eso'
              : 'Todavía no hay oportunidades'}
          </p>
          <p className="max-w-sm text-sm text-muted-foreground">
            {sp.q || sp.zona || sp.pendiente
              ? 'Prueba quitando algún filtro.'
              : 'Se abren solas en cuanto entra el primer mensaje de una persona.'}
          </p>
        </div>
      ) : (
        <Tablero columnas={columnas} porColumna={POR_COLUMNA} />
      )}
    </div>
  );
}
