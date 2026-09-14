import Link from 'next/link';
import { Suspense } from 'react';
import { MessageSquare, PhoneOff, Users } from 'lucide-react';
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
      <p className="text-sm text-destructive">
        No se pudo cargar la bandeja: {error.message}
      </p>
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
          <h1 className="text-2xl font-semibold tracking-tight">Contactos</h1>
          <p className="text-sm text-muted-foreground">
            {total !== null ? (
              <>
                <span className="tabular">{total.toLocaleString('es-CO')}</span>{' '}
                personas, unificadas desde WhatsApp, visitas y solicitudes
              </>
            ) : (
              'La memoria de la empresa'
            )}
          </p>
        </div>
      </header>

      <Suspense fallback={<Skeleton className="h-9 w-full" />}>
        <FiltrosContactos sinTelefono={sinTelefono ?? 0} />
      </Suspense>

      {contactos.length === 0 ? (
        <EstadoVacio hayBusqueda={Boolean(sp.q || sp.tipo || sp.sin_telefono)} />
      ) : (
        <div className="overflow-hidden rounded-lg border bg-card">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Nombre</TableHead>
                <TableHead>Teléfono</TableHead>
                <TableHead>Tipo</TableHead>
                <TableHead className="text-right">Actividad</TableHead>
                <TableHead className="text-right">Último contacto</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {contactos.map((c) => (
                <TableRow key={c.id} className="group">
                  <TableCell>
                    <Link
                      href={`/contactos/${c.id}`}
                      className="flex items-center gap-3 font-medium hover:text-primary"
                    >
                      <span className="grid size-8 shrink-0 place-items-center rounded-full bg-accent text-xs font-semibold text-accent-foreground">
                        {iniciales(c.nombre)}
                      </span>
                      <span className="truncate">
                        {c.nombre || <span className="text-muted-foreground">Sin nombre</span>}
                      </span>
                    </Link>
                  </TableCell>

                  <TableCell className="tabular">
                    {c.telefono_e164 ? (
                      telefonoLegible(c.telefono_e164)
                    ) : (
                      <span
                        className="inline-flex items-center gap-1.5 text-muted-foreground"
                        title={`Lo que llegó en su lugar: ${c.telefono_crudo ?? 'nada'}`}
                      >
                        <PhoneOff className="size-3.5" />
                        Sin número
                      </span>
                    )}
                  </TableCell>

                  <TableCell>
                    <Badge variant="secondary" className="capitalize">
                      {c.tipo}
                    </Badge>
                  </TableCell>

                  <TableCell className="text-right tabular">
                    {c.sin_leer && c.sin_leer > 0 ? (
                      // Lo no leído desplaza al total: si hay algo nuevo,
                      // el total deja de ser la pregunta interesante.
                      <span
                        className="inline-flex items-center gap-1.5 font-medium text-primary"
                        title={`${c.n_actividades} en total`}
                      >
                        <MessageSquare className="size-3.5" />
                        {c.sin_leer} nuevos
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1.5 text-muted-foreground">
                        <MessageSquare className="size-3.5" />
                        {c.n_actividades}
                      </span>
                    )}
                  </TableCell>

                  <TableCell className="text-right text-muted-foreground">
                    {tiempoRelativo(c.ultima_actividad_at)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      {hayMas && (
        <div className="flex justify-center">
          {/* Paginación por cursor: la siguiente página arranca donde
              terminó esta, así que no se vuelve lenta ni se salta filas
              cuando alguien escribe mientras navegas. */}
          <Button variant="outline" asChild>
            <Link href={`/contactos?${siguiente.toString()}`}>Ver más</Link>
          </Button>
        </div>
      )}
    </div>
  );
}

function EstadoVacio({ hayBusqueda }: { hayBusqueda: boolean }) {
  return (
    <div className="flex flex-col items-center gap-2 rounded-lg border border-dashed py-16 text-center">
      <Users className="size-8 text-muted-foreground" />
      <p className="font-medium">
        {hayBusqueda ? 'Nadie coincide con eso' : 'Todavía no hay contactos'}
      </p>
      <p className="max-w-sm text-sm text-muted-foreground">
        {hayBusqueda
          ? 'Prueba con menos filtros, o con parte del teléfono en vez del nombre.'
          : 'Los contactos aparecen solos a medida que entran mensajes de WhatsApp, visitas y solicitudes de horario.'}
      </p>
    </div>
  );
}
