'use client';

import { useState, useTransition } from 'react';
import {
  Archive,
  CheckCircle2,
  Clock,
  AlertTriangle,
  FileText,
  Loader2,
  Pencil,
  Plus,
  RefreshCw,
  Send,
  MessageSquare,
  MessageCircle,
  Sparkles,
  Info,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { previsualizar } from '@/lib/plantillas';
import {
  guardarPlantilla,
  archivarPlantilla,
  enviarAMeta,
  sincronizarConMeta,
} from './acciones';

export interface Plantilla {
  id: string;
  nombre: string;
  cuerpo: string;
  categoria: string;
  estado_meta: string;
  nombre_meta: string | null;
  tipo?: string;
  idioma?: string;
  motivo_rechazo_meta?: string | null;
  wa_phone_number_id?: string | null;
}

/** Una línea conectada: las plantillas de WhatsApp viven en su WABA. */
export interface LineaPlantilla {
  wa_phone_number_id: string;
  nombre: string;
  embudo: string;
}

/** Ya en Meta: lo que Meta revisó no se toca desde aquí. */
function estaEnMeta(p: Plantilla | null): boolean {
  return Boolean(p && p.tipo !== 'chat' && ['enviada', 'aprobada'].includes(p.estado_meta));
}

const ESTADOS_META: Record<
  string,
  {
    texto: string;
    ayuda: string;
    icono: React.ComponentType<{ className?: string }>;
    estilo: string;
  }
> = {
  aprobada: {
    texto: 'Aprobada por Meta',
    ayuda: 'Aprobada oficialmente. Se puede enviar para iniciar conversación fuera de las 24 horas.',
    icono: CheckCircle2,
    estilo: 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 border-emerald-300 dark:border-emerald-800',
  },
  enviada: {
    texto: 'En revisión de Meta',
    ayuda: 'Enviada a Meta, esperando respuesta de la IA o revisores (tarda entre 5 min y 24 h).',
    icono: Clock,
    estilo: 'bg-blue-500/10 text-blue-700 dark:text-blue-400 border-blue-300 dark:border-blue-800',
  },
  rechazada: {
    texto: 'Rechazada por Meta',
    ayuda: 'Meta rechazó la plantilla. Revisa el motivo de rechazo y reescríbela.',
    icono: AlertTriangle,
    estilo: 'bg-destructive/10 text-destructive border-destructive/30',
  },
  borrador: {
    texto: 'Borrador local',
    ayuda: 'Redactada en el CRM; aún no se ha mandado a revisión de Meta.',
    icono: FileText,
    estilo: 'bg-muted text-muted-foreground border-border/60',
  },
};

export function GestorPlantillas({
  plantillas,
  variables,
  lineas,
  puedeEditar,
}: {
  plantillas: Plantilla[];
  variables: string[];
  lineas: LineaPlantilla[];
  puedeEditar: boolean;
}) {
  const [tabActiva, setTabActiva] = useState<'whatsapp' | 'chat'>('whatsapp');
  const [editando, setEditando] = useState<Plantilla | 'nueva-whatsapp' | 'nueva-chat' | null>(null);
  const [nombre, setNombre] = useState('');
  const [nombreMeta, setNombreMeta] = useState('');
  const [cuerpo, setCuerpo] = useState('');
  const [categoria, setCategoria] = useState('utilidad');
  const [idioma, setIdioma] = useState('es');
  const [linea, setLinea] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [mensajeSync, setMensajeSync] = useState<string | null>(null);
  const [pendiente, startTransition] = useTransition();

  const plantillasWhatsApp = plantillas.filter((p) => p.tipo !== 'chat');
  const plantillasChat = plantillas.filter((p) => p.tipo === 'chat');
  const nombreDeLinea = (id?: string | null) =>
    lineas.find((l) => l.wa_phone_number_id === id)?.nombre ?? null;

  // Lo que Meta ya revisó no se edita: solo el título.
  const bloqueada = typeof editando === 'object' && estaEnMeta(editando);

  function abrir(p: Plantilla | 'nueva-whatsapp' | 'nueva-chat') {
    setEditando(p);
    setError(null);
    if (typeof p === 'string') {
      setNombre('');
      setNombreMeta('');
      setCuerpo('');
      setCategoria(p === 'nueva-whatsapp' ? 'utilidad' : 'general');
      setIdioma('es');
      setLinea(lineas[0]?.wa_phone_number_id ?? '');
    } else {
      setNombre(p.nombre);
      setNombreMeta(p.nombre_meta ?? '');
      setCuerpo(p.cuerpo);
      setCategoria(p.categoria);
      setIdioma(p.idioma ?? 'es');
      // Un borrador sin línea propone la primera; una que ya está en Meta
      // se queda como está, aunque no tenga línea.
      setLinea(
        p.wa_phone_number_id ??
          (p.tipo !== 'chat' && !estaEnMeta(p) ? lineas[0]?.wa_phone_number_id ?? '' : '')
      );
    }
  }

  function handleNombreChange(val: string) {
    setNombre(val);
    // Si es WhatsApp y estamos creando una nueva, autogenera el nombre técnico de Meta
    if (editando === 'nueva-whatsapp') {
      const tecnico = val
        .toLowerCase()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .replace(/[^a-z0-9_]/g, '_')
        .replace(/_+/g, '_')
        .slice(0, 50);
      setNombreMeta(tecnico);
    }
  }

  function guardar(enviarDirectoAMeta = false) {
    setError(null);
    startTransition(async () => {
      const tipoPlantilla =
        editando === 'nueva-chat' || (typeof editando === 'object' && editando?.tipo === 'chat')
          ? 'chat'
          : 'whatsapp';

      const r = await guardarPlantilla(
        typeof editando === 'object' && editando !== null ? editando.id : null,
        nombre,
        cuerpo,
        categoria,
        tipoPlantilla,
        tipoPlantilla === 'whatsapp' ? nombreMeta : null,
        idioma,
        tipoPlantilla === 'whatsapp' ? linea || null : null
      );

      if (!r.ok) {
        setError(r.error ?? 'No se pudo guardar la plantilla.');
        return;
      }

      // Si además pidió mandarla a revisión. Una nueva no tenía id hasta
      // ahora: el que vale es el que devolvió el guardado.
      if (enviarDirectoAMeta && tipoPlantilla === 'whatsapp' && r.id) {
        const rMeta = await enviarAMeta(r.id, linea || null);
        if (!rMeta.ok) {
          setError(`Quedó guardada como borrador, pero no se pudo mandar a Meta: ${rMeta.error}`);
          return;
        }
      }

      setEditando(null);
    });
  }

  function handleEnviarAMeta(p: Plantilla) {
    setError(null);
    // Sin línea y con varias conectadas, hay que elegir antes de mandarla.
    if (!p.wa_phone_number_id && lineas.length !== 1) {
      abrir(p);
      setError(
        lineas.length === 0
          ? 'Para mandarla a Meta hace falta una línea conectada.'
          : 'Elige por qué línea va a salir y pulsa «Mandar a Meta».'
      );
      return;
    }
    startTransition(async () => {
      const r = await enviarAMeta(p.id, p.wa_phone_number_id ?? lineas[0]?.wa_phone_number_id ?? null);
      if (!r.ok) {
        setError(r.error ?? 'No se pudo enviar a revisión.');
      }
    });
  }

  function sincronizar() {
    setError(null);
    setMensajeSync(null);
    startTransition(async () => {
      const r = await sincronizarConMeta();
      if (!r.ok) {
        setError(r.error ?? 'Error al sincronizar con Meta.');
      } else {
        setMensajeSync(r.detalles ?? 'Plantillas sincronizadas con Meta.');
        setTimeout(() => setMensajeSync(null), 5000);
      }
    });
  }

  function archivar(id: string) {
    startTransition(async () => {
      await archivarPlantilla(id);
    });
  }

  return (
    <div className="flex flex-col gap-5">
      {/* Pestañas ergonómicas de selección */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border/60 pb-3">
        <div className="flex items-center gap-2 rounded-xl bg-muted/40 p-1 border border-border/50">
          <button
            type="button"
            onClick={() => setTabActiva('whatsapp')}
            className={`flex items-center gap-2 rounded-xl px-4 py-2 text-xs font-semibold transition-all ${
              tabActiva === 'whatsapp'
                ? 'bg-background text-foreground shadow-xs'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            <MessageCircle className="size-3.5 text-emerald-600 dark:text-emerald-400" />
            <span>Plantillas de WhatsApp</span>
            <span className="rounded-full bg-primary/10 px-2 py-0.2 text-[11px] font-bold tabular text-primary">
              {plantillasWhatsApp.length}
            </span>
          </button>

          <button
            type="button"
            onClick={() => setTabActiva('chat')}
            className={`flex items-center gap-2 rounded-xl px-4 py-2 text-xs font-semibold transition-all ${
              tabActiva === 'chat'
                ? 'bg-background text-foreground shadow-xs'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            <MessageSquare className="size-3.5 text-blue-600 dark:text-blue-400" />
            <span>Respuestas rápidas de chat</span>
            <span className="rounded-full bg-muted px-2 py-0.2 text-[11px] font-bold tabular text-muted-foreground">
              {plantillasChat.length}
            </span>
          </button>
        </div>

        {/* Barra de acciones según pestaña */}
        {puedeEditar && (
          <div className="flex items-center gap-2">
            {tabActiva === 'whatsapp' && (
              <>
                <Button
                  size="sm"
                  variant="outline"
                  className="h-8 rounded-lg text-xs gap-1.5"
                  onClick={sincronizar}
                  disabled={pendiente || lineas.length === 0}
                  title={
                    lineas.length === 0
                      ? 'Las plantillas viven en la cuenta de WhatsApp de cada línea: primero hay que conectar una'
                      : 'Consulta en Meta las plantillas de cada línea y actualiza su estado'
                  }
                >
                  <RefreshCw className={`size-3.5 ${pendiente ? 'animate-spin' : ''}`} />
                  Sincronizar con Meta
                </Button>

                <Button
                  size="sm"
                  className="h-8 rounded-lg text-xs gap-1.5"
                  onClick={() => abrir('nueva-whatsapp')}
                >
                  <Plus className="size-3.5" />
                  Nueva plantilla de WhatsApp
                </Button>
              </>
            )}

            {tabActiva === 'chat' && (
              <Button
                size="sm"
                className="h-8 rounded-lg text-xs gap-1.5 shadow-xs"
                onClick={() => abrir('nueva-chat')}
              >
                <Plus className="size-3.5" />
                Nueva respuesta rápida
              </Button>
            )}
          </div>
        )}
      </div>

      {/* Avisos informativos o de sincronización */}
      {mensajeSync && (
        <div className="flex items-center gap-2 rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-3 text-xs text-emerald-800 dark:text-emerald-300">
          <CheckCircle2 className="size-4 shrink-0" />
          <span>{mensajeSync}</span>
        </div>
      )}

      {error && (
        <div className="flex items-center gap-2 rounded-xl border border-destructive/30 bg-destructive/10 p-3 text-xs text-destructive">
          <AlertTriangle className="size-4 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {/* ============================================================== */}
      {/* VISTA 1: PLANTILLAS DE WHATSAPP (META HSM)                     */}
      {/* ============================================================== */}
      {tabActiva === 'whatsapp' && (
        <div className="flex flex-col gap-4">
          <div className="flex items-start gap-2.5 rounded-xl border border-border/60 bg-muted/20 p-3.5 text-xs text-muted-foreground">
            <Info className="size-4 shrink-0 text-primary mt-0.5" />
            <div>
              <p className="font-semibold text-foreground">Reglas de Meta para WhatsApp:</p>
              <p className="mt-0.5 leading-relaxed">
                Estas plantillas son evaluadas por la IA y revisores de Meta. Son obligatorias para iniciar conversaciones,
                para reactivación y para contactar prospectos cuando pasaron más de 24 horas desde su último mensaje.
                Cada una vive en la cuenta de WhatsApp de <span className="font-semibold">una línea</span> y solo sale
                por esa línea.
              </p>
            </div>
          </div>

          {plantillasWhatsApp.length === 0 ? (
            <div className="rounded-xl border border-dashed border-border/80 py-16 text-center bg-card/40">
              <MessageCircle className="mx-auto size-8 text-muted-foreground/60 mb-2" />
              <p className="font-semibold text-foreground">No hay plantillas de WhatsApp registradas</p>
              <p className="text-xs text-muted-foreground mt-1 max-w-sm mx-auto">
                {puedeEditar
                  ? 'Crea una nueva plantilla para enviarla a revisión de Meta, o pulsa "Sincronizar con Meta" si ya tienes en tu WABA.'
                  : 'Pídele a un administrador que cree o sincronice las plantillas de WhatsApp.'}
              </p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {plantillasWhatsApp.map((p) => {
                const estado = ESTADOS_META[p.estado_meta] ?? ESTADOS_META.borrador;
                const IconoEstado = estado.icono;
                return (
                  <div
                    key={p.id}
                    className="flex flex-col justify-between rounded-xl border border-border/70 bg-card p-4 shadow-2xs hover:shadow-sm transition-all"
                  >
                    <div>
                      {/* Cabecera de la tarjeta */}
                      <div className="flex items-start justify-between gap-2 border-b border-border/40 pb-3">
                        <div className="min-w-0">
                          <h3 className="font-semibold text-sm truncate text-foreground">{p.nombre}</h3>
                          <div className="mt-1 flex flex-wrap items-center gap-1.5">
                            {p.nombre_meta && (
                              <code className="text-[11px] rounded-md bg-muted px-1.5 py-0.5 font-mono text-muted-foreground">
                                {p.nombre_meta}
                              </code>
                            )}
                            <Badge variant="outline" className="capitalize text-[11px] rounded-md">
                              {p.categoria}
                            </Badge>
                            <Badge
                              variant="outline"
                              className="text-[11px] rounded-md"
                              title="La cuenta de WhatsApp donde vive: solo sale por esta línea"
                            >
                              {nombreDeLinea(p.wa_phone_number_id) ??
                                (p.wa_phone_number_id ? 'Línea desconectada' : 'Sin línea')}
                            </Badge>
                          </div>
                        </div>

                        {puedeEditar && (
                          <div className="flex items-center gap-1 shrink-0">
                            <Button
                              size="icon-xs"
                              variant="ghost"
                              className="rounded-lg"
                              onClick={() => abrir(p)}
                              title="Editar plantilla"
                            >
                              <Pencil className="size-3.5" />
                            </Button>
                            <Button
                              size="icon-xs"
                              variant="ghost"
                              className="rounded-lg text-muted-foreground hover:text-destructive hover:bg-destructive/10"
                              onClick={() => archivar(p.id)}
                              disabled={pendiente}
                              title="Archivar plantilla"
                            >
                              <Archive className="size-3.5" />
                            </Button>
                          </div>
                        )}
                      </div>

                      {/* Estado de Meta */}
                      <div className="mt-3 flex items-center justify-between gap-2">
                        <span
                          className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-semibold ${estado.estilo}`}
                          title={estado.ayuda}
                        >
                          <IconoEstado className="size-3 shrink-0" />
                          {estado.texto}
                        </span>

                        {p.estado_meta === 'borrador' && puedeEditar && (
                          <Button
                            size="xs"
                            variant="outline"
                            className="h-7 text-xs gap-1 rounded-lg text-primary border-primary/40 hover:bg-primary/10"
                            onClick={() => handleEnviarAMeta(p)}
                            disabled={pendiente}
                          >
                            <Send className="size-3" />
                            Mandar a Meta
                          </Button>
                        )}
                      </div>

                      {/* Motivo de rechazo si aplica */}
                      {p.estado_meta === 'rechazada' && p.motivo_rechazo_meta && (
                        <div className="mt-2.5 rounded-xl border border-destructive/30 bg-destructive/10 p-2.5 text-xs text-destructive">
                          <p className="font-semibold flex items-center gap-1">
                            <AlertTriangle className="size-3" /> Motivo de rechazo de Meta:
                          </p>
                          <p className="mt-0.5">{p.motivo_rechazo_meta}</p>
                        </div>
                      )}

                      {/* Simulador visual de burbuja de WhatsApp */}
                      <div className="mt-3.5 rounded-xl bg-[#efeae2] dark:bg-[#0b141a] p-3 border border-border/40 shadow-inner">
                        <div className="max-w-[90%] rounded-xl rounded-tl-xs bg-white dark:bg-[#202c33] p-2.5 shadow-xs text-xs text-foreground space-y-1">
                          <p className="whitespace-pre-wrap leading-relaxed">{previsualizar(p.cuerpo)}</p>
                          <div className="flex items-center justify-end gap-1 text-[11px] text-muted-foreground/70">
                            <span>10:30 a.m.</span>
                            <span className="text-emerald-600 font-bold">✓✓</span>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}

      {/* ============================================================== */}
      {/* VISTA 2: RESPUESTAS RÁPIDAS DE CHAT (INTERNAS)                 */}
      {/* ============================================================== */}
      {tabActiva === 'chat' && (
        <div className="flex flex-col gap-4">
          <div className="flex items-start gap-2.5 rounded-xl border border-border/60 bg-muted/20 p-3.5 text-xs text-muted-foreground">
            <Sparkles className="size-4 shrink-0 text-amber-500 mt-0.5" />
            <div>
              <p className="font-semibold text-foreground">Respuestas rápidas para el chat del día a día</p>
              <p className="mt-0.5 leading-relaxed">
                Mensajes guardados para responder preguntas comunes en un clic durante la conversación activa
                (dentro de la ventana de 24 horas). Están disponibles de inmediato y no requieren trámite de Meta.
              </p>
            </div>
          </div>

          {plantillasChat.length === 0 ? (
            <div className="rounded-xl border border-dashed border-border/80 py-16 text-center bg-card/40">
              <MessageSquare className="mx-auto size-8 text-muted-foreground/60 mb-2" />
              <p className="font-semibold text-foreground">Todavía no hay respuestas rápidas de chat</p>
              <p className="text-xs text-muted-foreground mt-1 max-w-sm mx-auto">
                Crea respuestas predefinidas para que los asesores contesten preguntas de horarios, requisitos o precios con un solo toque.
              </p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {plantillasChat.map((p) => (
                <div
                  key={p.id}
                  className="flex flex-col justify-between rounded-xl border border-border/70 bg-card p-4 shadow-2xs hover:shadow-sm transition-all"
                >
                  <div>
                    <div className="flex items-start justify-between gap-2 border-b border-border/40 pb-2.5">
                      <div>
                        <h3 className="font-semibold text-sm text-foreground">{p.nombre}</h3>
                        <Badge variant="secondary" className="capitalize text-[11px] mt-1">
                          {p.categoria}
                        </Badge>
                      </div>

                      {puedeEditar && (
                        <div className="flex items-center gap-1">
                          <Button
                            size="icon-xs"
                            variant="ghost"
                            className="rounded-lg"
                            onClick={() => abrir(p)}
                            title="Editar respuesta"
                          >
                            <Pencil className="size-3.5" />
                          </Button>
                          <Button
                            size="icon-xs"
                            variant="ghost"
                            className="rounded-lg text-muted-foreground hover:text-destructive hover:bg-destructive/10"
                            onClick={() => archivar(p.id)}
                            disabled={pendiente}
                            title="Archivar"
                          >
                            <Archive className="size-3.5" />
                          </Button>
                        </div>
                      )}
                    </div>

                    <p className="mt-3 whitespace-pre-wrap rounded-xl bg-muted/40 p-3 text-xs text-foreground/90 border border-border/40">
                      {p.cuerpo}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* ============================================================== */}
      {/* DIÁLOGO MODAL: CREAR / EDITAR SEGÚN EL TIPO                   */}
      {/* ============================================================== */}
      <Dialog open={editando !== null} onOpenChange={(o) => !o && setEditando(null)}>
        <DialogContent className="sm:max-w-xl max-h-[90vh] overflow-y-auto rounded-xl">
          <DialogHeader>
            <DialogTitle>
              {editando === 'nueva-whatsapp' && 'Nueva plantilla de WhatsApp'}
              {editando === 'nueva-chat' && 'Nueva respuesta rápida de chat'}
              {typeof editando === 'object' &&
                editando?.tipo === 'chat' &&
                'Editar respuesta rápida'}
              {typeof editando === 'object' &&
                editando?.tipo !== 'chat' &&
                'Editar plantilla de WhatsApp'}
            </DialogTitle>
            <DialogDescription className="text-xs">
              {editando === 'nueva-whatsapp' || (typeof editando === 'object' && editando?.tipo !== 'chat')
                ? 'Las plantillas de WhatsApp son revisadas por Meta. Usa variables con nombre entre llaves dobles.'
                : 'Esta respuesta rápida estará disponible de inmediato en la caja de redactar para conversaciones activas.'}
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-4 py-2">
            {bloqueada && (
              <div className="flex items-start gap-2 rounded-xl border border-blue-500/30 bg-blue-500/10 p-2.5 text-xs text-blue-900 dark:text-blue-300">
                <Info className="mt-0.5 size-3.5 shrink-0" />
                <span>
                  Esta plantilla ya está en Meta. Solo se puede cambiar el título: el texto, la categoría y la línea
                  son los que Meta revisó. Para cambiar el texto, crea una nueva.
                </span>
              </div>
            )}

            {/* Nombre descriptivo */}
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="nombre-plantilla" className="text-xs font-semibold">
                Título descriptivo
              </Label>
              <Input
                id="nombre-plantilla"
                value={nombre}
                onChange={(ev) => handleNombreChange(ev.target.value)}
                placeholder={
                  editando === 'nueva-chat' || (typeof editando === 'object' && editando?.tipo === 'chat')
                    ? 'Ej: Horarios de atención'
                    : 'Ej: Reactivación de clientes dormidos'
                }
                disabled={pendiente}
                className="rounded-xl h-9 text-sm"
              />
            </div>

            {/* Nombre técnico de Meta (Solo si es WhatsApp) */}
            {(editando === 'nueva-whatsapp' ||
              (typeof editando === 'object' && editando?.tipo !== 'chat')) && (
              <div className="flex flex-col gap-1.5">
                <div className="flex items-center justify-between">
                  <Label htmlFor="nombre-meta" className="text-xs font-semibold">
                    Nombre técnico en Meta (snake_case)
                  </Label>
                  <span className="text-[11px] text-muted-foreground">Solo minúsculas y guiones bajos</span>
                </div>
                <Input
                  id="nombre-meta"
                  value={nombreMeta}
                  onChange={(ev) => setNombreMeta(ev.target.value.toLowerCase().replace(/[^a-z0-9_]/g, '_'))}
                  placeholder="reactivacion_clientes_dormidos"
                  disabled={pendiente || bloqueada}
                  className="rounded-xl h-9 text-xs font-mono"
                />
              </div>
            )}

            {/* Línea: la cuenta de WhatsApp donde va a vivir (solo WhatsApp) */}
            {(editando === 'nueva-whatsapp' ||
              (typeof editando === 'object' && editando?.tipo !== 'chat')) && (
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="linea-plantilla" className="text-xs font-semibold">
                  Línea
                </Label>
                {lineas.length === 0 ? (
                  <p className="rounded-xl border border-dashed p-2.5 text-[11px] text-muted-foreground">
                    Todavía no hay líneas conectadas. Puedes guardarla como borrador y elegir la línea cuando se
                    conecte una.
                  </p>
                ) : (
                  <select
                    id="linea-plantilla"
                    value={linea}
                    onChange={(ev) => setLinea(ev.target.value)}
                    disabled={pendiente || bloqueada}
                    className="h-8 rounded-lg border border-input bg-background px-3 text-xs"
                  >
                    {linea === '' && <option value="">Sin línea</option>}
                    {lineas.map((l) => (
                      <option key={l.wa_phone_number_id} value={l.wa_phone_number_id}>
                        {l.nombre}
                      </option>
                    ))}
                  </select>
                )}
                <span className="text-[11px] text-muted-foreground">
                  Meta la guarda en la cuenta de WhatsApp de esa línea: por otra no sale.
                </span>
              </div>
            )}

            {/* Categoría */}
            <div className="flex flex-col gap-1.5">
              <Label className="text-xs font-semibold">Categoría</Label>
              {editando === 'nueva-chat' || (typeof editando === 'object' && editando?.tipo === 'chat') ? (
                <div className="flex flex-wrap gap-1.5">
                  {['general', 'arrendamiento', 'visitas', 'ventas'].map((cat) => (
                    <button
                      key={cat}
                      type="button"
                      onClick={() => setCategoria(cat)}
                      className={`rounded-xl border px-3 py-1.5 text-xs font-medium capitalize transition-all ${
                        categoria === cat
                          ? 'bg-primary text-primary-foreground border-primary shadow-xs'
                          : 'bg-card text-muted-foreground hover:bg-muted'
                      }`}
                    >
                      {cat}
                    </button>
                  ))}
                </div>
              ) : (
                <div className="grid grid-cols-2 gap-2">
                  <button
                    type="button"
                    disabled={bloqueada}
                    onClick={() => setCategoria('utilidad')}
                    className={`flex flex-col items-start rounded-xl border p-2.5 text-left transition-all ${
                      categoria === 'utilidad'
                        ? 'border-primary bg-primary/5 text-foreground ring-1 ring-primary'
                        : 'border-border/60 hover:bg-muted/40 text-muted-foreground'
                    }`}
                  >
                    <span className="font-semibold text-xs text-foreground">Utilidad</span>
                    <span className="text-[11px] mt-0.5 opacity-80">
                      Confirmaciones, estados de solicitud o seguimiento pedido por el cliente.
                    </span>
                  </button>

                  <button
                    type="button"
                    disabled={bloqueada}
                    onClick={() => setCategoria('marketing')}
                    className={`flex flex-col items-start rounded-xl border p-2.5 text-left transition-all ${
                      categoria === 'marketing'
                        ? 'border-primary bg-primary/5 text-foreground ring-1 ring-primary'
                        : 'border-border/60 hover:bg-muted/40 text-muted-foreground'
                    }`}
                  >
                    <span className="font-semibold text-xs text-foreground">Marketing</span>
                    <span className="text-[11px] mt-0.5 opacity-80">
                      Reactivaciones, promociones, reenganche y recomendaciones de catálogo.
                    </span>
                  </button>
                </div>
              )}
            </div>

            {/* Mensaje / Cuerpo */}
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="cuerpo-plantilla" className="text-xs font-semibold">
                Cuerpo del mensaje
              </Label>
              <Textarea
                id="cuerpo-plantilla"
                value={cuerpo}
                onChange={(ev) => setCuerpo(ev.target.value)}
                rows={5}
                placeholder="Hola {{nombre}}, le escribe {{asesor}} de Inmobiliaria Cumbres…"
                disabled={pendiente || bloqueada}
                className="rounded-xl text-xs leading-relaxed"
              />

              <div className="flex flex-wrap items-center gap-1 text-[11px] text-muted-foreground pt-1">
                <span>Variables:</span>
                {variables.map((v) => (
                  <button
                    key={v}
                    type="button"
                    disabled={bloqueada}
                    onClick={() => setCuerpo((prev) => `${prev} {{${v}}}`)}
                    className="rounded bg-muted/80 px-1.5 py-0.5 font-mono text-[11px] hover:bg-primary/20 hover:text-primary transition-colors"
                    title="Clic para insertar"
                  >
                    {`{{${v}}}`}
                  </button>
                ))}
              </div>
            </div>

            {/* Previsualización en vivo tipo WhatsApp */}
            {cuerpo.trim() && (
              <div className="flex flex-col gap-1 rounded-xl bg-[#efeae2] dark:bg-[#0b141a] p-3 border border-border/40">
                <span className="text-[11px] font-semibold text-muted-foreground">
                  Previsualización en WhatsApp
                </span>
                <div className="rounded-xl rounded-tl-xs bg-white dark:bg-[#202c33] p-2.5 shadow-xs text-xs text-foreground space-y-1">
                  <p className="whitespace-pre-wrap">{previsualizar(cuerpo)}</p>
                  <div className="flex items-center justify-end gap-1 text-[11px] text-muted-foreground/70">
                    <span>10:30 a.m.</span>
                    <span className="text-emerald-600 font-bold">✓✓</span>
                  </div>
                </div>
              </div>
            )}
          </div>

          <DialogFooter className="gap-2 sm:gap-0">
            <Button variant="outline" className="rounded-xl" onClick={() => setEditando(null)}>
              Cancelar
            </Button>

            {/* Si es WhatsApp, opción de guardar o guardar y enviar a Meta */}
            {bloqueada ? (
              <Button
                className="rounded-xl"
                onClick={() => guardar(false)}
                disabled={pendiente || !nombre.trim()}
              >
                {pendiente && <Loader2 className="size-3.5 animate-spin mr-1" />}
                Guardar título
              </Button>
            ) : (editando === 'nueva-whatsapp' ||
              (typeof editando === 'object' && editando?.tipo !== 'chat')) ? (
              <div className="flex items-center gap-2">
                <Button
                  variant="outline"
                  className="rounded-xl"
                  onClick={() => guardar(false)}
                  disabled={pendiente || !nombre.trim() || !cuerpo.trim()}
                >
                  Guardar borrador
                </Button>
                <Button
                  className="rounded-lg gap-1.5"
                  onClick={() => guardar(true)}
                  disabled={pendiente || !nombre.trim() || !cuerpo.trim() || !linea}
                  title={linea ? undefined : 'Hace falta una línea conectada para mandarla a Meta'}
                >
                  {pendiente ? <Loader2 className="size-3.5 animate-spin" /> : <Send className="size-3.5" />}
                  Mandar a Meta
                </Button>
              </div>
            ) : (
              <Button
                className="rounded-xl"
                onClick={() => guardar(false)}
                disabled={pendiente || !nombre.trim() || !cuerpo.trim()}
              >
                {pendiente && <Loader2 className="size-3.5 animate-spin mr-1" />}
                Guardar respuesta
              </Button>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
