'use client';

import { useState, useTransition } from 'react';
import {
  FilePlus,
  Loader2,
  Sparkles,
  Building2,
  Briefcase,
  KeyRound,
  CheckCircle2,
  Wrench,
  AlertTriangle,
  Handshake,
  FileCheck,
  DoorOpen,
  Camera,
  FileText,
  Clock,
  PhoneCall,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import {
  convertirACaptacion,
  abrirCasoAdministrativo,
  cambiarEtapaOportunidad,
  resolverCaso,
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

const INFO_ETAPAS_ADMIN: Record<string, { desc: string; icon: typeof Building2; color: string }> = {
  al_dia: {
    desc: 'Inquilino al día y sin novedades activas.',
    icon: CheckCircle2,
    color: 'text-emerald-600 dark:text-emerald-400 bg-emerald-500/10 border-emerald-500/20',
  },
  mantenimiento: {
    desc: 'Reportó un daño, avería o solicitud de reparación en el inmueble.',
    icon: Wrench,
    color: 'text-amber-600 dark:text-amber-400 bg-amber-500/10 border-amber-500/20',
  },
  en_mora: {
    desc: 'Canon o cuota de administración pendiente de pago.',
    icon: AlertTriangle,
    color: 'text-rose-600 dark:text-rose-400 bg-rose-500/10 border-rose-500/20',
  },
  acuerdo_de_pago: {
    desc: 'Compromiso o acuerdo de cuotas pactado con el inquilino.',
    icon: Handshake,
    color: 'text-indigo-600 dark:text-indigo-400 bg-indigo-500/10 border-indigo-500/20',
  },
  en_renovacion: {
    desc: 'En trámite de renovación o ajuste de contrato de arrendamiento.',
    icon: FileCheck,
    color: 'text-blue-600 dark:text-blue-400 bg-blue-500/10 border-blue-500/20',
  },
  en_terminacion: {
    desc: 'Fin de contrato, entrega física del inmueble y finiquito.',
    icon: DoorOpen,
    color: 'text-purple-600 dark:text-purple-400 bg-purple-500/10 border-purple-500/20',
  },
};

const INFO_ETAPAS_CAPTACION: Record<string, { desc: string; icon: typeof Building2; color: string }> = {
  prospecto: {
    desc: 'Propietario interesado en consignar su propiedad con Cumbres.',
    icon: Clock,
    color: 'text-emerald-600 dark:text-emerald-400 bg-emerald-500/10 border-emerald-500/20',
  },
  propietario_contactado: {
    desc: 'Primer contacto telefónico o por chat realizado con el propietario.',
    icon: PhoneCall,
    color: 'text-blue-600 dark:text-blue-400 bg-blue-500/10 border-blue-500/20',
  },
  visita_captacion: {
    desc: 'Visita técnica programada o realizada para registro fotográfico e inspección.',
    icon: Camera,
    color: 'text-sky-600 dark:text-sky-400 bg-sky-500/10 border-sky-500/20',
  },
  inmueble_verificado: {
    desc: 'Estudio de títulos, certificado de tradición y verificación jurídica al día.',
    icon: FileText,
    color: 'text-indigo-600 dark:text-indigo-400 bg-indigo-500/10 border-indigo-500/20',
  },
  por_aprobar: {
    desc: 'Propuesta de canon y contrato de corretaje en comité para publicación.',
    icon: FileCheck,
    color: 'text-amber-600 dark:text-amber-400 bg-amber-500/10 border-amber-500/20',
  },
  negociando: {
    desc: 'Definiendo comisión, canon y condiciones comerciales finales.',
    icon: Handshake,
    color: 'text-purple-600 dark:text-purple-400 bg-purple-500/10 border-purple-500/20',
  },
};

export function CasosYEmbudos({ contactoId, oportunidades, etapas }: Props) {
  const [pendiente, iniciar] = useTransition();
  const [error, setError] = useState<string | null>(null);

  // Filtrar oportunidades abiertas
  const abiertas = oportunidades.filter((o) => o.estado === 'abierta');

  // Si hay varias abiertas, permitir alternar entre ellas con pestañas limpias
  const [tabSeleccionada, setTabSeleccionada] = useState<string>(
    abiertas[0]?.id ?? ''
  );

  const captacionAbierta = abiertas.find((o) => o.embudo === 'captacion');

  // Oportunidad activa actual
  const opActiva =
    abiertas.find((o) => o.id === tabSeleccionada) ?? abiertas[0] ?? null;

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

  const handleResolverCaso = (oportunidadId: string) => {
    setError(null);
    iniciar(async () => {
      const res = await resolverCaso(oportunidadId, contactoId, 'Trámite resuelto satisfactoriamente');
      if (!res.ok) {
        setError(res.error ?? 'No se pudo resolver el caso.');
      }
    });
  };

  // Sin casos abiertos
  if (abiertas.length === 0) {
    return (
      <section className="flex flex-col gap-3 rounded-2xl border border-border/70 bg-card p-4 shadow-2xs">
        <div className="flex items-center gap-2">
          <Building2 className="size-4 text-muted-foreground" />
          <h2 className="font-semibold text-sm text-foreground">Trámites y Procesos</h2>
        </div>
        <p className="text-xs text-muted-foreground">
          Esta persona no tiene trámites ni casos abiertos en este momento.
        </p>
        <div className="pt-1">
          <Button
            variant="outline"
            size="sm"
            onClick={handleAbrirAdmin}
            disabled={pendiente}
            className="h-8 gap-1.5 text-xs rounded-xl"
          >
            {pendiente ? (
              <Loader2 className="size-3.5 animate-spin" />
            ) : (
              <FilePlus className="size-3.5" />
            )}
            Iniciar caso administrativo
          </Button>
        </div>
        {error && (
          <p role="alert" className="text-xs text-destructive mt-1">
            {error}
          </p>
        )}
      </section>
    );
  }

  const etapasDelEmbudo = etapas.filter((e) => e.embudo === opActiva?.embudo);
  const etapaActual = etapasDelEmbudo.find((e) => e.codigo === opActiva?.etapa);

  const esAdmin = opActiva?.embudo === 'administrativa';
  const esCaptacion = opActiva?.embudo === 'captacion';

  const infoEtapa = esAdmin
    ? INFO_ETAPAS_ADMIN[opActiva?.etapa ?? '']
    : esCaptacion
    ? INFO_ETAPAS_CAPTACION[opActiva?.etapa ?? '']
    : null;

  const IconoEtapa = infoEtapa?.icon ?? CheckCircle2;

  return (
    <section className="flex flex-col gap-3.5 rounded-2xl border border-border/70 bg-card p-4 shadow-2xs">
      {/* Si hay múltiples casos, selector por pestañas para no mezclar */}
      {abiertas.length > 1 ? (
        <div className="flex flex-col gap-2">
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
            Trámites activos ({abiertas.length})
          </p>
          <div className="flex flex-wrap items-center gap-1.5 rounded-xl bg-muted/60 p-1 border border-border/40">
            {abiertas.map((op) => {
              const activa = (opActiva?.id ?? abiertas[0].id) === op.id;
              const nombre =
                op.embudo === 'administrativa'
                  ? '🏢 Caso Admin'
                  : op.embudo === 'captacion'
                  ? '🏡 Captación'
                  : '💼 Comercial';

              return (
                <button
                  key={op.id}
                  type="button"
                  onClick={() => setTabSeleccionada(op.id)}
                  className={`px-2.5 py-1 rounded-lg text-xs font-medium transition-all cursor-pointer ${
                    activa
                      ? 'bg-background text-foreground font-semibold shadow-2xs'
                      : 'text-muted-foreground hover:text-foreground'
                  }`}
                >
                  {nombre}
                </button>
              );
            })}
          </div>
        </div>
      ) : (
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            {esAdmin ? (
              <Building2 className="size-4 text-purple-600 dark:text-purple-400" />
            ) : esCaptacion ? (
              <KeyRound className="size-4 text-emerald-600 dark:text-emerald-400" />
            ) : (
              <Briefcase className="size-4 text-sky-600 dark:text-sky-400" />
            )}
            <h2 className="font-semibold text-sm text-foreground">
              {esAdmin
                ? 'Caso Administrativo · Línea 320'
                : esCaptacion
                ? 'Proceso de Captación · Línea 320'
                : 'Oportunidad Comercial · Línea 324'}
            </h2>
          </div>
          <Badge
            variant="outline"
            className={`text-[10px] font-semibold uppercase ${
              esAdmin
                ? 'bg-purple-500/10 text-purple-700 dark:text-purple-300 border-purple-500/20'
                : esCaptacion
                ? 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border-emerald-500/20'
                : 'bg-sky-500/10 text-sky-700 dark:text-sky-300 border-sky-500/20'
            }`}
          >
            {esAdmin ? 'Inquilino' : esCaptacion ? 'Propietario' : 'Comercial'}
          </Badge>
        </div>
      )}

      {/* Tarjeta de Fase / Etapa Actual */}
      <div className={`flex flex-col gap-2 rounded-xl border p-3.5 transition-all ${infoEtapa?.color ?? 'bg-muted/40 border-border/60'}`}>
        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <IconoEtapa className="size-4 shrink-0" />
            <span className="text-xs font-bold tracking-tight">
              {etapaActual?.etiqueta ?? opActiva?.etapa}
            </span>
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => handleResolverCaso(opActiva!.id)}
            disabled={pendiente}
            className="h-7 px-2 text-[11px] font-medium text-foreground/80 hover:text-foreground hover:bg-background/80 rounded-lg"
            title="Cierra el caso como resuelto con éxito"
          >
            <CheckCircle2 className="size-3 mr-1 text-emerald-600" />
            Dar por resuelto
          </Button>
        </div>

        {infoEtapa?.desc && (
          <p className="text-[11px] leading-relaxed opacity-90">
            {infoEtapa.desc}
          </p>
        )}
      </div>

      {/* Selector para avanzar el caso de fase */}
      <div className="flex flex-col gap-1.5 pt-1">
        <label
          htmlFor={`etapa-${opActiva?.id}`}
          className="text-xs font-medium text-muted-foreground"
        >
          Avanzar trámite a:
        </label>
        <select
          id={`etapa-${opActiva?.id}`}
          value={opActiva?.etapa}
          onChange={(e) => handleCambiarEtapa(opActiva!.id, e.target.value)}
          disabled={pendiente}
          className="h-9 w-full rounded-xl border border-border/70 bg-background px-3 text-xs font-medium focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary"
        >
          {etapasDelEmbudo.map((e) => (
            <option key={e.codigo} value={e.codigo}>
              {e.etiqueta}
            </option>
          ))}
        </select>
      </div>

      {/* Reclasificación a Captación (ÚNICAMENTE si es administrativo y NO tiene captación abierta ya) */}
      {esAdmin && !captacionAbierta && (
        <div className="mt-2 flex flex-col gap-2 rounded-xl border border-amber-500/25 bg-amber-500/10 p-3 text-amber-950 dark:text-amber-200">
          <div>
            <p className="text-xs font-semibold">¿Es un propietario que desea consignar?</p>
            <p className="text-[11px] text-amber-800/80 dark:text-amber-300/80 mt-0.5">
              Cierra este caso de inquilino y abre la captación para registrar el inmueble.
            </p>
          </div>
          <Button
            variant="outline"
            size="sm"
            onClick={handleConvertirCaptacion}
            disabled={pendiente}
            className="h-8 gap-1.5 text-xs font-semibold bg-background hover:bg-amber-500/20 text-amber-900 dark:text-amber-200 border-amber-500/40 rounded-lg w-full"
          >
            {pendiente ? (
              <Loader2 className="size-3.5 animate-spin" />
            ) : (
              <Sparkles className="size-3.5 text-amber-600 dark:text-amber-400" />
            )}
            Reclasificar como Captación
          </Button>
        </div>
      )}

      {error && (
        <p role="alert" className="text-xs text-destructive mt-1 font-medium">
          {error}
        </p>
      )}
    </section>
  );
}
