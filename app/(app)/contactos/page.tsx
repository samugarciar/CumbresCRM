import Link from 'next/link';
import { Suspense } from 'react';
import { MessageSquare, PhoneOff, Users, Phone, ArrowRight, Clock } from 'lucide-react';
import { createClient } from '@/lib/supabase/server';
import { tiempoRelativo, telefonoLegible, iniciales } from '@/lib/formato';
import { FiltrosContactos } from './FiltrosContactos';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';

const POR_PAGINA = 50;

interface Busqueda {
  q?: string;
  tipo?: string;
  sin_telefono?: string;
  cursor_at?: string;
  cursor_id?: string;
}

export default async function PaginaContactos({
  searchParams,
}: {
  searchParams: Promise<Busqueda>;
}) {
  const sp = await searchParams;
  const supabase = await createClient();
  const crm = supabase.schema('crm');

  // Toda la lógica de filtros, búsqueda y paginación vive en la base
  // (crm.bandeja_contactos), que además es SECURITY INVOKER: la RLS se
  // aplica con el token de este usuario. Aquí solo se pasan parámetros.
  const [{ data: filas, error }, { count: total }, { count: sinTelefono }] =
    await Promise.all([
      crm.rpc('bandeja_contactos', {
        p_texto: sp.q || undefined,
        p_tipo: sp.tipo || undefined,
        p_sin_telefono: sp.sin_telefono === '1' ? true : undefined,
        p_cursor_at: sp.cursor_at || undefined,
        p_cursor_id: sp.cursor_id || undefined,
        p_limite: POR_PAGINA,
      }),
      crm.from('contactos').select('*', { count: 'exact', head: true }).is('deleted_at', null),
      crm
        .from('contactos')
        .select('*', { count: 'exact', head: true })
        .is('deleted_at', null)
        .is('telefono_e164', null),
    ]);

  if (error) {
    return (
      <div className="rounded-xl border border-destructive/30 bg-destructive/10 p-4 text-sm text-destructive">
        No se pudo cargar la bandeja: {error.message}
      </div>
    );
  }

  const contactos = filas ?? [];
  const ultimo = contactos.at(-1);
  const hayMas = contactos.length === POR_PAGINA && ultimo;

  const siguiente = new URLSearchParams();
  if (sp.q) siguiente.set('q', sp.q);
  if (sp.tipo) siguiente.set('tipo', sp.tipo);
  if (sp.sin_telefono) siguiente.set('sin_telefono', sp.sin_telefono);
  if (ultimo) {
    siguiente.set('cursor_at', ultimo.orden_at ?? '');
    siguiente.set('cursor_id', ultimo.id);
  }

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-5">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold tracking-tight text-foreground">Contactos</h1>
          <p className="text-sm text-muted-foreground">
            {total !== null ? (
              <>
                <span className="font-semibold text-foreground tabular">{total.toLocaleString('es-CO')}</span>{' '}
                personas unificadas desde WhatsApp, visitas y solicitudes
              </>
            ) : (
              'Directorio central de personas'
            )}
          </p>
        </div>
      </header>

      <Suspense fallback={<Skeleton className="h-13 w-full rounded-2xl" />}>
        <FiltrosContactos sinTelefono={sinTelefono ?? 0} />
      </Suspense>

      {contactos.length === 0 ? (
        <EstadoVacio hayBusqueda={Boolean(sp.q || sp.tipo || sp.sin_telefono)} />
      ) : (
        <>
          {/* Vista Escritorio / Tablet: Tabla pulida */}
          <div className="hidden md:block overflow-hidden rounded-2xl border border-border/70 bg-card shadow-2xs">
            <Table>
              <TableHeader className="bg-muted/30">
                <TableRow className="border-border/60 hover:bg-transparent">
                  <TableHead className="w-80 py-3 font-semibold text-xs text-foreground/80">Persona</TableHead>
                  <TableHead className="py-3 font-semibold text-xs text-foreground/80">Teléfono</TableHead>
                  <TableHead className="py-3 font-semibold text-xs text-foreground/80">Tipo</TableHead>
                  <TableHead className="py-3 text-right font-semibold text-xs text-foreground/80">Mensajes</TableHead>
                  <TableHead className="py-3 text-right font-semibold text-xs text-foreground/80">Última interacción</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {contactos.map((c) => (
                  <TableRow key={c.id} className="group border-border/40 hover:bg-muted/30 transition-colors">
                    <TableCell className="py-3">
                      <Link
                        href={`/contactos/${c.id}`}
                        className="flex items-center gap-3 font-medium outline-none"
                      >
                        <span className="grid size-8 shrink-0 place-items-center rounded-full bg-primary/10 text-primary text-xs font-semibold group-hover:bg-primary group-hover:text-primary-foreground transition-colors">
                          {iniciales(c.nombre)}
                        </span>
                        <span className="truncate group-hover:text-primary group-hover:underline underline-offset-4 transition-colors">
                          {c.nombre || <span className="text-muted-foreground font-normal">Sin nombre</span>}
                        </span>
                      </Link>
                    </TableCell>

                    <TableCell className="tabular text-xs">
                      {c.telefono_e164 ? (
                        <span className="text-foreground/90 font-medium">
                          {telefonoLegible(c.telefono_e164)}
                        </span>
                      ) : (
                        <span
                          className="inline-flex items-center gap-1.5 text-muted-foreground/80"
                          title={`Lo que llegó en su lugar: ${c.telefono_crudo ?? 'nada'}`}
                        >
                          <PhoneOff className="size-3.5 opacity-60" />
                          Sin número
                        </span>
                      )}
                    </TableCell>

                    <TableCell>
                      <Badge
                        variant="secondary"
                        className="capitalize rounded-md text-[11px] font-medium border-border/40"
                      >
                        {c.tipo}
                      </Badge>
                    </TableCell>

                    <TableCell className="text-right tabular text-xs">
                      {c.sin_leer && c.sin_leer > 0 ? (
                        <span
                          className="inline-flex items-center gap-1.5 rounded-full bg-primary/10 px-2 py-0.5 font-semibold text-primary"
                          title={`${c.n_actividades} en total`}
                        >
                          <MessageSquare className="size-3" />
                          {c.sin_leer} nuevos
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 text-muted-foreground">
                          <MessageSquare className="size-3 opacity-60" />
                          {c.n_actividades}
                        </span>
                      )}
                    </TableCell>

                    <TableCell className="text-right text-xs text-muted-foreground tabular">
                      {tiempoRelativo(c.ultima_actividad_at)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>

          {/* Vista Móvil: Tarjetas ergonómicas con acción táctil */}
          <div className="flex flex-col gap-2.5 md:hidden">
            {contactos.map((c) => (
              <Link
                key={c.id}
                href={`/contactos/${c.id}`}
                className="group flex flex-col gap-2 rounded-2xl border border-border/70 bg-card p-3.5 shadow-2xs transition-all active:bg-muted/40"
              >
                <div className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-2.5 min-w-0">
                    <span className="grid size-9 shrink-0 place-items-center rounded-full bg-primary/10 text-primary text-xs font-semibold">
                      {iniciales(c.nombre)}
                    </span>
                    <div className="min-w-0">
                      <p className="truncate text-sm font-semibold tracking-tight text-foreground">
                        {c.nombre || <span className="text-muted-foreground font-normal">Sin nombre</span>}
                      </p>
                      <div className="flex items-center gap-1 text-xs text-muted-foreground">
                        <Phone className="size-3 opacity-60" />
                        <span className="tabular">
                          {c.telefono_e164 ? telefonoLegible(c.telefono_e164) : 'Sin número'}
                        </span>
                      </div>
                    </div>
                  </div>
                  <ArrowRight className="size-4 shrink-0 text-muted-foreground/50 group-hover:text-primary transition-colors" />
                </div>

                <div className="flex items-center justify-between border-t border-border/40 pt-2 text-xs">
                  <Badge variant="outline" className="capitalize text-[11px] rounded-md">
                    {c.tipo}
                  </Badge>

                  <div className="flex items-center gap-3">
                    {c.sin_leer && c.sin_leer > 0 ? (
                      <span className="inline-flex items-center gap-1 font-semibold text-primary">
                        <MessageSquare className="size-3" />
                        {c.sin_leer} nuevos
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1 text-muted-foreground">
                        <MessageSquare className="size-3 opacity-60" />
                        {c.n_actividades}
                      </span>
                    )}
                    <span className="flex items-center gap-1 text-muted-foreground tabular">
                      <Clock className="size-3 opacity-60" />
                      {tiempoRelativo(c.ultima_actividad_at)}
                    </span>
                  </div>
                </div>
              </Link>
            ))}
          </div>
        </>
      )}

      {hayMas && (
        <div className="flex justify-center pt-2 pb-6">
          <Button variant="outline" className="h-10 rounded-xl px-6 font-medium shadow-2xs" asChild>
            <Link href={`/contactos?${siguiente.toString()}`}>Cargar más contactos</Link>
          </Button>
        </div>
      )}
    </div>
  );
}

function EstadoVacio({ hayBusqueda }: { hayBusqueda: boolean }) {
  return (
    <div className="flex flex-col items-center gap-3 rounded-2xl border border-dashed border-border/80 bg-card/40 py-16 px-4 text-center">
      <div className="grid size-12 place-items-center rounded-full bg-muted">
        <Users className="size-6 text-muted-foreground" />
      </div>
      <div>
        <p className="font-semibold text-foreground">
          {hayBusqueda ? 'Nadie coincide con los criterios de búsqueda' : 'Todavía no hay contactos registrados'}
        </p>
        <p className="mx-auto mt-1 max-w-sm text-sm text-muted-foreground">
          {hayBusqueda
            ? 'Prueba ajustando los filtros o buscando por los últimos dígitos del teléfono.'
            : 'Los contactos se crearán automáticamente al recibir mensajes de WhatsApp, visitas o solicitudes.'}
        </p>
      </div>
    </div>
  );
}
