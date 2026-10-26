import Link from 'next/link';
import { Suspense } from 'react';
import { MessageSquare, PhoneOff, Clock, Check, UserRound } from 'lucide-react';
import { createClient } from '@/lib/supabase/server';
import { tiempoRelativo, telefonoLegible, iniciales, fechaLarga } from '@/lib/formato';
import { FiltrosContactos, type ConteosBandeja } from './FiltrosContactos';
import { BotonMarcarAtendido } from './BotonMarcarAtendido';
import { BandejaEnVivo } from './BandejaEnVivo';
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

/**
 * Sin números de línea escritos a mano: la comercial ya cambió de número
 * una vez (de la 324 a la 312) y la bandeja siguió diciendo «Línea 324».
 */
const CANAL: Record<string, { etiqueta: string; clase: string }> = {
  comercial: {
    etiqueta: 'Comercial',
    clase: 'bg-sky-500/10 text-sky-700 dark:text-sky-300 border-sky-500/30',
  },
  administrativa: {
    etiqueta: 'Administrativa',
    clase: 'bg-purple-500/10 text-purple-700 dark:text-purple-300 border-purple-500/30',
  },
  captacion: {
    etiqueta: 'Captación',
    clase: 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border-emerald-500/30',
  },
};

/**
 * El último mensaje, como se lee en una lista.
 *
 * Las fotos, notas de voz y documentos llegan al CRM con la marca que les
 * pone la plataforma («[foto] … (La foto muestra: …)», la transcripción
 * entera de la nota de voz…). En la bandeja basta con saber qué es y, si el
 * cliente escribió algo con la foto, qué escribió.
 */
function vistaPrevia(texto: string): string {
  const t = texto.trim();
  const conTexto = (icono: string, resto: string) => {
    const leyenda = resto.split(/\n\(La foto muestra:/)[0].trim();
    return leyenda ? `${icono}: ${leyenda}` : icono;
  };
  let m = t.match(/^\[foto\]([\s\S]*)$/i);
  if (m) return conTexto('📷 Foto', m[1]);
  if (/^\[nota de voz/i.test(t)) return '🎤 Nota de voz';
  if (/^\[audio/i.test(t)) return '🎤 Audio';
  m = t.match(/^\[video\]([\s\S]*)$/i);
  if (m) return conTexto('🎬 Video', m[1]);
  m = t.match(/^\[documento(?::[^\]]*)?\]([\s\S]*)$/i);
  if (m) return conTexto('📄 Documento', m[1]);
  if (/^\[sticker\]/i.test(t)) return 'Sticker';
  return t;
}

/** Quién dijo lo último. La RPC no dice si contestó el bot o el equipo. */
function quien(tipo: string | null): string {
  if (tipo === 'mensaje_entrante') return 'Cliente: ';
  if (tipo === 'nota') return 'Nota: ';
  return 'Respuesta: ';
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
      <div className="mx-auto w-full max-w-6xl rounded-xl border border-destructive/30 bg-destructive/10 p-4 text-sm text-destructive">
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

  const resumen: Record<string, { total: number; esperando: number; que: string }> = {
    comercial: {
      total: conteos.comercial_total,
      esperando: conteos.comercial_esperando,
      que: 'conversaciones comerciales',
    },
    administrativa: {
      total: conteos.admin_total,
      esperando: conteos.admin_esperando,
      que: 'casos administrativos',
    },
    captacion: {
      total: conteos.captacion_total,
      esperando: conteos.captacion_esperando,
      que: 'propietarios en captación',
    },
    administrativa_captacion: {
      total: conteos.admin_captacion_total,
      esperando: conteos.admin_captacion_esperando,
      que: 'casos administrativos y de captación',
    },
  };
  const enCanal = resumen[canalActual] ?? {
    total: conteos.total,
    esperando: conteos.total_esperando,
    que: 'conversaciones en total',
  };

  // La columna de canal solo dice algo cuando se ven todos juntos.
  const verCanal = canalActual === 'todos';

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-4">
      <BandejaEnVivo pausado={Boolean(sp.cursor_at)} />

      <header>
        <h1 className="text-xl font-semibold tracking-tight text-foreground">Bandeja de entrada</h1>
        <p className="mt-0.5 text-sm text-muted-foreground">
          <span className="tabular font-medium text-foreground">
            {enCanal.total.toLocaleString('es-CO')}
          </span>{' '}
          {enCanal.que}
          {enCanal.esperando > 0 && (
            <>
              {' · '}
              <span className="tabular font-medium text-amber-700 dark:text-amber-400">
                {enCanal.esperando} esperando respuesta
              </span>
            </>
          )}
        </p>
      </header>

      <Suspense fallback={<Skeleton className="h-24 w-full rounded-xl" />}>
        <FiltrosContactos sinTelefono={sinTelefono ?? 0} canalActual={canalActual} conteos={conteos} />
      </Suspense>

      {contactos.length === 0 ? (
        <EstadoVacio
          hayBusqueda={Boolean(sp.q || sp.tipo || sp.sin_telefono || sp.esperando)}
          canal={canalActual}
        />
      ) : (
        <>
          {/* Escritorio: tabla de ancho fijo. La primera columna se recorta
              para que hora, estado y acción se vean siempre, sin scroll
              horizontal. */}
          <div className="hidden overflow-hidden rounded-xl border bg-card md:block">
            <Table className="table-fixed">
              <TableHeader className="bg-muted/30">
                <TableRow className="hover:bg-transparent">
                  <TableHead className="py-2.5 text-xs font-semibold text-foreground/80">
                    Contacto y último mensaje
                  </TableHead>
                  {verCanal && (
                    <TableHead className="w-32 py-2.5 text-xs font-semibold text-foreground/80">
                      Canal
                    </TableHead>
                  )}
                  <TableHead className="w-44 py-2.5 text-xs font-semibold text-foreground/80">
                    Estado
                  </TableHead>
                  <TableHead className="w-44 py-2.5 text-right text-xs font-semibold text-foreground/80">
                    Acción
                  </TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {contactos.map((c) => {
                  const titulo = c.nombre?.trim() || telefonoLegible(c.telefono_e164) || 'Sin nombre';
                  const canal = CANAL[c.canal ?? ''] ?? CANAL.comercial;
                  return (
                    <TableRow key={c.id} className="group">
                      <TableCell className="py-3 whitespace-normal">
                        <Link href={`/contactos/${c.id}`} className="flex min-w-0 items-start gap-3 outline-none">
                          <Avatar nombre={c.nombre} esperando={Boolean(c.esperando_respuesta)} />
                          <div className="min-w-0 flex-1">
                            <p className="flex min-w-0 items-baseline gap-2">
                              <span className="truncate text-sm font-semibold group-hover:text-primary">
                                {titulo}
                              </span>
                              <span
                                className="shrink-0 text-xs text-muted-foreground tabular"
                                title={fechaLarga(c.ultima_actividad_at)}
                              >
                                {tiempoRelativo(c.ultima_actividad_at)}
                              </span>
                            </p>
                            <Telefono c={c} />
                            {c.ultimo_mensaje ? (
                              <p className="mt-0.5 truncate text-xs text-muted-foreground">
                                <span className="font-medium text-foreground/75">
                                  {quien(c.ultimo_mensaje_tipo)}
                                </span>
                                {vistaPrevia(c.ultimo_mensaje)}
                              </p>
                            ) : (
                              <p className="mt-0.5 text-xs italic text-muted-foreground/70">
                                Sin mensajes todavía
                              </p>
                            )}
                          </div>
                        </Link>
                      </TableCell>

                      {verCanal && (
                        <TableCell className="whitespace-normal">
                          <span
                            className={`inline-flex rounded-md border px-1.5 py-0.5 text-[11px] font-semibold ${canal.clase}`}
                          >
                            {canal.etiqueta}
                          </span>
                        </TableCell>
                      )}

                      <TableCell className="whitespace-normal">
                        <div className="flex flex-col items-start gap-1">
                          <Estado esperando={Boolean(c.esperando_respuesta)} />
                          {c.sin_leer && c.sin_leer > 0 ? (
                            <span
                              className="inline-flex items-center gap-1 rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary"
                              title={`${c.n_actividades} mensajes en total`}
                            >
                              <MessageSquare className="size-3" />
                              {c.sin_leer} {c.sin_leer === 1 ? 'nuevo' : 'nuevos'}
                            </span>
                          ) : null}
                        </div>
                      </TableCell>

                      <TableCell className="text-right">
                        {c.esperando_respuesta ? (
                          <BotonMarcarAtendido contactoId={c.id} variante="compacto" />
                        ) : (
                          <Link
                            href={`/contactos/${c.id}`}
                            className="text-xs font-medium text-muted-foreground hover:text-foreground"
                          >
                            Abrir
                          </Link>
                        )}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>

          {/* Celular: tarjetas */}
          <ul className="flex flex-col gap-2 md:hidden">
            {contactos.map((c) => {
              const titulo = c.nombre?.trim() || telefonoLegible(c.telefono_e164) || 'Sin nombre';
              const canal = CANAL[c.canal ?? ''] ?? CANAL.comercial;
              return (
                <li key={c.id} className="flex flex-col gap-2 rounded-xl border bg-card p-3">
                  <Link href={`/contactos/${c.id}`} className="flex min-w-0 items-start gap-3">
                    <Avatar nombre={c.nombre} esperando={Boolean(c.esperando_respuesta)} />
                    <div className="min-w-0 flex-1">
                      <p className="flex min-w-0 items-baseline gap-2">
                        <span className="truncate text-sm font-semibold text-foreground">{titulo}</span>
                        <span className="ml-auto shrink-0 text-xs text-muted-foreground tabular">
                          {tiempoRelativo(c.ultima_actividad_at)}
                        </span>
                      </p>
                      <Telefono c={c} />
                      {c.ultimo_mensaje && (
                        <p className="mt-1 line-clamp-2 text-xs text-muted-foreground">
                          <span className="font-medium text-foreground/75">
                            {quien(c.ultimo_mensaje_tipo)}
                          </span>
                          {vistaPrevia(c.ultimo_mensaje)}
                        </p>
                      )}
                    </div>
                  </Link>

                  <div className="flex items-center justify-between gap-2 border-t pt-2">
                    <div className="flex flex-wrap items-center gap-1.5">
                      <Estado esperando={Boolean(c.esperando_respuesta)} />
                      {c.sin_leer && c.sin_leer > 0 ? (
                        <span className="rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary">
                          {c.sin_leer} {c.sin_leer === 1 ? 'nuevo' : 'nuevos'}
                        </span>
                      ) : null}
                      {verCanal && (
                        <span
                          className={`rounded-md border px-1.5 py-0.5 text-[11px] font-semibold ${canal.clase}`}
                        >
                          {canal.etiqueta}
                        </span>
                      )}
                    </div>
                    {c.esperando_respuesta && (
                      <BotonMarcarAtendido contactoId={c.id} variante="compacto" />
                    )}
                  </div>
                </li>
              );
            })}
          </ul>
        </>
      )}

      {hayMas && (
        <div className="flex justify-center pb-6 pt-2">
          <Button variant="outline" size="sm" className="h-8 rounded-lg px-4" asChild>
            <Link href={`/contactos?${siguiente.toString()}`}>Cargar más</Link>
          </Button>
        </div>
      )}
    </div>
  );
}

function Avatar({ nombre, esperando }: { nombre: string | null; esperando: boolean }) {
  return (
    <span className="relative mt-0.5 grid size-9 shrink-0 place-items-center rounded-full bg-primary/10 text-xs font-semibold text-primary">
      {nombre?.trim() ? iniciales(nombre) : <UserRound className="size-4" aria-hidden />}
      {esperando && (
        <span className="absolute -right-0.5 -top-0.5 size-2.5 rounded-full bg-amber-500 ring-2 ring-background" />
      )}
    </span>
  );
}

/** El teléfono va debajo del nombre; si no hay nombre, ya es el título. */
function Telefono({
  c,
}: {
  c: { nombre: string | null; telefono_e164: string | null; telefono_crudo: string | null };
}) {
  if (!c.telefono_e164) {
    return (
      <p
        className="inline-flex items-center gap-1 text-xs text-muted-foreground"
        title={`Lo que llegó en su lugar: ${c.telefono_crudo ?? 'nada'}`}
      >
        <PhoneOff className="size-3 opacity-70" />
        Sin número
      </p>
    );
  }
  if (!c.nombre?.trim()) return null;
  return <p className="text-xs text-muted-foreground tabular">{telefonoLegible(c.telefono_e164)}</p>;
}

function Estado({ esperando }: { esperando: boolean }) {
  return esperando ? (
    <span className="inline-flex items-center gap-1 rounded-full border border-amber-500/30 bg-amber-500/15 px-2 py-0.5 text-xs font-semibold text-amber-800 dark:text-amber-300">
      <Clock className="size-3" />
      Esperando respuesta
    </span>
  ) : (
    <span className="inline-flex items-center gap-1 text-xs text-muted-foreground">
      <Check className="size-3 text-emerald-600" />
      Al día
    </span>
  );
}

function EstadoVacio({ hayBusqueda, canal }: { hayBusqueda: boolean; canal: string }) {
  const canalTexto =
    canal === 'comercial'
      ? 'en Comercial'
      : canal === 'administrativa'
        ? 'en Administrativa'
        : canal === 'captacion'
          ? 'en Captación'
          : canal === 'administrativa_captacion'
            ? 'en Administrativa y captación'
            : 'en la bandeja';

  return (
    <div className="flex flex-col items-center gap-3 rounded-xl border border-dashed bg-card/40 px-4 py-16 text-center">
      <div className="grid size-12 place-items-center rounded-full bg-muted">
        <MessageSquare className="size-6 text-muted-foreground" />
      </div>
      <div>
        <p className="font-semibold text-foreground">
          {hayBusqueda ? 'Nada coincide con los filtros' : `No hay conversaciones ${canalTexto}`}
        </p>
        <p className="mx-auto mt-1 max-w-sm text-sm text-muted-foreground">
          {hayBusqueda
            ? 'Prueba quitando «Solo esperando» o cambiando de pestaña.'
            : 'Los mensajes nuevos de WhatsApp aparecen aquí solos, sin recargar.'}
        </p>
      </div>
    </div>
  );
}
