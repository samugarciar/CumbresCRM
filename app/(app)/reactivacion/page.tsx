import { createClient } from '@/lib/supabase/server';
import type { PlantillaResumen } from '@/app/(app)/contactos/[id]/UsarPlantilla';
import { Bandeja, CabeceraVentana, type Reactivable } from './Bandeja';

const POR_PAGINA = 25;

export default async function PaginaReactivacion({
  searchParams,
}: {
  searchParams: Promise<{ pagina?: string }>;
}) {
  const { pagina } = await searchParams;
  const n = Math.max(1, Number.parseInt(pagina ?? '1', 10) || 1);

  const supabase = await createClient();
  const crm = supabase.schema('crm');

  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { data: perfil } = user
    ? await supabase.from('usuarios').select('nombre_completo').eq('id', user.id).single()
    : { data: null };

  const [{ data: gente, error }, { data: total }, { data: plantillas }] =
    await Promise.all([
      crm.rpc('reactivables', {
        p_dias: 14,
        p_limite: POR_PAGINA,
        p_salto: (n - 1) * POR_PAGINA,
      }),
      crm.rpc('reactivables_total', { p_dias: 14 }),
      // Marketing primero: a este público solo se le puede escribir con
      // plantilla, y «hace rato no hablamos» es marketing para Meta —
      // llamarlo utilidad es la escalera de sanción.
      crm
        .from('plantillas')
        .select('id, nombre, categoria')
        .eq('activa', true)
        .order('categoria', { ascending: false })
        .order('nombre'),
    ]);

  if (error) {
    return (
      <p className="text-sm text-destructive">
        No se pudo cargar la bandeja: {error.message}
      </p>
    );
  }

  const cuantos = total ?? 0;
  const paginas = Math.max(1, Math.ceil(cuantos / POR_PAGINA));
  const ahora = new Date().toISOString();

  return (
    <div className="mx-auto flex w-full max-w-3xl flex-col gap-5">
      <header>
        <h1 className="text-xl font-semibold tracking-tight">Reactivación</h1>
        <p className="max-w-[64ch] text-sm text-muted-foreground">
          Gente que nos escribió, nos contó algo y se quedó callada. Están
          ordenados del más callado al menos, que es al revés de lo que hace
          uno solo: al que lleva cuatro meses no le escribe nadie nunca.
        </p>
      </header>

      {cuantos > 0 && <CabeceraVentana total={cuantos} />}

      <Bandeja
        gente={(gente ?? []) as Reactivable[]}
        plantillas={(plantillas ?? []) as PlantillaResumen[]}
        asesor={perfil?.nombre_completo ?? null}
        ahora={ahora}
      />

      {paginas > 1 && (
        <nav className="flex items-center justify-between text-sm">
          <a
            href={`/reactivacion?pagina=${n - 1}`}
            className={`text-primary hover:underline ${n <= 1 ? 'pointer-events-none opacity-40' : ''}`}
          >
            ← Menos callados
          </a>
          <span className="tabular text-muted-foreground">
            {n} de {paginas}
          </span>
          <a
            href={`/reactivacion?pagina=${n + 1}`}
            className={`text-primary hover:underline ${n >= paginas ? 'pointer-events-none opacity-40' : ''}`}
          >
            Más callados →
          </a>
        </nav>
      )}
    </div>
  );
}
