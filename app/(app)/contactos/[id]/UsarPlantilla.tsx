'use client';

import { useState, useTransition } from 'react';
import {
  Check,
  Copy,
  Loader2,
  MessageSquareText,
  TriangleAlert,
  MessageCircle,
  MessageSquare,
  ShieldAlert,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { renderizar } from './acciones';
import { VentanaWhatsApp } from './VentanaWhatsApp';

export interface PlantillaResumen {
  id: string;
  nombre: string;
  categoria: string;
  tipo?: string;
  estado_meta?: string;
}

/**
 * Elegir una plantilla o respuesta rápida, verla rellena con los datos de ESTA persona,
 * y copiarla o insertarla en el mensaje.
 *
 * Si la ventana de 24h está cerrada, por política de Meta SOLO se permite enviar
 * plantillas oficiales de WhatsApp aprobadas (HSM).
 */
export function UsarPlantilla({
  plantillas,
  contactoId,
  inmuebleId = null,
  etiqueta = 'Plantillas y Respuestas',
  asesor,
  ventanaCierraAt = null,
  ahora,
}: {
  plantillas: PlantillaResumen[];
  contactoId: string;
  inmuebleId?: string | null;
  etiqueta?: string;
  asesor: string | null;
  ventanaCierraAt?: string | null;
  ahora: string;
}) {
  const [abierto, setAbierto] = useState(false);
  const [elegida, setElegida] = useState<PlantillaResumen | null>(null);
  const [texto, setTexto] = useState('');
  const [copiado, setCopiado] = useState(false);
  const [pendiente, startTransition] = useTransition();

  const ventanaAbierta = Boolean(
    ventanaCierraAt && new Date(ventanaCierraAt).getTime() > new Date(ahora).getTime()
  );

  const [tabTipo, setTabTipo] = useState<'whatsapp' | 'chat'>(
    ventanaAbierta ? 'chat' : 'whatsapp'
  );

  if (plantillas.length === 0) return null;

  const plantillasWhatsApp = plantillas.filter((p) => p.tipo !== 'chat');
  const plantillasChat = plantillas.filter((p) => p.tipo === 'chat');

  function elegir(p: PlantillaResumen) {
    setElegida(p);
    setCopiado(false);
    startTransition(async () => {
      const r = await renderizar(p.id, contactoId, inmuebleId, asesor);
      setTexto(r ?? '');
    });
  }

  async function copiar() {
    try {
      await navigator.clipboard.writeText(texto);
      setCopiado(true);
      setTimeout(() => setCopiado(false), 2000);
    } catch {
      // Sin permiso de portapapeles el texto sigue ahí para seleccionarlo.
    }
  }

  const huecos = texto.match(/\[sin [^\]]+\]|\[asesor\]/g);

  return (
    <>
      <Button
        size="sm"
        variant="outline"
        className="h-9 gap-1.5 rounded-xl text-xs font-semibold shadow-2xs"
        onClick={() => {
          setAbierto(true);
          setElegida(null);
          setTexto('');
          // Si la ventana está cerrada, forzar pestaña WhatsApp
          setTabTipo(ventanaAbierta ? 'chat' : 'whatsapp');
        }}
      >
        <MessageSquareText className="size-3.5" />
        {etiqueta}
      </Button>

      <Dialog open={abierto} onOpenChange={setAbierto}>
        <DialogContent className="sm:max-w-xl max-h-[90vh] overflow-y-auto rounded-2xl">
          <DialogHeader>
            <DialogTitle>
              {elegida ? elegida.nombre : 'Elige una plantilla o respuesta'}
            </DialogTitle>
            <DialogDescription className="text-xs">
              {elegida
                ? 'Así queda con los datos de esta persona. Puedes editar el texto antes de copiarlo.'
                : 'Selecciona una respuesta rápida para el chat diario o una plantilla oficial de WhatsApp.'}
            </DialogDescription>
          </DialogHeader>

          {!elegida ? (
            <div className="flex flex-col gap-3 py-1">
              {/* Selector de tipo */}
              <div className="flex items-center gap-1.5 rounded-xl bg-muted/40 p-1 border border-border/50">
                <button
                  type="button"
                  onClick={() => setTabTipo('whatsapp')}
                  className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg px-3 py-2 text-xs font-semibold transition-all ${
                    tabTipo === 'whatsapp'
                      ? 'bg-background text-foreground shadow-xs'
                      : 'text-muted-foreground hover:text-foreground'
                  }`}
                >
                  <MessageCircle className="size-3.5 text-emerald-600 dark:text-emerald-400" />
                  <span>WhatsApp (Meta HSM)</span>
                  <span className="rounded-full bg-primary/10 px-1.5 py-0.2 text-[10px] tabular">
                    {plantillasWhatsApp.length}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setTabTipo('chat')}
                  className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg px-3 py-2 text-xs font-semibold transition-all ${
                    tabTipo === 'chat'
                      ? 'bg-background text-foreground shadow-xs'
                      : 'text-muted-foreground hover:text-foreground'
                  }`}
                >
                  <MessageSquare className="size-3.5 text-blue-600 dark:text-blue-400" />
                  <span>Respuestas Rápidas</span>
                  <span className="rounded-full bg-muted px-1.5 py-0.2 text-[10px] tabular">
                    {plantillasChat.length}
                  </span>
                </button>
              </div>

              {/* Advertencia de ventana cerrada si intenta ver chat libre */}
              {!ventanaAbierta && tabTipo === 'chat' && (
                <div className="flex items-start gap-2 rounded-xl border border-amber-500/30 bg-amber-500/10 p-3 text-xs text-amber-900 dark:text-amber-300">
                  <ShieldAlert className="size-4 shrink-0 mt-0.5" />
                  <div>
                    <span className="font-semibold">Ventana de 24h cerrada:</span>
                    <p className="mt-0.5 leading-relaxed">
                      Por política de Meta, los mensajes de texto libre serán rechazados (error 131047). Para abrir conversación, usa una{' '}
                      <button
                        type="button"
                        onClick={() => setTabTipo('whatsapp')}
                        className="font-bold underline"
                      >
                        Plantilla de WhatsApp aprobada
                      </button>
                      .
                    </p>
                  </div>
                </div>
              )}

              {/* Lista de plantillas según la pestaña elegida */}
              <div className="flex flex-col gap-1.5 max-h-72 overflow-y-auto pr-1">
                {tabTipo === 'whatsapp' ? (
                  plantillasWhatsApp.length === 0 ? (
                    <p className="rounded-xl border border-dashed py-8 text-center text-xs text-muted-foreground">
                      No hay plantillas de WhatsApp registradas.
                    </p>
                  ) : (
                    plantillasWhatsApp.map((p) => {
                      const estaAprobada = p.estado_meta === 'aprobada';
                      return (
                        <button
                          key={p.id}
                          type="button"
                          onClick={() => elegir(p)}
                          className="flex w-full items-center justify-between gap-3 rounded-xl border border-border/60 bg-card p-3 text-left transition-all hover:bg-muted/40 hover:border-primary/40"
                        >
                          <div className="min-w-0">
                            <span className="block font-medium text-xs text-foreground truncate">
                              {p.nombre}
                            </span>
                            <span className="text-[11px] text-muted-foreground capitalize">
                              {p.categoria}
                            </span>
                          </div>
                          <Badge
                            variant={estaAprobada ? 'secondary' : 'outline'}
                            className={`text-[10px] rounded-md ${
                              estaAprobada
                                ? 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 border-emerald-300'
                                : 'text-muted-foreground'
                            }`}
                          >
                            {estaAprobada ? 'Aprobada' : p.estado_meta ?? 'Borrador'}
                          </Badge>
                        </button>
                      );
                    })
                  )
                ) : (
                  plantillasChat.length === 0 ? (
                    <p className="rounded-xl border border-dashed py-8 text-center text-xs text-muted-foreground">
                      No hay respuestas rápidas de chat.
                    </p>
                  ) : (
                    plantillasChat.map((p) => (
                      <button
                        key={p.id}
                        type="button"
                        onClick={() => elegir(p)}
                        className="flex w-full items-center justify-between gap-3 rounded-xl border border-border/60 bg-card p-3 text-left transition-all hover:bg-muted/40 hover:border-primary/40"
                      >
                        <div className="min-w-0">
                          <span className="block font-medium text-xs text-foreground truncate">
                            {p.nombre}
                          </span>
                          <span className="text-[11px] text-muted-foreground capitalize">
                            {p.categoria}
                          </span>
                        </div>
                      </button>
                    ))
                  )
                )}
              </div>
            </div>
          ) : (
            <div className="flex flex-col gap-3 py-1">
              {pendiente ? (
                <div className="flex items-center justify-center gap-2 py-12 text-xs text-muted-foreground">
                  <Loader2 className="size-4 animate-spin text-primary" />
                  Rellenando con datos del contacto…
                </div>
              ) : (
                <>
                  <Textarea
                    value={texto}
                    onChange={(e) => setTexto(e.target.value)}
                    rows={8}
                    aria-label="Mensaje"
                    className="rounded-xl text-xs leading-relaxed"
                  />
                  {huecos && (
                    <div className="flex items-start gap-1.5 rounded-xl border border-amber-500/30 bg-amber-500/10 p-2.5 text-xs text-amber-800 dark:text-amber-300">
                      <TriangleAlert className="mt-0.5 size-3.5 shrink-0" />
                      <span>Faltan datos por completar: {huecos.join(', ')}. Rellénalos antes de enviar.</span>
                    </div>
                  )}
                </>
              )}
            </div>
          )}

          {elegida && !pendiente && (
            <VentanaWhatsApp cierraAt={ventanaCierraAt} ahora={ahora} compacto />
          )}

          <DialogFooter className="gap-2 sm:gap-0">
            {elegida && (
              <Button
                variant="outline"
                className="rounded-xl text-xs"
                onClick={() => setElegida(null)}
              >
                Elegir otra
              </Button>
            )}
            <Button
              className="rounded-xl text-xs gap-1.5 font-semibold"
              onClick={copiar}
              disabled={!elegida || pendiente || !texto}
            >
              {copiado ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
              {copiado ? '¡Copiado al portapapeles!' : 'Copiar mensaje'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
