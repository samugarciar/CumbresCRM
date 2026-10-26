'use client';

import { useState, useTransition } from 'react';
import { Check, Loader2, Pencil, X } from 'lucide-react';
import { actualizarContacto } from './acciones';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { fechaLarga } from '@/lib/formato';
import { ControlBot } from './ControlBot';
import { Responsable } from './Responsable';

interface Props {
  contactoId: string;
  nombre: string | null;
  tipo: string;
  origen: string | null;
  telefonoCrudo: string | null;
  creadoAt: string;
  identidades: { tipo: string; valor: string }[];
  botActivo: boolean;
  botMotivo: string | null;
  botCambiadoAt: string | null;
  botVuelveAt: string | null;
  /** Todas sus oportunidades abiertas son de embudos que el bot no atiende. */
  botNoAtiende: boolean;
  ahora: string;
  responsableNombre: string | null;
  responsableEsMio: boolean;
}

const ETIQUETA_IDENTIDAD: Record<string, string> = {
  telefono_e164: 'Teléfono',
  whatsapp_username: 'Usuario de WhatsApp',
  // Kommo ya no se usa: son números de la era anterior, solo de consulta.
  kommo_lead: 'Histórico Kommo · lead',
  kommo_contact: 'Histórico Kommo · contacto',
  email: 'Correo',
  meta_psid: 'Meta',
  otro: 'Otro',
};

/** De dónde salió el contacto, dicho como lo diría una persona. */
const ETIQUETA_ORIGEN: Record<string, string> = {
  whatsapp: 'WhatsApp',
  envio_masivo: 'Envío masivo',
  cita: 'Cita de la plataforma',
  kommo: 'Histórico Kommo',
  manual: 'Creado a mano',
};

function origenLegible(origen: string | null): string {
  if (!origen) return '—';
  return ETIQUETA_ORIGEN[origen] ?? origen.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase());
}

const ETIQUETA_TIPO: Record<string, string> = {
  cliente: 'Cliente',
  propietario: 'Propietario',
  ambos: 'Cliente y propietario',
};

export function PanelDatos(props: Props) {
  const [editando, setEditando] = useState(false);
  const [nombre, setNombre] = useState(props.nombre ?? '');
  const [tipo, setTipo] = useState(props.tipo);
  const [error, setError] = useState<string | null>(null);
  const [guardando, iniciar] = useTransition();

  const guardar = () => {
    setError(null);
    iniciar(async () => {
      const r = await actualizarContacto(props.contactoId, nombre, tipo);
      if (r.ok) setEditando(false);
      else setError(r.error ?? 'No se pudo guardar.');
    });
  };

  // El teléfono ya está en la cabecera: la sección solo aporta algo si
  // hay otra forma de reconocerlo (correo, histórico de Kommo…).
  const otrasIdentidades = props.identidades.filter((i) => i.tipo !== 'telefono_e164');

  return (
    <aside className="flex flex-col gap-4 text-sm">
      {/* Quién lleva esto va primero: si entras a una ficha ajena, es lo
          que tienes que saber antes de escribir. */}
      <Responsable
        contactoId={props.contactoId}
        nombre={props.responsableNombre}
        esMio={props.responsableEsMio}
      />

      {/* Y después el bot: lo otro de este panel sobre lo que se ACTÚA, y
          callado hay que verlo al abrir la ficha, no al bajar. */}
      <ControlBot
        contactoId={props.contactoId}
        activo={props.botActivo}
        motivo={props.botMotivo}
        cambiadoAt={props.botCambiadoAt}
        vuelveAt={props.botVuelveAt}
        ahora={props.ahora}
        noAtiende={props.botNoAtiende}
      />

      <section className="flex flex-col gap-3 rounded-xl border bg-card p-4">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold">Datos</h2>
          {!editando && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setEditando(true)}
              className="h-8 rounded-lg text-xs"
            >
              <Pencil className="size-3.5" />
              Editar
            </Button>
          )}
        </div>

        {editando ? (
          <div className="flex flex-col gap-3">
            <label className="flex flex-col gap-1">
              <span className="text-xs text-muted-foreground">Nombre</span>
              <Input
                value={nombre}
                onChange={(e) => setNombre(e.target.value)}
                disabled={guardando}
              />
            </label>

            <label className="flex flex-col gap-1">
              <span className="text-xs text-muted-foreground">Tipo</span>
              <select
                value={tipo}
                onChange={(e) => setTipo(e.target.value)}
                disabled={guardando}
                className="h-8 rounded-lg border bg-background px-2.5 text-sm"
              >
                <option value="cliente">Cliente</option>
                <option value="propietario">Propietario</option>
                <option value="ambos">Ambos</option>
              </select>
            </label>

            <div className="flex gap-2">
              <Button size="sm" onClick={guardar} disabled={guardando} className="h-8 rounded-lg">
                {guardando ? <Loader2 className="animate-spin" /> : <Check className="size-3.5" />}
                Guardar
              </Button>
              <Button
                size="sm"
                variant="ghost"
                onClick={() => {
                  setEditando(false);
                  setNombre(props.nombre ?? '');
                  setTipo(props.tipo);
                }}
                disabled={guardando}
                className="h-8 rounded-lg"
                aria-label="Cancelar"
              >
                <X className="size-3.5" />
              </Button>
            </div>
          </div>
        ) : (
          <dl className="grid grid-cols-[7rem_1fr] gap-x-3 gap-y-2">
            <dt className="text-muted-foreground">Tipo</dt>
            <dd>{ETIQUETA_TIPO[props.tipo] ?? props.tipo}</dd>

            <dt className="text-muted-foreground">Llegó por</dt>
            <dd>{origenLegible(props.origen)}</dd>

            <dt className="text-muted-foreground">Conocido desde</dt>
            <dd>{fechaLarga(props.creadoAt)}</dd>

            {/* El valor crudo solo importa cuando NO se pudo normalizar:
                es la pista para revisar a mano qué llegó en su lugar. */}
            {props.telefonoCrudo && !props.identidades.some((i) => i.tipo === 'telefono_e164') && (
              <>
                <dt className="text-muted-foreground">Llegó como</dt>
                <dd className="break-all font-mono text-xs">{props.telefonoCrudo}</dd>
              </>
            )}
          </dl>
        )}

        {error && (
          <p role="alert" className="text-sm text-destructive">
            {error}
          </p>
        )}
      </section>

      {otrasIdentidades.length > 0 && (
        <section className="flex flex-col gap-3 rounded-xl border bg-card p-4">
          <h2 className="text-sm font-semibold">Cómo lo reconocemos</h2>
          <ul className="flex flex-col gap-2">
            {otrasIdentidades.map((i) => (
              <li key={`${i.tipo}:${i.valor}`} className="flex flex-col">
                <span className="text-xs text-muted-foreground">
                  {ETIQUETA_IDENTIDAD[i.tipo] ?? i.tipo}
                </span>
                <span className="break-all font-mono text-xs">{i.valor}</span>
              </li>
            ))}
          </ul>
        </section>
      )}

    </aside>
  );
}
