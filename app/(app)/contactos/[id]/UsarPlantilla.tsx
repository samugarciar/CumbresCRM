'use client';

import { useState, useTransition } from 'react';
import { Check, Copy, Loader2, MessageSquareText, TriangleAlert } from 'lucide-react';
import { Button } from '@/components/ui/button';
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
}

/**
 * Elegir una plantilla, verla rellena con los datos de ESTA persona, y
 * copiarla.
 *
 * Se previsualiza siempre antes de copiar, y no es ceremonia: lo que
 * falta sale marcado como «[sin precio]» y el asesor lo ve antes de
 * pegarlo. Un hueco silencioso llega hasta el cliente.
 *
 * Copiar, no enviar — y eso es honesto mientras el mensaje salga del
 * teléfono del asesor. El botón de enviar aparece cuando exista el canal
 * propio (fase 5-B), no antes.
 */
export function UsarPlantilla({
  plantillas,
  contactoId,
  inmuebleId = null,
  etiqueta = 'Usar plantilla',
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

  if (plantillas.length === 0) return null;

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
        size="xs"
        variant="ghost"
        onClick={() => {
          setAbierto(true);
          setElegida(null);
          setTexto('');
        }}
      >
        <MessageSquareText className="size-3" />
        {etiqueta}
      </Button>

      <Dialog open={abierto} onOpenChange={setAbierto}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>
              {elegida ? elegida.nombre : 'Elige una plantilla'}
            </DialogTitle>
            <DialogDescription>
              {elegida
                ? 'Así queda con los datos de esta persona. Puedes editarlo antes de copiar.'
                : 'Se rellenan solas con el nombre, el inmueble y el precio.'}
            </DialogDescription>
          </DialogHeader>

          {!elegida ? (
            <ul className="flex flex-col gap-1.5">
              {plantillas.map((p) => (
                <li key={p.id}>
                  <button
                    type="button"
                    onClick={() => elegir(p)}
                    className="flex w-full items-center gap-2 rounded-lg border px-3 py-2 text-left text-sm transition-colors hover:bg-muted"
                  >
                    <span className="flex-1 font-medium">{p.nombre}</span>
                    <span className="text-xs capitalize text-muted-foreground">
                      {p.categoria}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          ) : (
            <div className="flex flex-col gap-2">
              {pendiente ? (
                <div className="flex items-center gap-2 py-6 text-sm text-muted-foreground">
                  <Loader2 className="size-4 animate-spin" />
                  Rellenando…
                </div>
              ) : (
                <>
                  <Textarea
                    value={texto}
                    onChange={(e) => setTexto(e.target.value)}
                    rows={9}
                    aria-label="Mensaje"
                  />
                  {/* Lo que falta se señala, no se esconde: es la última
                      oportunidad de verlo antes de que salga. */}
                  {huecos && (
                    <p className="flex items-start gap-1.5 text-xs text-warning">
                      <TriangleAlert className="mt-0.5 size-3.5 shrink-0" />
                      Faltan datos: {huecos.join(', ')}. Complétalos antes de mandarlo.
                    </p>
                  )}
                </>
              )}
            </div>
          )}

          {/* El estado de la ventana, pegado al botón de copiar: es el
              último momento en que sirve saberlo. */}
          {elegida && !pendiente && (
            <VentanaWhatsApp cierraAt={ventanaCierraAt} ahora={ahora} compacto />
          )}

          <DialogFooter>
            {elegida && (
              <Button variant="outline" onClick={() => setElegida(null)}>
                Otra plantilla
              </Button>
            )}
            <Button onClick={copiar} disabled={!elegida || pendiente || !texto}>
              {copiado ? <Check className="size-4" /> : <Copy className="size-4" />}
              {copiado ? 'Copiado' : 'Copiar'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
