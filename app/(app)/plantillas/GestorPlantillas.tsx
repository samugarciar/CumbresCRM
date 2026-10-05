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
  puedeEditar,
}: {
  plantillas: Plantilla[];
  variables: string[];
  puedeEditar: boolean;
}) {
  const [tabActiva, setTabActiva] = useState<'whatsapp' | 'chat'>('whatsapp');
  const [editando, setEditando] = useState<Plantilla | 'nueva-whatsapp' | 'nueva-chat' | null>(null);
  const [nombre, setNombre] = useState('');
  const [nombreMeta, setNombreMeta] = useState('');
  const [cuerpo, setCuerpo] = useState('');
  const [categoria, setCategoria] = useState('utilidad');
  const [idioma, setIdioma] = useState('es');
  const [error, setError] = useState<string | null>(null);
  const [mensajeSync, setMensajeSync] = useState<string | null>(null);
  const [pendiente, startTransition] = useTransition();

  const plantillasWhatsApp = plantillas.filter((p) => p.tipo !== 'chat');
  const plantillasChat = plantillas.filter((p) => p.tipo === 'chat');

  function abrir(p: Plantilla | 'nueva-whatsapp' | 'nueva-chat') {
    setEditando(p);
    setError(null);
    if (typeof p === 'string') {
      setNombre('');
      setNombreMeta('');
      setCuerpo('');
      setCategoria(p === 'nueva-whatsapp' ? 'utilidad' : 'general');
      setIdioma('es');
    } else {
      setNombre(p.nombre);
      setNombreMeta(p.nombre_meta ?? '');
      setCuerpo(p.cuerpo);
      setCategoria(p.categoria);
      setIdioma(p.idioma ?? 'es');
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
        idioma
      );

      if (!r.ok) {
        setError(r.error ?? 'No se pudo guardar la plantilla.');
        return;
      }

      // Si además pidió enviar a revisión a Meta
      if (enviarDirectoAMeta && tipoPlantilla === 'whatsapp') {
        const idAEnviar = typeof editando === 'object' && editando ? editando.id : null;
        if (idAEnviar) {
          const rMeta = await enviarAMeta(idAEnviar);
          if (!rMeta.ok) {
            setError(`Guardada como borrador, pero Meta la rechazó: ${rMeta.error}`);
            return;
          }
        }
      }

      setEditando(null);
    });
  }

  function handleEnviarAMeta(id: string) {
    setError(null);
    startTransition(async () => {
      const r = await enviarAMeta(id);
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

  // Previsualización de texto reemplazando variables dinámicas por datos simulados
  function previsualizar(c: string) {
    return c
      .replace(/\{\{\s*nombre\s*\}\}/g, 'María Restrepo')
      .replace(/\{\{\s*asesor\s*\}\}/g, 'Alejandro Rojas')
      .replace(/\{\{\s*inmueble\s*\}\}/g, 'Apto Poblado 401')
      .replace(/\{\{\s*precio\s*\}\}/g, '$2.800.000')
      .replace(/\{\{\s*habitaciones\s*\}\}/g, '3')
      .replace(/\{\{\s*banos\s*\}\}/g, '2')
      .replace(/\{\{\s*barrio\s*\}\}/g, 'El Poblado')
      .replace(/\{\{\s*ciudad\s*\}\}/g, 'Medellín');
  }

  return (
    <div className="flex flex-col gap-5">
      {/* Pestañas ergonómicas de selección */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border/60 pb-3">
        <div className="flex items-center gap-2 rounded-2xl bg-muted/40 p-1 border border-border/50">
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
            <span>Plantillas de WhatsApp (Meta HSM)</span>
            <span className="rounded-full bg-primary/10 px-2 py-0.2 text-[10px] font-bold tabular text-primary">
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
            <span>Respuestas Rápidas de Chat</span>
            <span className="rounded-full bg-muted px-2 py-0.2 text-[10px] font-bold tabular text-muted-foreground">
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
                  className="h-9 rounded-xl text-xs gap-1.5"
                  onClick={sincronizar}
                  disabled={pendiente}
                  title="Consulta la WABA de Meta y actualiza el estado de las plantillas"
                >
                  <RefreshCw className={`size-3.5 ${pendiente ? 'animate-spin' : ''}`} />
                  Sincronizar con Meta
                </Button>

                <Button
                  size="sm"
                  className="h-9 rounded-xl text-xs gap-1.5 bg-emerald-700 hover:bg-emerald-800 text-white shadow-xs"
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
                className="h-9 rounded-xl text-xs gap-1.5 shadow-xs"
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
              </p>
            </div>
          </div>

          {plantillasWhatsApp.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-border/80 py-16 text-center bg-card/40">
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
                    className="flex flex-col justify-between rounded-2xl border border-border/70 bg-card p-4 shadow-2xs hover:shadow-sm transition-all"
                  >
                    <div>
                      {/* Cabecera de la tarjeta */}
                      <div className="flex items-start justify-between gap-2 border-b border-border/40 pb-3">
                        <div className="min-w-0">
                          <h3 className="font-semibold text-sm truncate text-foreground">{p.nombre}</h3>
                          <div className="mt-1 flex flex-wrap items-center gap-1.5">
                            {p.nombre_meta && (
                              <code className="text-[10px] rounded-md bg-muted px-1.5 py-0.5 font-mono text-muted-foreground">
                                {p.nombre_meta}
                              </code>
                            )}
                            <Badge variant="outline" className="capitalize text-[10px] rounded-md">
                              {p.categoria}
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
                            onClick={() => handleEnviarAMeta(p.id)}
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
                          <div className="flex items-center justify-end gap-1 text-[10px] text-muted-foreground/70">
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
              <p className="font-semibold text-foreground">Respuestas Rápidas para el Chat Diario:</p>
              <p className="mt-0.5 leading-relaxed">
                Mensajes guardados para responder preguntas comunes en un clic durante la conversación activa
                (dentro de la ventana de 24 horas). Están disponibles de inmediato y no requieren trámite de Meta.
              </p>
            </div>
          </div>

          {plantillasChat.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-border/80 py-16 text-center bg-card/40">
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
                  className="flex flex-col justify-between rounded-2xl border border-border/70 bg-card p-4 shadow-2xs hover:shadow-sm transition-all"
                >
                  <div>
                    <div className="flex items-start justify-between gap-2 border-b border-border/40 pb-2.5">
                      <div>
                        <h3 className="font-semibold text-sm text-foreground">{p.nombre}</h3>
                        <Badge variant="secondary" className="capitalize text-[10px] mt-1">
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
        <DialogContent className="sm:max-w-xl max-h-[90vh] overflow-y-auto rounded-2xl">
          <DialogHeader>
            <DialogTitle>
              {editando === 'nueva-whatsapp' && 'Nueva Plantilla Oficial de WhatsApp (Meta HSM)'}
              {editando === 'nueva-chat' && 'Nueva Respuesta Rápida de Chat'}
              {typeof editando === 'object' &&
                editando?.tipo === 'chat' &&
                'Editar Respuesta Rápida'}
              {typeof editando === 'object' &&
                editando?.tipo !== 'chat' &&
                'Editar Plantilla de WhatsApp'}
            </DialogTitle>
            <DialogDescription className="text-xs">
              {editando === 'nueva-whatsapp' || (typeof editando === 'object' && editando?.tipo !== 'chat')
                ? 'Las plantillas de WhatsApp son revisadas por Meta. Usa variables con nombre entre llaves dobles.'
                : 'Esta respuesta rápida estará disponible de inmediato en la caja de redactar para conversaciones activas.'}
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-4 py-2">
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
                  disabled={pendiente}
                  className="rounded-xl h-9 text-xs font-mono"
                />
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
                disabled={pendiente}
                className="rounded-xl text-xs leading-relaxed"
              />

              <div className="flex flex-wrap items-center gap-1 text-[11px] text-muted-foreground pt-1">
                <span>Variables:</span>
                {variables.map((v) => (
                  <button
                    key={v}
                    type="button"
                    onClick={() => setCuerpo((prev) => `${prev} {{${v}}}`)}
                    className="rounded bg-muted/80 px-1.5 py-0.5 font-mono text-[10px] hover:bg-primary/20 hover:text-primary transition-colors"
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
                <span className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">
                  Previsualización en WhatsApp
                </span>
                <div className="rounded-xl rounded-tl-xs bg-white dark:bg-[#202c33] p-2.5 shadow-xs text-xs text-foreground space-y-1">
                  <p className="whitespace-pre-wrap">{previsualizar(cuerpo)}</p>
                  <div className="flex items-center justify-end gap-1 text-[10px] text-muted-foreground/70">
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
            {(editando === 'nueva-whatsapp' ||
              (typeof editando === 'object' && editando?.tipo !== 'chat')) ? (
              <div className="flex items-center gap-2">
                <Button
                  variant="outline"
                  className="rounded-xl"
                  onClick={() => guardar(false)}
                  disabled={pendiente || !nombre.trim() || !cuerpo.trim()}
                >
                  Guardar Borrador
                </Button>
                <Button
                  className="rounded-xl bg-emerald-700 hover:bg-emerald-800 text-white gap-1.5"
                  onClick={() => guardar(true)}
                  disabled={pendiente || !nombre.trim() || !cuerpo.trim()}
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
                Guardar Respuesta
              </Button>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
