'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
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
  ChevronDown,
  MoreHorizontal,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { CerrarOportunidad } from '@/app/(app)/tablero/CerrarOportunidad';
import {
  convertirACaptacion,
  convertirAAdministrativo,
  abrirCasoAdministrativo,
  cambiarEtapaOportunidad,
  resolverCaso,
  type Resultado,
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
  /** Para las preguntas de confirmación: «¿Cerrar el caso de Gloria…?». */
  nombre?: string | null;
  oportunidades: OportunidadContacto[];
  etapas: EtapaConfig[];
}

/** Sin números de línea: la comercial ya cambió de número una vez. */
const EMBUDO: Record<string, { etiqueta: string; icono: typeof Building2; color: string }> = {
  comercial: { etiqueta: 'Comercial', icono: Briefcase, color: 'text-sky-600 dark:text-sky-400' },
  administrativa: {
    etiqueta: 'Administrativa',
    icono: Building2,
    color: 'text-purple-600 dark:text-purple-400',
  },
  captacion: { etiqueta: 'Captación', icono: KeyRound, color: 'text-emerald-600 dark:text-emerald-400' },
};

const INFO_ETAPAS_ADMIN: Record<string, { desc: string; icon: typeof Building2 }> = {
  al_dia: { desc: 'Inquilino al día y sin novedades activas.', icon: CheckCircle2 },
  mantenimiento: {
    desc: 'Reportó un daño, avería o solicitud de reparación en el inmueble.',
    icon: Wrench,
  },
  en_mora: { desc: 'Canon o cuota de administración pendiente de pago.', icon: AlertTriangle },
  acuerdo_de_pago: {
    desc: 'Compromiso o acuerdo de cuotas pactado con el inquilino.',
    icon: Handshake,
  },
  en_renovacion: {
    desc: 'En trámite de renovación o ajuste de contrato de arrendamiento.',
    icon: FileCheck,
  },
  en_terminacion: {
    desc: 'Fin de contrato, entrega física del inmueble y finiquito.',
    icon: DoorOpen,
  },
};

const INFO_ETAPAS_CAPTACION: Record<string, { desc: string; icon: typeof Building2 }> = {
  prospecto: { desc: 'Propietario interesado en consignar su propiedad con Cumbres.', icon: Clock },
  propietario_contactado: {
    desc: 'Primer contacto telefónico o por chat realizado con el propietario.',
    icon: PhoneCall,
  },
  visita_captacion: {
    desc: 'Visita técnica programada o realizada para registro fotográfico e inspección.',
    icon: Camera,
  },
  inmueble_verificado: {
    desc: 'Estudio de títulos, certificado de tradición y verificación jurídica al día.',
    icon: FileText,
  },
  negociando: {
    desc: 'Definiendo comisión, canon y condiciones comerciales finales.',
    icon: Handshake,
  },
};

interface Confirmacion {
  titulo: string;
  descripcion: string;
  boton: string;
  accion: () => Promise<Resultado>;
}

/**
 * Los casos abiertos de la persona y lo que se puede hacer con ellos.
 *
 * NADA SE CIERRA NI SE MUEVE CON UN SOLO CLIC. Antes, «Dar por resuelto»
 * cerraba la oportunidad comercial como ganada al primer toque y el select
 * de etapa movía al elegir. En la calle, con el celular en la mano, eso es
 * un caso cerrado por error. Ahora:
 * - la comercial se cierra con el mismo diálogo del Tablero (ganada o
 *   perdida, con motivo);
 * - administrativa y captación piden confirmación antes de cerrar;
 * - cambiar de etapa es elegir y pulsar «Mover».
 */
export function CasosYEmbudos({ contactoId, nombre, oportunidades, etapas }: Props) {
  const router = useRouter();
  const [pendiente, iniciar] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [confirmar, setConfirmar] = useState<Confirmacion | null>(null);
  const [eleccion, setEleccion] = useState<{ id: string; etapa: string } | null>(null);
  // El menú de «Cerrar oportunidad» se controla aquí para cerrarlo cuando
  // se cancela el diálogo: si no, quedaba abierto encima de la ficha.
  const [menuCerrar, setMenuCerrar] = useState(false);

  const abiertas = oportunidades.filter((o) => o.estado === 'abierta');
  const [tabSeleccionada, setTabSeleccionada] = useState<string>(abiertas[0]?.id ?? '');

  const captacionAbierta = abiertas.find((o) => o.embudo === 'captacion');
  const adminAbierta = abiertas.find((o) => o.embudo === 'administrativa');
  const opActiva = abiertas.find((o) => o.id === tabSeleccionada) ?? abiertas[0] ?? null;

  const primerNombre = nombre?.trim().split(/\s+/)[0] || 'esta persona';

  const ejecutar = (accion: () => Promise<Resultado>, alTerminar?: (r: Resultado) => void) => {
    setError(null);
    iniciar(async () => {
      const r = await accion();
      if (!r.ok) {
        setError(r.error ?? 'No se pudo guardar el cambio.');
        return;
      }
      setConfirmar(null);
      alTerminar?.(r);
    });
  };

  const handleAbrirAdmin = () => ejecutar(() => abrirCasoAdministrativo(contactoId));

  if (!opActiva) {
    return (
      <section className="flex flex-col gap-3 rounded-xl border bg-card p-4">
        <div className="flex items-center gap-2">
          <Building2 className="size-4 text-muted-foreground" />
          <h2 className="text-sm font-semibold text-foreground">Casos</h2>
        </div>
        <p className="text-xs text-muted-foreground">
          Esta persona no tiene casos abiertos en este momento.
        </p>
        <div>
          <Button
            variant="outline"
            size="sm"
            onClick={handleAbrirAdmin}
            disabled={pendiente}
            className="h-8 gap-1.5 rounded-lg text-xs"
          >
            {pendiente ? <Loader2 className="size-3.5 animate-spin" /> : <FilePlus className="size-3.5" />}
            Abrir caso administrativo
          </Button>
        </div>
        {error && (
          <p role="alert" className="text-xs text-destructive">
            {error}
          </p>
        )}
      </section>
    );
  }

  const etapasDelEmbudo = etapas.filter((e) => e.embudo === opActiva.embudo);
  const etapaActual = etapasDelEmbudo.find((e) => e.codigo === opActiva.etapa);
  const etapaElegida = eleccion && eleccion.id === opActiva.id ? eleccion.etapa : opActiva.etapa;
  const etiquetaElegida =
    etapasDelEmbudo.find((e) => e.codigo === etapaElegida)?.etiqueta ?? etapaElegida;

  const esComercial = opActiva.embudo === 'comercial';
  const esAdmin = opActiva.embudo === 'administrativa';
  const esCaptacion = opActiva.embudo === 'captacion';
  const embudo = EMBUDO[opActiva.embudo] ?? EMBUDO.comercial;
  const IconoEmbudo = embudo.icono;

  const infoEtapa = esAdmin
    ? INFO_ETAPAS_ADMIN[opActiva.etapa]
    : esCaptacion
      ? INFO_ETAPAS_CAPTACION[opActiva.etapa]
      : null;

  const puedeReclasificar = esAdmin && !captacionAbierta;
  const puedePasarAAdmin = esCaptacion && !adminAbierta;

  const mover = () => {
    if (etapaElegida === opActiva.etapa) return;
    ejecutar(
      () => cambiarEtapaOportunidad(opActiva.id, etapaElegida, contactoId),
      () => setEleccion(null)
    );
  };

  return (
    <section className="flex flex-col gap-3 rounded-xl border bg-card p-4">
      {/* Varias abiertas: una pestaña por embudo, para no mezclarlas */}
      {abiertas.length > 1 && (
        <div className="flex flex-wrap items-center gap-1 rounded-lg bg-muted/60 p-1">
          {abiertas.map((op) => {
            const activa = opActiva.id === op.id;
            return (
              <button
                key={op.id}
                type="button"
                onClick={() => setTabSeleccionada(op.id)}
                aria-pressed={activa}
                className={`rounded-md px-2.5 py-1 text-xs font-medium transition-colors ${
                  activa
                    ? 'bg-background text-foreground shadow-2xs'
                    : 'text-muted-foreground hover:text-foreground'
                }`}
              >
                {(EMBUDO[op.embudo] ?? EMBUDO.comercial).etiqueta}
              </button>
            );
          })}
        </div>
      )}

      <div className="flex items-start justify-between gap-2">
        <div className="flex min-w-0 items-start gap-2">
          <IconoEmbudo className={`mt-0.5 size-4 shrink-0 ${embudo.color}`} />
          <h2 className="text-sm font-semibold leading-snug text-foreground">
            {embudo.etiqueta} · {etapaActual?.etiqueta ?? opActiva.etapa}
          </h2>
        </div>

        {(puedeReclasificar || puedePasarAAdmin) && (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="ghost"
                size="icon-sm"
                className="shrink-0 text-muted-foreground"
                aria-label="Más acciones"
                title="Más acciones"
              >
                <MoreHorizontal className="size-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-64">
              {puedeReclasificar && (
                <DropdownMenuItem
                  onSelect={() =>
                    setConfirmar({
                      titulo: '¿Reclasificar como captación?',
                      descripcion: `Se cierra el caso administrativo de ${primerNombre} y se abre la captación para registrar su inmueble.`,
                      boton: 'Reclasificar',
                      accion: () => convertirACaptacion(contactoId),
                    })
                  }
                >
                  <Sparkles />
                  Reclasificar como captación
                </DropdownMenuItem>
              )}
              {puedePasarAAdmin && (
                <DropdownMenuItem
                  onSelect={() =>
                    setConfirmar({
                      titulo: '¿Pasar a Administrativa?',
                      descripcion: `Se cierra la captación de ${primerNombre} como lograda y se abre el caso administrativo para el contrato y la administración del inmueble.`,
                      boton: 'Pasar a Administrativa',
                      accion: () => convertirAAdministrativo(contactoId, true),
                    })
                  }
                >
                  <Handshake />
                  Pasar a Administrativa
                </DropdownMenuItem>
              )}
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </div>

      {infoEtapa?.desc && (
        <p className="text-xs leading-relaxed text-muted-foreground">{infoEtapa.desc}</p>
      )}

      {/* Cambiar de etapa: elegir NO mueve; mueve el botón */}
      <div className="flex flex-col gap-1.5">
        <label htmlFor={`etapa-${opActiva.id}`} className="text-xs font-medium text-muted-foreground">
          Cambiar de etapa
        </label>
        <div className="flex items-center gap-2">
          <select
            id={`etapa-${opActiva.id}`}
            value={etapaElegida}
            onChange={(e) => setEleccion({ id: opActiva.id, etapa: e.target.value })}
            disabled={pendiente}
            className="h-8 min-w-0 flex-1 rounded-lg border bg-background px-2.5 text-xs font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
          >
            {etapasDelEmbudo.map((e) => (
              <option key={e.codigo} value={e.codigo}>
                {e.etiqueta}
              </option>
            ))}
          </select>
          <Button
            size="sm"
            variant={etapaElegida === opActiva.etapa ? 'outline' : 'default'}
            onClick={mover}
            disabled={pendiente || etapaElegida === opActiva.etapa}
            className="h-8 shrink-0 rounded-lg text-xs"
            title={
              etapaElegida === opActiva.etapa
                ? 'Elige otra etapa para moverla'
                : `Mover a «${etiquetaElegida}»`
            }
          >
            {pendiente && etapaElegida !== opActiva.etapa ? (
              <Loader2 className="size-3.5 animate-spin" />
            ) : null}
            Mover
          </Button>
        </div>
      </div>

      {/* Cerrar: comercial con el diálogo del Tablero; lo demás, con confirmación */}
      <div className="border-t pt-3">
        {esComercial ? (
          <DropdownMenu open={menuCerrar} onOpenChange={setMenuCerrar}>
            <DropdownMenuTrigger asChild>
              <Button
                variant="outline"
                size="sm"
                disabled={pendiente}
                className="h-8 gap-1.5 whitespace-normal rounded-lg text-xs"
              >
                Cerrar oportunidad
                <ChevronDown className="size-3.5" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="start" className="w-56">
              <CerrarOportunidad
                oportunidadId={opActiva.id}
                nombre={nombre || 'Esta persona'}
                contactoId={contactoId}
                desdeFicha
                alCerrar={() => router.refresh()}
                alSalirDelDialogo={() => setMenuCerrar(false)}
              />
            </DropdownMenuContent>
          </DropdownMenu>
        ) : (
          <Button
            variant="outline"
            size="sm"
            disabled={pendiente}
            onClick={() =>
              setConfirmar({
                titulo: `¿Cerrar el caso de ${primerNombre} como resuelto?`,
                descripcion: esAdmin
                  ? 'El caso administrativo se cierra y queda en su historial.'
                  : 'La captación se cierra y queda en su historial.',
                boton: 'Cerrar caso',
                accion: () => resolverCaso(opActiva.id, contactoId, 'Trámite resuelto'),
              })
            }
            className="h-8 gap-1.5 whitespace-normal rounded-lg text-xs"
          >
            <CheckCircle2 className="size-3.5 text-emerald-600" />
            Cerrar caso
          </Button>
        )}
      </div>

      {error && !confirmar && (
        <p role="alert" className="text-xs font-medium text-destructive">
          {error}
        </p>
      )}

      <Dialog
        open={confirmar !== null}
        onOpenChange={(abierto) => {
          if (!abierto && !pendiente) {
            setConfirmar(null);
            setError(null);
          }
        }}
      >
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{confirmar?.titulo}</DialogTitle>
            <DialogDescription>{confirmar?.descripcion}</DialogDescription>
          </DialogHeader>
          {error && (
            <p role="alert" className="text-sm text-destructive">
              {error}
            </p>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setConfirmar(null)} disabled={pendiente}>
              Cancelar
            </Button>
            <Button
              onClick={() => {
                const c = confirmar;
                if (!c) return;
                ejecutar(c.accion, (r) => {
                  if (r.oportunidadId) setTabSeleccionada(r.oportunidadId);
                });
              }}
              disabled={pendiente}
            >
              {pendiente && <Loader2 className="size-3.5 animate-spin" />}
              {confirmar?.boton}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </section>
  );
}
