'use client';

import { useState, useTransition, useEffect, useRef, useSyncExternalStore } from 'react';
import Link from 'next/link';
import {
  Check,
  ChevronDown,
  Copy,
  KeyRound,
  Loader2,
  Lock,
  MessageCircle,
  MessageSquare,
  Phone,
  Search,
  SendHorizontal,
  ShieldAlert,
  Sparkles,
  TriangleAlert,
  Zap,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { telefonoLegible } from '@/lib/formato';
import type { EleccionLinea } from '@/lib/lineas';
import type { PlantillaResumen } from './UsarPlantilla';
import { enviarMensaje, renderizar } from './acciones';
import { cuandoColombia } from './estadoBot';

/** Cómo se dice cada variable cuando falta. */
const NOMBRE_VARIABLE: Record<string, string> = {
  nombre: 'el nombre',
  telefono: 'el teléfono',
  asesor: 'tu nombre',
  inmueble: 'el inmueble',
  barrio: 'el barrio',
  ciudad: 'la ciudad',
  precio: 'el precio',
  habitaciones: 'las habitaciones',
  monto: 'monto',
  fecha_limite: 'fecha límite',
  dias_mora: 'días de mora',
  referencia: 'referencia',
};

/** Las que solo llegan en el archivo de un envío masivo de cartera. */
const DE_CARTERA = new Set(['monto', 'fecha_limite', 'dias_mora', 'referencia']);

/** «monto, fecha límite y referencia». */
function enumerar(variables: string[]): string {
  const nombres = variables.map((v) => NOMBRE_VARIABLE[v] ?? v.replace(/_/g, ' '));
  if (nombres.length <= 1) return nombres.join('');
  return `${nombres.slice(0, -1).join(', ')} y ${nombres.at(-1)}`;
}

/** El atajo de enviar se escribe distinto en Mac. Sin suscripción: no cambia. */
const sinSuscripcion = () => () => {};
const esMacEnNavegador = () => /Mac|iPhone|iPad/.test(navigator.userAgent);
const esMacEnServidor = () => false;

/**
 * La caja de escribir de la ficha: lo único que se le manda al cliente sale
 * de aquí, por la línea oficial.
 *
 * 1. DENTRO DE LA VENTANA DE 24 H: texto libre, respuestas rápidas con '/'
 *    y el aviso de hasta qué hora se le puede escribir. Es el ÚNICO sitio de
 *    la ficha que habla de la ventana.
 *
 * 2. FUERA DE LA VENTANA: WhatsApp no entrega texto libre, así que la caja
 *    pasa a ofrecer las plantillas aprobadas de la línea. Arranca con la
 *    primera que se puede llenar con los datos de la ficha: una de cartera
 *    sin monto ni referencia saldría con huecos, y Meta la rechaza.
 */
export function CajaDeEscribir({
  contactoId,
  ventanaAbierta,
  cierraAt,
  nuncaEscribio,
  canalListo,
  linea,
  ahora,
  plantillas = [],
  asesor = null,
}: {
  contactoId: string;
  ventanaAbierta: boolean;
  cierraAt: string | null;
  nuncaEscribio: boolean;
  canalListo: boolean;
  linea: EleccionLinea;
  ahora: string;
  plantillas?: PlantillaResumen[];
  asesor?: string | null;
}) {
  const [texto, setTexto] = useState('');
  const [embudo, setEmbudo] = useState(linea.opciones[0]?.embudo);
  const elegida = linea.opciones.find((l) => l.embudo === embudo) ?? null;
  const lineaCaida = Boolean(elegida?.token_invalido_at);
  const [copiado, setCopiado] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [enviando, iniciarEnvio] = useTransition();

  // Selector visual de plantillas (modal/popover)
  const [selectorAbierto, setSelectorAbierto] = useState(false);
  const [tabSelector, setTabSelector] = useState<'chat' | 'whatsapp'>('chat');
  const [busqueda, setBusqueda] = useState('');
  const [insertando, iniciarInsercion] = useTransition();

  // Autocompletado con '/' (Slash command)
  const [slashActivo, setSlashActivo] = useState(false);
  const [slashFiltro, setSlashFiltro] = useState('');
  const [slashIndex, setSlashIndex] = useState(0);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Modo reactivación (fuera de ventana). Solo las aprobadas de la línea
  // elegida: una plantilla vive en la cuenta de WhatsApp de una línea y
  // por otra no sale. Sin línea, las del número por defecto.
  const lineaElegida = elegida?.wa_phone_number_id ?? null;
  const aprobadas = plantillas.filter(
    (p) =>
      p.tipo !== 'chat' &&
      p.estado_meta === 'aprobada' &&
      (p.wa_phone_number_id ?? null) === lineaElegida
  );
  // La primera que sale completa; si ninguna, la primera.
  const completas = aprobadas.filter((p) => (p.faltan ?? []).length === 0);
  const porDefecto = completas[0]?.id ?? aprobadas[0]?.id ?? null;
  const [plantillaElegidaId, setPlantillaReactivacionId] = useState<string | null>(porDefecto);
  // Al cambiar de línea, la que estaba elegida puede no ser de la nueva.
  const plantillaReactivacionId = aprobadas.some((p) => p.id === plantillaElegidaId)
    ? plantillaElegidaId
    : porDefecto;
  const esMac = useSyncExternalStore(sinSuscripcion, esMacEnNavegador, esMacEnServidor);
  const [textoReactivacion, setTextoReactivacion] = useState('');
  const [cargandoReactivacion, iniciarRenderReactivacion] = useTransition();

  // «hasta las 11:11 p. m.» o «hasta mañana a las 9:00 a. m.»
  const hastaCuando = cierraAt ? cuandoColombia(cierraAt, ahora).replace(/^a (las?) /, '$1 ') : null;

  // Cargar texto renderizado de la plantilla de reactivación seleccionada
  useEffect(() => {
    if (!ventanaAbierta && plantillaReactivacionId) {
      iniciarRenderReactivacion(async () => {
        const r = await renderizar(plantillaReactivacionId, contactoId, null, asesor);
        setTextoReactivacion(r ?? '');
      });
    }
  }, [ventanaAbierta, plantillaReactivacionId, contactoId, asesor]);

  // Manejador para copiar al portapapeles
  const copiar = async (contenido: string) => {
    try {
      await navigator.clipboard.writeText(contenido);
      setCopiado(true);
      setTimeout(() => setCopiado(false), 2000);
    } catch {
      // Sin permiso de portapapeles el asesor lo selecciona a mano
    }
  };

  // Enviar mensaje de texto libre dentro de ventana
  const enviarLibre = () => {
    if (!texto.trim() || enviando) return;
    setError(null);
    iniciarEnvio(async () => {
      const r = await enviarMensaje(contactoId, texto, elegida?.embudo);
      if (r.ok) {
        setTexto('');
      } else {
        setError(r.error ?? 'No se pudo enviar.');
      }
    });
  };

  // Enviar plantilla oficial de reactivación fuera de ventana
  const enviarReactivacion = () => {
    if (!plantillaReactivacionId || !textoReactivacion.trim() || enviando) return;
    setError(null);
    iniciarEnvio(async () => {
      const r = await enviarMensaje(
        contactoId,
        textoReactivacion,
        elegida?.embudo,
        plantillaReactivacionId
      );
      if (r.ok) {
        setTextoReactivacion('');
      } else {
        setError(r.error ?? 'No se pudo enviar la plantilla oficial.');
      }
    });
  };

  // Inserción de plantilla en el textarea
  const insertarPlantilla = async (
    p: PlantillaResumen,
    reemplazarSlash: boolean = false
  ) => {
    iniciarInsercion(async () => {
      const renderizado = (await renderizar(p.id, contactoId, null, asesor)) ?? '';
      if (reemplazarSlash) {
        // Reemplaza el token '/...' previo al cursor
        setTexto((prev) => {
          const match = prev.match(/(?:^|\s)\/([a-zA-Z0-9_\u00C0-\u017F-]*)$/);
          if (match && match.index !== undefined) {
            const start = match[0].startsWith(' ') ? match.index + 1 : match.index;
            return prev.slice(0, start) + renderizado + ' ';
          }
          return prev ? `${prev}\n${renderizado}` : renderizado;
        });
      } else {
        setTexto((prev) => (prev ? `${prev}\n\n${renderizado}` : renderizado));
      }

      setSelectorAbierto(false);
      setSlashActivo(false);

      setTimeout(() => {
        textareaRef.current?.focus();
      }, 50);
    });
  };

  // Detección de comando '/' mientras se teclea
  const manejarCambioTexto = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    const nuevo = e.target.value;
    setTexto(nuevo);

    // Detecta si lo último escrito es '/' seguido opcionalmente de letras
    const match = nuevo.match(/(?:^|\s)\/([a-zA-Z0-9_\u00C0-\u017F-]*)$/);
    if (match) {
      setSlashActivo(true);
      setSlashFiltro(match[1].toLowerCase());
      setSlashIndex(0);
    } else {
      setSlashActivo(false);
    }
  };

  // Filtrado para el menú de autocompletado con '/'
  const sugerenciasSlash = plantillas
    .filter((p) => {
      if (!slashFiltro) return true;
      return (
        p.nombre.toLowerCase().includes(slashFiltro) ||
        p.categoria.toLowerCase().includes(slashFiltro)
      );
    })
    .slice(0, 5);

  // Manejo de teclado: atajos Enter y slash menu
  const manejarKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (slashActivo && sugerenciasSlash.length > 0) {
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        setSlashIndex((prev) => (prev + 1) % sugerenciasSlash.length);
        return;
      }
      if (e.key === 'ArrowUp') {
        e.preventDefault();
        setSlashIndex((prev) => (prev - 1 + sugerenciasSlash.length) % sugerenciasSlash.length);
        return;
      }
      if (e.key === 'Enter' || e.key === 'Tab') {
        e.preventDefault();
        const seleccionada = sugerenciasSlash[slashIndex];
        if (seleccionada) {
          insertarPlantilla(seleccionada, true);
        }
        return;
      }
      if (e.key === 'Escape') {
        e.preventDefault();
        setSlashActivo(false);
        return;
      }
    }

    // Ctrl+Enter o Cmd+Enter para enviar rápido
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
      e.preventDefault();
      enviarLibre();
    }
  };

  // Filtrado para el modal completo de plantillas
  const plantillasFiltradas = plantillas.filter((p) => {
    const coincideTipo = tabSelector === 'chat' ? p.tipo === 'chat' : p.tipo !== 'chat';
    if (!coincideTipo) return false;
    if (!busqueda.trim()) return true;
    const q = busqueda.toLowerCase();
    return p.nombre.toLowerCase().includes(q) || p.categoria.toLowerCase().includes(q);
  });

  const huecosReactivacion = textoReactivacion.match(/\[sin [^\]]+\]|\[asesor\]/g);

  // =========================================================================
  // CASO 1: FUERA DE LA VENTANA DE 24 HORAS (SOLO PLANTILLAS APROBADAS)
  // =========================================================================
  if (!ventanaAbierta) {
    const plantillaActual = aprobadas.find((p) => p.id === plantillaReactivacionId);
    const faltan = plantillaActual?.faltan ?? [];
    const incompleta = faltan.length > 0 || Boolean(huecosReactivacion);
    const hayOtraCompleta = completas.some((p) => p.id !== plantillaActual?.id);

    // Esta no es sticky: es alta (plantilla, vista previa, aviso) y fija
    // abajo taparía casi toda la conversación. El chat abre en el fondo,
    // así que igual se ve al llegar.
    return (
      <div className="mb-3 flex flex-col gap-3 rounded-xl border border-amber-500/40 bg-amber-50 p-4 dark:bg-amber-950">
        <div className="flex items-start gap-2.5">
          <ShieldAlert className="mt-0.5 size-4 shrink-0 text-amber-700 dark:text-amber-300" />
          <div className="min-w-0 flex-1">
            <h3 className="text-sm font-semibold text-foreground">Reactivar la conversación</h3>
            <p className="mt-0.5 text-xs leading-relaxed text-muted-foreground">
              {nuncaEscribio
                ? 'Esta persona todavía no nos ha escrito: solo puedes enviarle una plantilla aprobada.'
                : 'Pasaron más de 24 h: solo puedes enviarle una plantilla aprobada.'}
            </p>
          </div>
        </div>

        {aprobadas.length === 0 ? (
          <div className="flex flex-col items-center justify-center gap-2 rounded-xl border border-dashed border-border/80 bg-background/50 p-6 text-center">
            <Lock className="size-6 text-muted-foreground/60" />
            <p className="text-xs font-semibold text-foreground">
              Esta línea no tiene plantillas aprobadas
            </p>
            <p className="max-w-md text-xs text-muted-foreground">
              Para escribirle fuera de las 24 h hace falta al menos una plantilla aprobada por
              WhatsApp para esta línea.
            </p>
            <Button size="sm" variant="outline" asChild className="mt-2 h-8 gap-1.5 rounded-lg text-xs">
              <Link href="/plantillas">
                <Sparkles className="size-3.5" />
                Ir a Plantillas
              </Link>
            </Button>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {/* Selector de plantilla aprobada */}
            <div className="flex flex-col gap-1.5">
              <label htmlFor="select-reactivacion" className="text-xs font-medium text-foreground">
                Plantilla aprobada
              </label>
              <div className="relative">
                <select
                  id="select-reactivacion"
                  value={plantillaReactivacionId ?? ''}
                  onChange={(e) => setPlantillaReactivacionId(e.target.value)}
                  disabled={cargandoReactivacion || enviando}
                  className="h-8 w-full appearance-none rounded-lg border bg-background px-2.5 pr-8 text-xs font-medium text-foreground focus:outline-none focus:ring-2 focus:ring-ring/50"
                >
                  {aprobadas.map((p) => {
                    const le = p.faltan ?? [];
                    const nota =
                      le.length === 0
                        ? ''
                        : le.some((v) => DE_CARTERA.has(v))
                          ? ' · necesita datos del archivo de cartera'
                          : ' · necesita datos que no están en la ficha';
                    return (
                      <option key={p.id} value={p.id}>
                        {p.nombre}
                        {nota}
                      </option>
                    );
                  })}
                </select>
                <ChevronDown className="pointer-events-none absolute right-2.5 top-2 size-4 text-muted-foreground" />
              </div>
            </div>

            {/* Vista previa en burbuja de WhatsApp */}
            <div className="flex flex-col gap-1.5">
              <span className="text-xs font-medium text-muted-foreground">
                Así le llegará
              </span>
              <div className="relative max-h-40 overflow-y-auto rounded-lg border bg-background p-3">
                {cargandoReactivacion ? (
                  <div className="flex items-center justify-center gap-2 py-6 text-xs text-muted-foreground">
                    <Loader2 className="size-4 animate-spin text-primary" />
                    Preparando variables del contacto…
                  </div>
                ) : (
                  <p className="whitespace-pre-wrap break-words text-xs leading-relaxed text-foreground">
                    {textoReactivacion || 'Sin contenido en la plantilla.'}
                  </p>
                )}
              </div>

              {incompleta && (
                <div
                  role="status"
                  className="flex items-start gap-1.5 rounded-lg border border-amber-500/40 bg-amber-500/10 p-2.5 text-xs text-amber-900 dark:text-amber-200"
                >
                  <TriangleAlert className="mt-0.5 size-3.5 shrink-0" />
                  <span>
                    {faltan.length > 0
                      ? `Esta plantilla necesita ${enumerar(faltan)}, que no ${faltan.length === 1 ? 'está' : 'están'} en la ficha.`
                      : `A esta plantilla le faltan datos de la ficha: ${huecosReactivacion?.join(', ')}.`}{' '}
                    {hayOtraCompleta
                      ? 'Elige otra.'
                      : 'No hay otra plantilla aprobada de esta línea que salga completa.'}
                  </span>
                </div>
              )}
            </div>

            {/* Línea de salida */}
            {elegida && (
              <div className="flex flex-wrap items-center gap-x-1.5 gap-y-1 text-xs text-muted-foreground">
                <Phone className="size-3 text-muted-foreground" />
                <span>
                  Saldrá por la línea <b className="font-medium text-foreground">{elegida.nombre}</b>
                </span>
                {elegida.telefono_e164 && (
                  <span className="tabular">· {telefonoLegible(elegida.telefono_e164)}</span>
                )}
              </div>
            )}

            {/* Botones de acción */}
            <div className="flex flex-wrap items-center justify-end gap-2 border-t border-amber-500/20 pt-2">
              {/* Copiar solo hace falta si el envío directo no está conectado */}
              {!canalListo && (
                <Button
                  type="button"
                  size="sm"
                  variant="ghost"
                  onClick={() => copiar(textoReactivacion)}
                  disabled={!textoReactivacion || enviando || cargandoReactivacion}
                  className="h-8 gap-1.5 rounded-lg text-xs"
                >
                  {copiado ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
                  {copiado ? 'Copiado' : 'Copiar texto'}
                </Button>
              )}

              <Button
                type="button"
                size="sm"
                onClick={enviarReactivacion}
                disabled={
                  !canalListo ||
                  lineaCaida ||
                  incompleta ||
                  !textoReactivacion.trim() ||
                  enviando ||
                  cargandoReactivacion
                }
                className="h-8 gap-1.5 rounded-lg text-xs font-semibold"
              >
                {enviando ? (
                  <Loader2 className="size-3.5 animate-spin" />
                ) : (
                  <SendHorizontal className="size-3.5" />
                )}
                {enviando ? 'Enviando…' : 'Reactivar conversación'}
              </Button>
            </div>

            {error && (
              <p role="alert" className="text-xs text-destructive font-medium">
                {error}
              </p>
            )}

            {!canalListo && (
              <p className="text-xs text-muted-foreground">
                El envío directo todavía no está conectado: por ahora copia el mensaje y mándalo
                por la línea de WhatsApp que corresponde.
              </p>
            )}
          </div>
        )}
      </div>
    );
  }

  // =========================================================================
  // CASO 2: DENTRO DE LA VENTANA DE 24 HORAS (CONVERSACIÓN LIBRE + PLANTILLAS)
  // =========================================================================
  return (
    <div className="sticky bottom-0 z-10 mb-3 flex flex-col gap-2.5 rounded-xl border bg-card p-3 shadow-[0_-6px_12px_-10px_rgb(0_0_0/0.25)]">
      {/* Menú flotante de autocompletado con '/' */}
      {slashActivo && sugerenciasSlash.length > 0 && (
        <div className="absolute bottom-full left-3 z-30 mb-2 w-80 rounded-xl border border-border/80 bg-popover/95 p-1.5 shadow-xl backdrop-blur-md animate-in fade-in slide-in-from-bottom-2">
          <div className="flex items-center justify-between px-2.5 py-1 text-[11px] font-semibold text-muted-foreground border-b border-border/50 pb-1 mb-1">
            <span className="flex items-center gap-1">
              <Sparkles className="size-3 text-primary" />
              Respuestas rápidas sugeridas
            </span>
            <span className="text-[11px] text-muted-foreground/75">↑↓ navegar · Enter</span>
          </div>
          <div className="flex flex-col gap-0.5">
            {sugerenciasSlash.map((p, idx) => {
              const seleccionado = idx === slashIndex;
              const esChat = p.tipo === 'chat';
              return (
                <button
                  key={p.id}
                  type="button"
                  onClick={() => insertarPlantilla(p, true)}
                  className={`flex items-center justify-between gap-2 rounded-xl px-2.5 py-1.5 text-left text-xs transition-colors cursor-pointer ${
                    seleccionado
                      ? 'bg-primary text-primary-foreground font-medium'
                      : 'hover:bg-muted text-foreground'
                  }`}
                >
                  <div className="flex items-center gap-2 min-w-0">
                    {esChat ? (
                      <MessageSquare className="size-3.5 shrink-0 opacity-70" />
                    ) : (
                      <MessageCircle className="size-3.5 shrink-0 opacity-70 text-emerald-500" />
                    )}
                    <span className="truncate">{p.nombre}</span>
                  </div>
                  <span
                    className={`text-[11px] px-1.5 py-0.2 rounded-md capitalize shrink-0 ${
                      seleccionado
                        ? 'bg-primary-foreground/20 text-primary-foreground'
                        : 'bg-muted text-muted-foreground'
                    }`}
                  >
                    {p.categoria}
                  </span>
                </button>
              );
            })}
          </div>
        </div>
      )}

      {/* Barra de herramientas superior del chat */}
      <div className="flex items-center justify-between gap-2 border-b border-border/40 pb-2">
        <div className="flex items-center gap-1.5">
          <Button
            type="button"
            size="sm"
            variant="ghost"
            onClick={() => {
              setSelectorAbierto(true);
              setBusqueda('');
            }}
            className="h-8 gap-1.5 rounded-lg px-2 text-xs font-medium text-muted-foreground hover:text-foreground hover:bg-muted"
          >
            <Zap className="size-3.5 text-amber-500" />
            <span>Respuestas rápidas</span>
            <span className="rounded-md bg-muted px-1.5 py-0.2 text-[11px] text-muted-foreground font-mono">
              /
            </span>
          </Button>
        </div>

        {/* La ventana de 24 h, dicha una sola vez y con la hora de Colombia */}
        {hastaCuando && (
          <span className="text-xs text-muted-foreground">
            Puedes escribirle hasta {hastaCuando}
          </span>
        )}
      </div>

      {/* Campo de texto de mensaje */}
      <div className="relative">
        <Textarea
          ref={textareaRef}
          value={texto}
          onChange={manejarCambioTexto}
          onKeyDown={manejarKeyDown}
          rows={3}
          placeholder="Escribe un mensaje, o «/» para una respuesta rápida…"
          aria-label="Mensaje para esta persona"
          disabled={enviando || insertando}
          className="rounded-xl border-none bg-transparent p-1 text-sm shadow-none focus-visible:ring-0 resize-none leading-relaxed"
        />
      </div>

      {/* Selector de línea y detalles */}
      {elegida && (
        <div className="flex flex-wrap items-center gap-x-1.5 gap-y-1 text-xs text-muted-foreground pt-1 border-t border-border/40">
          <Phone className="size-3 text-muted-foreground" />
          {linea.opciones.length > 1 ? (
            <>
              <label htmlFor={`linea-${contactoId}`} className="text-xs">
                Sale por
              </label>
              <select
                id={`linea-${contactoId}`}
                value={elegida.embudo}
                onChange={(e) => setEmbudo(e.target.value)}
                disabled={enviando}
                className="h-7 rounded-lg border bg-background px-2 text-xs font-medium text-foreground"
              >
                {linea.opciones.map((l) => (
                  <option key={l.embudo} value={l.embudo}>
                    {l.nombre}
                  </option>
                ))}
              </select>
            </>
          ) : (
            <span className="text-xs">
              Sale por <b className="font-medium text-foreground">{elegida.nombre}</b>
            </span>
          )}
          {elegida.telefono_e164 && (
            <span className="tabular text-xs">· {telefonoLegible(elegida.telefono_e164)}</span>
          )}
        </div>
      )}

      {lineaCaida && (
        <p role="alert" className="flex items-start gap-1.5 text-xs text-destructive">
          <KeyRound className="mt-0.5 size-3.5 shrink-0" />
          <span>
            WhatsApp rechaza la credencial de esta línea. Hay que reconectarla en{' '}
            <Link href="/lineas" className="underline font-medium">
              Líneas
            </Link>
            .
          </span>
        </p>
      )}

      {/* Botones inferiores */}
      <div className="flex flex-wrap items-center justify-between gap-2 pt-1">
        {/* En pantallas táctiles no hay teclado con Ctrl: la pista sobra */}
        <span className="hidden text-[11px] text-muted-foreground [@media(hover:hover)_and_(pointer:fine)]:inline">
          <kbd className="rounded bg-muted px-1 py-0.5 font-mono">{esMac ? '⌘ + Enter' : 'Ctrl + Enter'}</kbd>{' '}
          para enviar
        </span>

        <div className="ml-auto flex items-center gap-1.5">
          {!canalListo && (
            <Button
              size="sm"
              variant="ghost"
              onClick={() => copiar(texto)}
              disabled={!texto.trim() || enviando}
              className="h-8 gap-1.5 rounded-lg text-xs"
            >
              {copiado ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
              {copiado ? 'Copiado' : 'Copiar'}
            </Button>
          )}

          <Button
            size="sm"
            onClick={enviarLibre}
            disabled={!canalListo || lineaCaida || !texto.trim() || enviando}
            className="h-8 gap-1.5 rounded-lg px-3.5 text-xs font-semibold"
            title={
              canalListo
                ? 'Enviar por WhatsApp'
                : 'El envío directo todavía no está conectado'
            }
          >
            {enviando ? (
              <Loader2 className="size-3.5 animate-spin" />
            ) : (
              <SendHorizontal className="size-3.5" />
            )}
            {enviando ? 'Enviando…' : 'Enviar'}
          </Button>
        </div>
      </div>

      {error && (
        <p role="alert" className="text-xs text-destructive font-medium">
          {error}
        </p>
      )}

      {!canalListo && (
        <p className="text-xs text-muted-foreground">
          El envío directo todavía no está conectado: por ahora copia el mensaje y pégalo en
          WhatsApp.
        </p>
      )}

      {/* Diálogo / Selector Completo de Plantillas y Respuestas */}
      <Dialog open={selectorAbierto} onOpenChange={setSelectorAbierto}>
        <DialogContent className="sm:max-w-xl max-h-[85vh] overflow-y-auto rounded-xl">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2 text-base">
              <Zap className="size-4 text-amber-500" />
              Respuestas rápidas y plantillas
            </DialogTitle>
            <DialogDescription className="text-xs">
              Selecciona una respuesta para insertarla en el chat con los datos de esta persona ya
              rellenos.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-3 py-1">
            {/* Buscador */}
            <div className="relative">
              <Search className="absolute left-3 top-2.5 size-3.5 text-muted-foreground" />
              <input
                type="text"
                placeholder="Buscar por nombre o categoría…"
                value={busqueda}
                onChange={(e) => setBusqueda(e.target.value)}
                className="w-full rounded-xl border bg-muted/40 pl-8 pr-3 py-2 text-xs focus:bg-background focus:outline-none focus:ring-2 focus:ring-primary/20"
              />
            </div>

            {/* Pestañas Chat vs WhatsApp */}
            <div className="flex items-center gap-1.5 rounded-xl bg-muted/40 p-1 border border-border/50">
              <button
                type="button"
                onClick={() => setTabSelector('chat')}
                className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-semibold transition-all cursor-pointer ${
                  tabSelector === 'chat'
                    ? 'bg-background text-foreground shadow-xs'
                    : 'text-muted-foreground hover:text-foreground'
                }`}
              >
                <MessageSquare className="size-3.5 text-blue-500" />
                <span>Respuestas rápidas</span>
                <span className="rounded-full bg-muted px-1.5 py-0.2 text-[11px] tabular">
                  {plantillas.filter((p) => p.tipo === 'chat').length}
                </span>
              </button>

              <button
                type="button"
                onClick={() => setTabSelector('whatsapp')}
                className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-semibold transition-all cursor-pointer ${
                  tabSelector === 'whatsapp'
                    ? 'bg-background text-foreground shadow-xs'
                    : 'text-muted-foreground hover:text-foreground'
                }`}
              >
                <MessageCircle className="size-3.5 text-emerald-500" />
                <span>Plantillas de WhatsApp</span>
                <span className="rounded-full bg-muted px-1.5 py-0.2 text-[11px] tabular">
                  {plantillas.filter((p) => p.tipo !== 'chat').length}
                </span>
              </button>
            </div>

            {/* Lista de plantillas */}
            <div className="flex flex-col gap-2 max-h-72 overflow-y-auto pr-1">
              {plantillasFiltradas.length === 0 ? (
                <div className="flex flex-col items-center justify-center gap-2 rounded-xl border border-dashed py-8 text-center bg-muted/20">
                  <p className="text-xs text-muted-foreground">
                    No se encontraron plantillas en esta sección.
                  </p>
                </div>
              ) : (
                plantillasFiltradas.map((p) => {
                  const esAprobada = p.estado_meta === 'aprobada';
                  return (
                    <div
                      key={p.id}
                      className="flex items-center justify-between gap-3 rounded-xl border border-border/60 bg-card p-3 hover:border-primary/40 transition-colors"
                    >
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2">
                          <span className="font-semibold text-xs text-foreground truncate">
                            {p.nombre}
                          </span>
                          {p.tipo !== 'chat' && (
                            <Badge
                              variant="outline"
                              className={`text-[11px] h-4 px-1.5 ${
                                esAprobada
                                  ? 'border-emerald-500/30 text-emerald-700 bg-emerald-500/10'
                                  : 'text-muted-foreground'
                              }`}
                            >
                              {esAprobada ? 'Aprobada' : p.estado_meta ?? 'Borrador'}
                            </Badge>
                          )}
                        </div>
                        <span className="text-[11px] text-muted-foreground capitalize">
                          {p.categoria}
                        </span>
                      </div>

                      <Button
                        size="sm"
                        onClick={() => insertarPlantilla(p, false)}
                        disabled={insertando}
                        className="rounded-xl text-xs h-7 px-3 gap-1"
                      >
                        {insertando ? (
                          <Loader2 className="size-3 animate-spin" />
                        ) : (
                          <Zap className="size-3" />
                        )}
                        Insertar
                      </Button>
                    </div>
                  );
                })
              )}
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
