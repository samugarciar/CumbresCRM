import Link from 'next/link';
import { Suspense } from 'react';
import { ArrowLeft, Home, MessageCircle, Sparkles } from 'lucide-react';
import { createClient } from '@/lib/supabase/server';
import { tiempoRelativo, telefonoLegible, enlaceWhatsApp } from '@/lib/formato';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { FiltrosCoincidencias } from './FiltrosCoincidencias';

// Cinco por inmueble en la lista; al abrir uno, todas. Cinco caben de un
// vistazo y es lo que un asesor va a contactar hoy; las demás están a un
// clic y no estorban mientras tanto.
const POR_INMUEBLE = 5;
const AL_ABRIR = 100;

interface Fila {
  inmueble_id: string;
  titulo: string | null;
  barrio: string | null;
  ciudad: string | null;
  precio: number | null;
  habitaciones: number | null;
  tipo_inmueble: string | null;
  tipo_transaccion: string | null;
  disponible_desde: string | null;
  frescura: number;
  total_clientes: number;
  contacto_id: string;
  nombre: string | null;
  telefono_e164: string | null;
  puntaje: number;
  especificidad: number;
  pidio: string | null;
  oportunidad_id: string | null;
  etapa: string | null;
  ultima_actividad_at: string | null;
}

function pesos(n: number | null): string {
  if (n === null) return 'Sin precio';
  return '$' + n.toLocaleString('es-CO', { maximumFractionDigits: 0 });
}

export default async function PaginaCoincidencias({
  searchParams,
}: {
  searchParams: Promise<{ min?: string; inmueble?: string; historico?: string }>;
}) {
  const sp = await searchParams;
  const minimo = Number(sp.min) || 50;
  const unoSolo = sp.inmueble;
  // Por defecto solo sale gente que habló en el último mes: es lo que
  // convierte 500 nombres en una lista a la que llamar hoy. El histórico
  // se pide a propósito, para rebuscar.
  const historico = sp.historico === '1';

  const supabase = await createClient();
  const crm = supabase.schema('crm');

  const [{ data, error }, { count: disponibles }, { count: conRequerimiento }] =
    await Promise.all([
      crm.rpc('coincidencias', {
        p_minimo: minimo,
        p_por_inmueble: unoSolo ? AL_ABRIR : POR_INMUEBLE,
        p_limite: unoSolo ? 1 : 20,
        p_inmueble_id: unoSolo || undefined,
        p_frescura_max: historico ? undefined : 1,
      }),
      crm.from('v_inmuebles').select('*', { count: 'exact', head: true }).eq('estado', 'disponible'),
      crm.from('requerimientos').select('*', { count: 'exact', head: true }).eq('activo', true),
    ]);

  if (error) {
    return (
      <p className="text-sm text-destructive">
        No se pudieron cargar las coincidencias: {error.message}
      </p>
    );
  }

  const filas = (data ?? []) as Fila[];

  // Se agrupa aquí porque la base ya hizo lo caro —el cruce y el recorte
  // por inmueble—; repartir un array de 100 elementos es gratis.
  const porInmueble = new Map<string, { info: Fila; clientes: Fila[] }>();
  for (const f of filas) {
    const g = porInmueble.get(f.inmueble_id);
    if (g) g.clientes.push(f);
    else porInmueble.set(f.inmueble_id, { info: f, clientes: [f] });
  }
  const grupos = [...porInmueble.values()];

  return (
    <div className="mx-auto flex w-full max-w-4xl flex-col gap-5">
      <header className="flex flex-col gap-1">
        {unoSolo && (
          <Button variant="ghost" size="sm" asChild className="-ml-2 w-fit">
            <Link href="/coincidencias">
              <ArrowLeft className="size-4" />
              Todas las coincidencias
            </Link>
          </Button>
        )}
        <h1 className="text-xl font-semibold tracking-tight">Coincidencias</h1>
        <p className="text-sm text-muted-foreground">
          Lo que entró al catálogo, y quién lo había pedido.{' '}
          <span className="tabular">{disponibles ?? 0}</span> inmuebles disponibles ·{' '}
          <span className="tabular">{conRequerimiento ?? 0}</span> personas dijeron qué
          buscan
        </p>
      </header>

      <Suspense fallback={<Skeleton className="h-9 w-full" />}>
        <FiltrosCoincidencias minimo={minimo} historico={historico} />
      </Suspense>

      {grupos.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-lg border border-dashed py-16 text-center">
          <Sparkles className="size-8 text-muted-foreground" />
          <p className="font-medium">Ningún inmueble encaja con nadie ahora mismo</p>
          <p className="max-w-md text-sm text-muted-foreground">
            {historico
              ? 'Ni rebuscando en el histórico. Baja la exigencia del cruce.'
              : 'Nadie que haya hablado en el último mes encaja con lo que hay. Prueba a rebuscar en el histórico.'}
          </p>
        </div>
      ) : (
        <div className="flex flex-col gap-4">
          {grupos.map(({ info, clientes }) => (
            <section key={info.inmueble_id} className="overflow-hidden rounded-lg border bg-card">
              <header className="flex flex-wrap items-start justify-between gap-3 border-b px-4 py-3">
                <div className="min-w-0">
                  <h2 className="truncate font-medium">{info.titulo ?? 'Sin título'}</h2>
                  <p className="flex flex-wrap items-center gap-x-2 text-sm text-muted-foreground">
                    <span>
                      {[info.barrio, info.ciudad].filter(Boolean).join(' · ') || 'Sin zona'}
                    </span>
                    <span aria-hidden>·</span>
                    <span className="tabular">{pesos(info.precio)}</span>
                    {info.habitaciones !== null && (
                      <>
                        <span aria-hidden>·</span>
                        <span>{info.habitaciones} hab</span>
                      </>
                    )}
                    <span aria-hidden>·</span>
                    <span className="capitalize">{info.tipo_transaccion}</span>
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-sm font-medium">
                    {info.total_clientes}{' '}
                    {Number(info.total_clientes) === 1 ? 'persona' : 'personas'}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    disponible {tiempoRelativo(info.disponible_desde)}
                  </p>
                </div>
              </header>

              <ul className="divide-y">
                {clientes.map((c) => {
                  const wa = enlaceWhatsApp(c.telefono_e164);
                  return (
                    <li
                      key={c.contacto_id}
                      className="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-2.5"
                    >
                      {/* El puntaje va primero porque es lo que ordena la
                          lista, y así el ojo baja por una columna de
                          números en vez de buscarlo en cada fila. */}
                      <span
                        className="tabular w-9 shrink-0 text-sm font-semibold"
                        title={`Cumple el ${c.puntaje}% de las ${c.especificidad} cosas que pidió`}
                      >
                        {c.puntaje}
                      </span>

                      <Link
                        href={`/contactos/${c.contacto_id}`}
                        className="min-w-0 flex-1 hover:underline"
                      >
                        <span className="block truncate text-sm font-medium">
                          {c.nombre || 'Sin nombre'}
                        </span>
                        <span className="block truncate text-xs text-muted-foreground">
                          {c.pidio || 'Sin detalle'}
                        </span>
                      </Link>

                      {/* Sin oportunidad abierta = reactivación: dijo qué
                          quería, no se lo pudimos dar, y hoy sí. Va en
                          gris porque es contexto, no alarma. */}
                      <span className="shrink-0 text-xs text-muted-foreground">
                        {c.etapa ? (
                          <span className="capitalize">{c.etapa.replace(/_/g, ' ')}</span>
                        ) : (
                          'reactivación'
                        )}
                        {c.frescura >= 2 && ' · frío'}
                      </span>

                      {wa ? (
                        <Button size="xs" variant="outline" asChild>
                          <a href={wa} target="_blank" rel="noopener noreferrer">
                            <MessageCircle className="size-3" />
                            WhatsApp
                          </a>
                        </Button>
                      ) : (
                        <span className="text-xs text-muted-foreground">Sin número</span>
                      )}
                    </li>
                  );
                })}
              </ul>

              {!unoSolo && Number(info.total_clientes) > clientes.length && (
                <div className="border-t px-4 py-2">
                  <Link
                    href={`/coincidencias?inmueble=${info.inmueble_id}&min=${minimo}`}
                    className="text-xs text-primary hover:underline"
                  >
                    Ver las {Number(info.total_clientes) - clientes.length} restantes
                  </Link>
                </div>
              )}
            </section>
          ))}
        </div>
      )}

      {grupos.length > 0 && !unoSolo && (
        <p className="flex items-center justify-center gap-1.5 pb-4 text-xs text-muted-foreground">
          <Home className="size-3.5" />
          Solo salen los inmuebles que tienen a alguien esperándolos.
        </p>
      )}
    </div>
  );
}
