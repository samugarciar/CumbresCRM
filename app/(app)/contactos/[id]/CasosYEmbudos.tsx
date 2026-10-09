'use client';

import { useState, useTransition } from 'react';
import { FilePlus, Loader2, Sparkles } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import {
  convertirACaptacion,
  abrirCasoAdministrativo,
  cambiarEtapaOportunidad,
} from './acciones';

export interface OportunidadContacto {
  id: string;
  embudo: string;
  etapa: string;
  estado: string;
  updated_at: string;
}

export interface EtapaConfig {
  codigo: string;
  etiqueta: string;
  embudo: string;
  orden: number;
}

interface Props {
  contactoId: string;
  oportunidades: OportunidadContacto[];
  etapas: EtapaConfig[];
}

const NOMBRES_EMBUDO: Record<string, string> = {
  comercial: 'Comercial',
  administrativa: 'Administrativa',
  captacion: 'Captación',
};

const VARIANTES_BADGE: Record<string, 'default' | 'secondary' | 'outline'> = {
  comercial: 'default',
  administrativa: 'secondary',
  captacion: 'outline',
};

export function CasosYEmbudos({ contactoId, oportunidades, etapas }: Props) {
  const [pendiente, iniciar] = useTransition();
  const [error, setError] = useState<string | null>(null);

  const casoAdmin = oportunidades.find(
    (o) => o.embudo === 'administrativa' && o.estado === 'abierta',
  );

  const handleConvertirCaptacion = () => {
    setError(null);
    iniciar(async () => {
      const res = await convertirACaptacion(contactoId);
      if (!res.ok) {
        setError(res.error ?? 'No se pudo convertir a captación.');
      }
    });
  };

  const handleAbrirAdmin = () => {
    setError(null);
    iniciar(async () => {
      const res = await abrirCasoAdministrativo(contactoId);
      if (!res.ok) {
        setError(res.error ?? 'No se pudo abrir el caso administrativo.');
      }
    });
  };

  const handleCambiarEtapa = (oportunidadId: string, nuevaEtapa: string) => {
    setError(null);
    iniciar(async () => {
      const res = await cambiarEtapaOportunidad(oportunidadId, nuevaEtapa, contactoId);
      if (!res.ok) {
        setError(res.error ?? 'No se pudo cambiar de etapa.');
      }
    });
  };

  return (
    <section className="flex flex-col gap-4 rounded-lg border bg-card p-4">
      <div className="flex items-center justify-between">
        <h2 className="font-medium flex items-center gap-2">
          <span>Embudos y Casos</span>
        </h2>
        {!casoAdmin && (
          <Button
            variant="outline"
            size="sm"
            onClick={handleAbrirAdmin}
            disabled={pendiente}
            className="h-8 gap-1 text-xs"
          >
            {pendiente ? (
              <Loader2 className="size-3.5 animate-spin" />
            ) : (
              <FilePlus className="size-3.5" />
            )}
            Abrir caso administrativo
          </Button>
        )}
      </div>

      {oportunidades.length === 0 ? (
        <p className="text-xs text-muted-foreground">
          No tiene oportunidades o casos abiertos actualmente.
        </p>
      ) : (
        <div className="flex flex-col gap-3">
          {oportunidades.map((op) => {
            const etapasDelEmbudo = etapas.filter((e) => e.embudo === op.embudo);
            const etapaActual = etapasDelEmbudo.find((e) => e.codigo === op.etapa);
            const esAdmin = op.embudo === 'administrativa';

            return (
              <div
                key={op.id}
                className="flex flex-col gap-2 rounded-md border bg-muted/30 p-3"
              >
                <div className="flex items-center justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <Badge variant={VARIANTES_BADGE[op.embudo] ?? 'default'} className="text-xs">
                      {NOMBRES_EMBUDO[op.embudo] ?? op.embudo}
                    </Badge>
                    <span className="text-xs text-muted-foreground">
                      {etapaActual?.etiqueta ?? op.etapa}
                    </span>
                  </div>

                  {esAdmin && (
                    <Button
                      variant="secondary"
                      size="sm"
                      onClick={handleConvertirCaptacion}
                      disabled={pendiente}
                      className="h-7 gap-1 text-xs font-medium bg-amber-500/10 text-amber-600 hover:bg-amber-500/20 border border-amber-500/30"
                      title="Cierra el caso administrativo, abre prospecto de captación y cambia contacto a propietario"
                    >
                      {pendiente ? (
                        <Loader2 className="size-3 animate-spin" />
                      ) : (
                        <Sparkles className="size-3" />
                      )}
                      Es una captación
                    </Button>
                  )}
                </div>

                {/* Selector de etapa para mover caso a mano */}
                <div className="flex items-center gap-2 pt-1">
                  <label htmlFor={`etapa-${op.id}`} className="text-xs text-muted-foreground whitespace-nowrap">
                    Cambiar estado:
                  </label>
                  <select
                    id={`etapa-${op.id}`}
                    value={op.etapa}
                    onChange={(e) => handleCambiarEtapa(op.id, e.target.value)}
                    disabled={pendiente}
                    className="h-8 w-full rounded-md border bg-background px-2 text-xs"
                  >
                    {etapasDelEmbudo.map((e) => (
                      <option key={e.codigo} value={e.codigo}>
                        {e.etiqueta}
                      </option>
                    ))}
                  </select>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {error && (
        <p role="alert" className="text-xs text-destructive">
          {error}
        </p>
      )}
    </section>
  );
}
