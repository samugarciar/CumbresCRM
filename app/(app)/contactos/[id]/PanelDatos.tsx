'use client';

import { useState, useTransition } from 'react';
import { Check, Loader2, Pencil, X } from 'lucide-react';
import { actualizarContacto } from './acciones';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { fechaLarga } from '@/lib/formato';

interface Props {
  contactoId: string;
  nombre: string | null;
  tipo: string;
  origen: string | null;
  telefonoCrudo: string | null;
  creadoAt: string;
  identidades: { tipo: string; valor: string }[];
}

const ETIQUETA_IDENTIDAD: Record<string, string> = {
  telefono_e164: 'Teléfono',
  whatsapp_username: 'Usuario de WhatsApp',
  kommo_lead: 'Lead en Kommo',
  kommo_contact: 'Contacto en Kommo',
  email: 'Correo',
  meta_psid: 'Meta',
  otro: 'Otro',
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

  return (
    <aside className="flex flex-col gap-5 text-sm">
      <section className="flex flex-col gap-3 rounded-lg border bg-card p-4">
        <div className="flex items-center justify-between">
          <h2 className="font-medium">Datos</h2>
          {!editando && (
            <Button variant="ghost" size="sm" onClick={() => setEditando(true)}>
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
                className="h-9 rounded-md border bg-background px-3 text-sm"
              >
                <option value="cliente">Cliente</option>
                <option value="propietario">Propietario</option>
                <option value="ambos">Ambos</option>
              </select>
            </label>

            <div className="flex gap-2">
              <Button size="sm" onClick={guardar} disabled={guardando}>
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
              >
                <X className="size-3.5" />
              </Button>
            </div>
          </div>
        ) : (
          <dl className="grid grid-cols-[7rem_1fr] gap-x-3 gap-y-2">
            <dt className="text-muted-foreground">Tipo</dt>
            <dd className="capitalize">{props.tipo}</dd>

            <dt className="text-muted-foreground">Origen</dt>
            <dd>{props.origen ?? '—'}</dd>

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

      <section className="flex flex-col gap-3 rounded-lg border bg-card p-4">
        <h2 className="font-medium">Cómo lo reconocemos</h2>
        {props.identidades.length === 0 ? (
          <p className="text-muted-foreground">Sin identidades registradas.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {props.identidades.map((i) => (
              <li key={`${i.tipo}:${i.valor}`} className="flex flex-col">
                <span className="text-xs text-muted-foreground">
                  {ETIQUETA_IDENTIDAD[i.tipo] ?? i.tipo}
                </span>
                <span className="break-all font-mono text-xs">{i.valor}</span>
              </li>
            ))}
          </ul>
        )}
      </section>

    </aside>
  );
}
