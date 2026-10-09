import Link from 'next/link';
import { Suspense } from 'react';
import { MessageSquare, PhoneOff, Phone, ArrowRight, Clock, Check, Inbox } from 'lucide-react';
import { createClient } from '@/lib/supabase/server';
import { tiempoRelativo, telefonoLegible, iniciales } from '@/lib/formato';
import { FiltrosContactos, type ConteosBandeja } from './FiltrosContactos';
import { BotonMarcarAtendido } from './BotonMarcarAtendido';
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
  esperando?: string;
  canal?: string;
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

  const canalActual = sp.canal || 'comercial';
  const canalParam = canalActual === 'todos' ? undefined : canalActual;

  // Toda la lógica de filtros, búsqueda y paginación vive en la base
  // (crm.bandeja_contactos y crm.conteo_bandeja), que además son SECURITY INVOKER:
  // la RLS se aplica con el token de este usuario.
  const [
    { data: filas, error },
    { data: conteosFilas },
    { count: sinTelefono },
  ] = await Promise.all([
    crm.rpc('bandeja_contactos', {
      p_texto: sp.q || undefined,
      p_tipo: sp.tipo || undefined,
      p_sin_telefono: sp.sin_telefono === '1' ? true : undefined,
      p_cursor_at: sp.cursor_at || undefined,
      p_cursor_id: sp.cursor_id || undefined,
      p_limite: POR_PAGINA,
      p_solo_esperando: sp.esperando === '1' ? true : undefined,
      p_canal: canalParam,
    }),
    crm.rpc('conteo_bandeja'),
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

  const conteos: ConteosBandeja = {
    total: Number(conteosFilas?.[0]?.total ?? 0),
    total_esperando: Number(conteosFilas?.[0]?.total_esperando ?? 0),
    comercial_total: Number(conteosFilas?.[0]?.comercial_total ?? 0),
    comercial_esperando: Number(conteosFilas?.[0]?.comercial_esperando ?? 0),
    admin_captacion_total: Number(conteosFilas?.[0]?.admin_captacion_total ?? 0),
    admin_captacion_esperando: Number(conteosFilas?.[0]?.admin_captacion_esperando ?? 0),
    admin_total: Number(conteosFilas?.[0]?.admin_total ?? 0),
    admin_esperando: Number(conteosFilas?.[0]?.admin_esperando ?? 0),
    captacion_total: Number(conteosFilas?.[0]?.captacion_total ?? 0),
    captacion_esperando: Number(conteosFilas?.[0]?.captacion_esperando ?? 0),
  };

  const contactos = filas ?? [];
  const ultimo = contactos.at(-1);
  const hayMas = contactos.length === POR_PAGINA && ultimo;

  const siguiente = new URLSearchParams();
  if (sp.canal) siguiente.set('canal', sp.canal);
  if (sp.q) siguiente.set('q', sp.q);
  if (sp.tipo) siguiente.set('tipo', sp.tipo);
  if (sp.sin_telefono) siguiente.set('sin_telefono', sp.sin_telefono);
  if (sp.esperando) siguiente.set('esperando', sp.esperando);
  if (ultimo) {
    siguiente.set('cursor_at', ultimo.orden_at ?? '');
    siguiente.set('cursor_id', ultimo.id);
  }

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-5">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <div className="flex items-center gap-2">
            <Inbox className="size-6 text-primary" />
            <h1 className="text-xl font-semibold tracking-tight text-foreground">
              Bandeja de entrada
            </h1>
          </div>
          <p className="text-sm text-muted-foreground mt-0.5">
            {canalActual === 'comercial' ? (
              <>
                <span className="font-semibold text-foreground tabular">{conteos.comercial_total.toLocaleString('es-CO')}</span>{' '}
                conversaciones comerciales (Línea 324) ·{' '}
                <span className="tabular font-medium text-amber-700 dark:text-amber-400">
                  {conteos.comercial_esperando} esperando respuesta
                </span>
              </>
            ) : canalActual === 'administrativa' ? (
              <>
                <span className="font-semibold text-foreground tabular">{conteos.admin_total.toLocaleString('es-CO')}</span>{' '}
                casos administrativos (Línea 320) ·{' '}
                <span className="tabular font-medium text-amber-700 dark:text-amber-400">
                  {conteos.admin_esperando} esperando respuesta
                </span>
              </>
            ) : canalActual === 'captacion' ? (
              <>
                <span className="font-semibold text-foreground tabular">{conteos.captacion_total.toLocaleString('es-CO')}</span>{' '}
                prospectos de captación (Línea 320) ·{' '}
                <span className="tabular font-medium text-amber-700 dark:text-amber-400">
                  {conteos.captacion_esperando} esperando respuesta
                </span>
              </>
            ) : canalActual === 'administrativa_captacion' ? (
              <>
                <span className="font-semibold text-foreground tabular">{conteos.admin_captacion_total.toLocaleString('es-CO')}</span>{' '}
                casos administrativos y de captación (Línea 320) ·{' '}
                <span className="tabular font-medium text-amber-700 dark:text-amber-400">
                  {conteos.admin_captacion_esperando} esperando respuesta
                </span>
              </>
            ) : (
              <>
                <span className="font-semibold text-foreground tabular">{conteos.total.toLocaleString('es-CO')}</span>{' '}
                conversaciones en total ·{' '}
                <span className="tabular font-medium text-amber-700 dark:text-amber-400">
                  {conteos.total_esperando} esperando respuesta
                </span>
              </>
            )}
          </p>
        </div>
      </header>

      <Suspense fallback={<Skeleton className="h-28 w-full rounded-2xl" />}>
        <FiltrosContactos
          sinTelefono={sinTelefono ?? 0}
          canalActual={canalActual}
          conteos={conteos}
        />
      </Suspense>

      {contactos.length === 0 ? (
        <EstadoVacio
          hayBusqueda={Boolean(sp.q || sp.tipo || sp.sin_telefono || sp.esperando)}
          canal={canalActual}
        />
      ) : (
        <>
          {/* Vista Escritorio / Tablet: Tabla Inbox */}
          <div className="hidden md:block overflow-hidden rounded-2xl border border-border/70 bg-card shadow-2xs">
            <Table>
              <TableHeader className="bg-muted/30">
                <TableRow className="border-border/60 hover:bg-transparent">
                  <TableHead className="w-[38%] py-3 font-semibold text-xs text-foreground/80">Contacto y último mensaje</TableHead>
                  <TableHead className="py-3 font-semibold text-xs text-foreground/80">Teléfono</TableHead>
                  <TableHead className="py-3 font-semibold text-xs text-foreground/80">Canal / Línea</TableHead>
                  <TableHead className="py-3 font-semibold text-xs text-foreground/80">Turno</TableHead>
                  <TableHead className="py-3 text-right font-semibold text-xs text-foreground/80">Estado / Acción</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {contactos.map((c) => (
                  <TableRow key={c.id} className="group border-border/40 hover:bg-muted/30 transition-colors">
                    <TableCell className="py-3">
                      <Link
                        href={`/contactos/${c.id}`}
                        className="flex items-start gap-3 outline-none"
                      >
                        <div className="relative mt-0.5">
                          <span className="grid size-9 shrink-0 place-items-center rounded-full bg-primary/10 text-primary text-xs font-semibold group-hover:bg-primary group-hover:text-primary-foreground transition-colors">
                            {iniciales(c.nombre)}
                          </span>
                          {c.esperando_respuesta && (
                            <span className="absolute -top-0.5 -right-0.5 size-2.5 rounded-full bg-amber-500 ring-2 ring-background animate-pulse" />
                          )}
                        </div>
                        <div className="min-w-0 flex-1">
                          <p className="truncate font-semibold text-sm group-hover:text-primary group-hover:underline underline-offset-4 transition-colors">
                            {c.nombre || <span className="text-muted-foreground font-normal">Sin nombre</span>}
                          </p>
                          {c.ultimo_mensaje ? (
                            <p className="line-clamp-1 text-xs text-muted-foreground mt-0.5">
                              <span className="font-semibold text-foreground/75">
                                {c.ultimo_mensaje_tipo === 'mensaje_entrante'
                                  ? 'Cliente: '
                                  : c.ultimo_mensaje_tipo === 'nota'
                                  ? 'Nota: '
                                  : 'Tú: '}
                              </span>
                              {c.ultimo_mensaje}
                            </p>
                          ) : (
                            <p className="text-[11px] text-muted-foreground/60 italic mt-0.5">
                              Sin mensajes registrados
                            </p>
                          )}
                        </div>
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
                      <div className="flex flex-col gap-1 items-start">
                        {c.canal === 'comercial' ? (
                          <Badge variant="outline" className="bg-sky-500/10 text-sky-700 dark:text-sky-300 border-sky-500/30 text-[10px] font-semibold py-0.5">
                            Línea 324 · Comercial
                          </Badge>
                        ) : c.canal === 'captacion' ? (
                          <Badge variant="outline" className="bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border-emerald-500/30 text-[10px] font-semibold py-0.5">
                            Línea 320 · Captación
                          </Badge>
                        ) : (
                          <Badge variant="outline" className="bg-purple-500/10 text-purple-700 dark:text-purple-300 border-purple-500/30 text-[10px] font-semibold py-0.5">
                            Línea 320 · Admin
                          </Badge>
                        )}
                        <span className="text-[11px] text-muted-foreground capitalize">
                          {c.tipo}
                        </span>
                      </div>
                    </TableCell>

                    <TableCell>
                      {c.esperando_respuesta ? (
                        <span className="inline-flex items-center gap-1.5 rounded-full bg-amber-500/15 border border-amber-500/30 px-2.5 py-0.5 text-[11px] font-semibold text-amber-700 dark:text-amber-300">
                          <Clock className="size-3 text-amber-600 animate-pulse" />
                          Esperando respuesta
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 text-[11px] font-medium text-muted-foreground/80">
                          <Check className="size-3 text-emerald-500" />
                          Al día
                        </span>
                      )}
                    </TableCell>

                    <TableCell className="text-right">
                      <div className="flex items-center justify-end gap-2">
                        {c.esperando_respuesta && (
                          <BotonMarcarAtendido contactoId={c.id} variante="compacto" />
                        )}

                        {c.sin_leer && c.sin_leer > 0 ? (
                          <span
                            className="inline-flex items-center gap-1 rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary"
                            title={`${c.n_actividades} mensajes en total`}
                          >
                            <MessageSquare className="size-3" />
                            {c.sin_leer} nuevos
                          </span>
                        ) : null}

                        <span className="text-xs text-muted-foreground tabular whitespace-nowrap">
                          {tiempoRelativo(c.ultima_actividad_at)}
                        </span>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>

          {/* Vista Móvil: Tarjetas de conversación */}
          <div className="flex flex-col gap-2.5 md:hidden">
            {contactos.map((c) => (
              <div
                key={c.id}
                className="group flex flex-col gap-2.5 rounded-2xl border border-border/70 bg-card p-3.5 shadow-2xs transition-all"
              >
                <Link href={`/contactos/${c.id}`} className="block">
                  <div className="flex items-start justify-between gap-3">
                    <div className="flex items-center gap-2.5 min-w-0">
                      <span className="relative grid size-10 shrink-0 place-items-center rounded-full bg-primary/10 text-primary text-xs font-semibold">
                        {iniciales(c.nombre)}
                        {c.esperando_respuesta && (
                          <span className="absolute top-0 right-0 size-2.5 rounded-full bg-amber-500 ring-2 ring-background" />
                        )}
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
                    <ArrowRight className="size-4 shrink-0 text-muted-foreground/50 group-hover:text-primary transition-colors mt-1" />
                  </div>

                  <div className="flex flex-wrap items-center gap-1.5 mt-2">
                    {c.canal === 'comercial' ? (
                      <Badge variant="outline" className="bg-sky-500/10 text-sky-700 dark:text-sky-300 border-sky-500/30 text-[10px] font-semibold py-0">
                        Línea 324 · Comercial
                      </Badge>
                    ) : c.canal === 'captacion' ? (
                      <Badge variant="outline" className="bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border-emerald-500/30 text-[10px] font-semibold py-0">
                        Línea 320 · Captación
                      </Badge>
                    ) : (
                      <Badge variant="outline" className="bg-purple-500/10 text-purple-700 dark:text-purple-300 border-purple-500/30 text-[10px] font-semibold py-0">
                        Línea 320 · Admin
                      </Badge>
                    )}
                    <span className="text-[11px] text-muted-foreground capitalize">
                      · {c.tipo}
                    </span>
                  </div>

                  {c.ultimo_mensaje && (
                    <div className="mt-2 rounded-xl bg-muted/40 p-2 text-xs text-muted-foreground">
                      <p className="line-clamp-2 italic">
                        <span className="font-semibold text-foreground/75 not-italic">
                          {c.ultimo_mensaje_tipo === 'mensaje_entrante' ? 'Cliente: ' : 'Tú: '}
                        </span>
                        {c.ultimo_mensaje}
                      </p>
                    </div>
                  )}
                </Link>

                <div className="flex items-center justify-between border-t border-border/40 pt-2 text-xs">
                  <div className="flex items-center gap-2">
                    {c.esperando_respuesta ? (
                      <span className="text-[11px] font-semibold text-amber-600 dark:text-amber-400 flex items-center gap-1">
                        <Clock className="size-3" /> Esperando
                      </span>
                    ) : (
                      <span className="text-[11px] text-muted-foreground flex items-center gap-1">
                        <Check className="size-3 text-emerald-500" /> Al día
                      </span>
                    )}
                  </div>

                  <div className="flex items-center gap-2">
                    {c.esperando_respuesta && (
                      <BotonMarcarAtendido contactoId={c.id} variante="compacto" />
                    )}
                    <span className="text-[11px] text-muted-foreground tabular">
                      {tiempoRelativo(c.ultima_actividad_at)}
                    </span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </>
      )}

      {hayMas && (
        <div className="flex justify-center pt-2 pb-6">
          <Button variant="outline" className="h-10 rounded-xl px-6 font-medium shadow-2xs" asChild>
            <Link href={`/contactos?${siguiente.toString()}`}>Cargar más</Link>
          </Button>
        </div>
      )}
    </div>
  );
}

function EstadoVacio({ hayBusqueda, canal }: { hayBusqueda: boolean; canal: string }) {
  const canalTexto =
    canal === 'comercial'
      ? 'en el canal comercial (Línea 324)'
      : canal === 'administrativa'
      ? 'en administrativa (Línea 320)'
      : canal === 'captacion'
      ? 'en captaciones (Línea 320)'
      : canal === 'administrativa_captacion'
      ? 'en administrativo y captaciones (Línea 320)'
      : 'en la bandeja';

  return (
    <div className="flex flex-col items-center gap-3 rounded-2xl border border-dashed border-border/80 bg-card/40 py-16 px-4 text-center">
      <div className="grid size-12 place-items-center rounded-full bg-muted">
        <MessageSquare className="size-6 text-muted-foreground" />
      </div>
      <div>
        <p className="font-semibold text-foreground">
          {hayBusqueda ? 'No hay mensajes que coincidan con los filtros' : `Sin mensajes pendientes ${canalTexto}`}
        </p>
        <p className="mx-auto mt-1 max-w-sm text-sm text-muted-foreground">
          {hayBusqueda
            ? 'Prueba desactivando «Esperando respuesta» o cambiando de canal.'
            : 'Los mensajes nuevos de WhatsApp recibidos por esta línea aparecerán aquí en tiempo real.'}
        </p>
      </div>
    </div>
  );
}
