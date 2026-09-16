'use client';

import { useState, useTransition } from 'react';
import { Archive, Loader2, Pencil, Plus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { guardarPlantilla, archivarPlantilla } from './acciones';

export interface Plantilla {
  id: string;
  nombre: string;
  cuerpo: string;
  categoria: string;
  estado_meta: string;
  nombre_meta: string | null;
}

// Lo que Meta significa con cada estado, dicho en una línea. "Borrador"
// sin explicación no le dice nada a quien nunca ha tramitado una.
const ESTADO: Record<string, { texto: string; ayuda: string }> = {
  borrador:  { texto: 'Borrador',  ayuda: 'Escrita aquí; todavía no se mandó a Meta' },
  enviada:   { texto: 'En revisión', ayuda: 'Mandada a Meta, esperando respuesta' },
  aprobada:  { texto: 'Aprobada',  ayuda: 'Se puede enviar fuera de las 24 horas' },
  rechazada: { texto: 'Rechazada', ayuda: 'Meta la rechazó; hay que reescribirla' },
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
  const [editando, setEditando] = useState<Plantilla | 'nueva' | null>(null);
  const [nombre, setNombre] = useState('');
  const [cuerpo, setCuerpo] = useState('');
  const [categoria, setCategoria] = useState('utilidad');
  const [error, setError] = useState<string | null>(null);
  const [pendiente, startTransition] = useTransition();

  function abrir(p: Plantilla | 'nueva') {
    setEditando(p);
    setError(null);
    setNombre(p === 'nueva' ? '' : p.nombre);
    setCuerpo(p === 'nueva' ? '' : p.cuerpo);
    setCategoria(p === 'nueva' ? 'utilidad' : p.categoria);
  }

  function guardar() {
    setError(null);
    startTransition(async () => {
      const r = await guardarPlantilla(
        editando === 'nueva' || editando === null ? null : editando.id,
        nombre,
        cuerpo,
        categoria
      );
      if (!r.ok) {
        setError(r.error ?? 'No se pudo guardar.');
        return;
      }
      setEditando(null);
    });
  }

  function archivar(id: string) {
    startTransition(async () => {
      await archivarPlantilla(id);
    });
  }

  return (
    <div className="flex flex-col gap-4">
      {puedeEditar && (
        <div>
          <Button size="sm" onClick={() => abrir('nueva')}>
            <Plus className="size-4" />
            Nueva plantilla
          </Button>
        </div>
      )}

      {plantillas.length === 0 ? (
        <div className="rounded-lg border border-dashed py-14 text-center">
          <p className="font-medium">Todavía no hay plantillas</p>
          <p className="text-sm text-muted-foreground">
            {puedeEditar
              ? 'Crea la primera con el botón de arriba.'
              : 'Pídele a un administrador que cree la primera.'}
          </p>
        </div>
      ) : (
        <ul className="flex flex-col gap-3">
          {plantillas.map((p) => {
            const e = ESTADO[p.estado_meta] ?? ESTADO.borrador;
            return (
              <li key={p.id} className="rounded-lg border bg-card p-4">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div className="min-w-0">
                    <h2 className="font-medium">{p.nombre}</h2>
                    <p className="text-xs text-muted-foreground">
                      <span className="capitalize">{p.categoria}</span>
                      {' · '}
                      <span title={e.ayuda}>{e.texto}</span>
                    </p>
                  </div>
                  {puedeEditar && (
                    <div className="flex items-center gap-1">
                      <Button size="xs" variant="ghost" onClick={() => abrir(p)}>
                        <Pencil className="size-3" />
                        Editar
                      </Button>
                      <Button
                        size="xs"
                        variant="ghost"
                        onClick={() => archivar(p.id)}
                        disabled={pendiente}
                        title="Se archiva, no se borra: los envíos ya hechos apuntan a ella"
                      >
                        <Archive className="size-3" />
                      </Button>
                    </div>
                  )}
                </div>

                <p className="mt-2 whitespace-pre-wrap rounded-md bg-muted px-3 py-2 text-sm text-muted-foreground">
                  {p.cuerpo}
                </p>
              </li>
            );
          })}
        </ul>
      )}

      <Dialog open={editando !== null} onOpenChange={(o) => !o && setEditando(null)}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>
              {editando === 'nueva' ? 'Nueva plantilla' : 'Editar plantilla'}
            </DialogTitle>
            <DialogDescription>
              Escribe el mensaje y deja las variables entre llaves dobles.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-2">
            <Label htmlFor="nombre-plantilla">Nombre</Label>
            <Input
              id="nombre-plantilla"
              value={nombre}
              onChange={(ev) => setNombre(ev.target.value)}
              placeholder="Recomendación de inmueble"
              disabled={pendiente}
            />
          </div>

          <div className="flex flex-col gap-2">
            <Label htmlFor="cuerpo-plantilla">Mensaje</Label>
            <Textarea
              id="cuerpo-plantilla"
              value={cuerpo}
              onChange={(ev) => setCuerpo(ev.target.value)}
              rows={8}
              placeholder={'Hola {{nombre}}, soy {{asesor}} de Cumbres…'}
              disabled={pendiente}
            />
            {/* El catálogo a la vista mientras se escribe: una variable
                inventada no se puede guardar, y descubrirlo al pulsar
                Guardar es peor que tenerlo delante. */}
            <p className="text-xs text-muted-foreground">
              Variables disponibles:{' '}
              {variables.map((v, i) => (
                <span key={v}>
                  {i > 0 && ', '}
                  <code className="rounded bg-muted px-1 py-0.5">{`{{${v}}}`}</code>
                </span>
              ))}
            </p>
          </div>

          <fieldset className="flex flex-col gap-2">
            <legend className="pb-2 text-sm font-medium">Categoría</legend>
            <div className="flex gap-1.5">
              {[
                { v: 'utilidad', t: 'Utilidad', a: 'Sobre algo que el cliente pidió: confirmar una visita' },
                { v: 'marketing', t: 'Marketing', a: 'Iniciativa nuestra: recomendar, reactivar' },
              ].map((c) => (
                <button
                  key={c.v}
                  type="button"
                  title={c.a}
                  onClick={() => setCategoria(c.v)}
                  aria-pressed={categoria === c.v}
                  className={`rounded-4xl border px-2.5 py-1 text-xs transition-colors ${
                    categoria === c.v
                      ? 'bg-primary text-primary-foreground'
                      : 'hover:bg-muted'
                  }`}
                >
                  {c.t}
                </button>
              ))}
            </div>
          </fieldset>

          {error && (
            <p role="alert" className="text-sm text-destructive">
              {error}
            </p>
          )}

          <DialogFooter>
            <Button variant="outline" onClick={() => setEditando(null)}>
              Cancelar
            </Button>
            <Button onClick={guardar} disabled={pendiente || !nombre.trim() || !cuerpo.trim()}>
              {pendiente && <Loader2 className="animate-spin" />}
              Guardar
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
