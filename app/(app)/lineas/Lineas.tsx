'use client';

import { useState, useTransition } from 'react';
import { Check, KeyRound, Loader2, MessageCircle, Pencil, Phone, PhoneOff } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { fechaLarga } from '@/lib/formato';
import { guardarLinea } from './acciones';

export interface Embudo {
  codigo: string;
  etiqueta: string;
  bot_atiende: boolean;
}

export interface Linea {
  embudo: string;
  nombre: string;
  wa_phone_number_id: string | null;
  telefono_e164: string | null;
  /** Desde cuándo Meta rechaza el token (el primer rechazo). Lo anota la plataforma. */
  token_invalido_at: string | null;
  token_error_codigo: number | null;
  /** El mensaje de Meta, con cualquier cosa con forma de token ya retirada en la base. */
  token_error: string | null;
}

/**
 * Dónde se conecta cada número de WhatsApp.
 *
 * Existe para un momento concreto: el día que Meta devuelva los
 * `phone_number_id` y haya que decirle al CRM cuál alimenta qué embudo.
 * Sin esa fila el webhook descarta los mensajes entrantes en vez de
 * adivinar de quién son — y lo hace en silencio, que es lo peor que
 * podría pasar el primer día del canal.
 *
 * El campo que más se equivoca es el primero: Meta llama `phone_number_id`
 * a un identificador largo de dígitos que NO es el teléfono. Por eso van
 * separados y con su explicación al lado.
 */
export function Lineas({
  embudos,
  lineas,
  puedeEditar,
  urlConectar,
}: {
  embudos: Embudo[];
  lineas: Linea[];
  puedeEditar: boolean;
  /**
   * La página de la plataforma donde se conecta un número con la ventana
   * de Meta (registro integrado, coexistencia). Sin `PLATAFORMA_URL`, null.
   */
  urlConectar: string | null;
}) {
  const [editando, setEditando] = useState<string | null>(null);

  return (
    <ul className="flex flex-col gap-3">
      {embudos.map((e) => {
        const linea = lineas.find((l) => l.embudo === e.codigo) ?? null;
        return (
          <li key={e.codigo} className="rounded-lg border bg-card p-4">
            <Fila
              embudo={e}
              linea={linea}
              puedeEditar={puedeEditar}
              urlConectar={urlConectar}
              abierto={editando === e.codigo}
              abrir={() => setEditando(e.codigo)}
              cerrar={() => setEditando(null)}
            />
          </li>
        );
      })}
    </ul>
  );
}

function Fila({
  embudo,
  linea,
  puedeEditar,
  urlConectar,
  abierto,
  abrir,
  cerrar,
}: {
  embudo: Embudo;
  linea: Linea | null;
  puedeEditar: boolean;
  urlConectar: string | null;
  abierto: boolean;
  abrir: () => void;
  cerrar: () => void;
}) {
  const [nombre, setNombre] = useState(linea?.nombre ?? embudo.etiqueta);
  const [id, setId] = useState(linea?.wa_phone_number_id ?? '');
  const [tel, setTel] = useState(linea?.telefono_e164 ?? '');
  const [error, setError] = useState<string | null>(null);
  const [guardando, iniciar] = useTransition();

  const conectada = Boolean(linea?.wa_phone_number_id);
  // Una línea con el token rechazado sigue "conectada" en el sentido de
  // que tiene número, pero no sale ni entra nada. Es lo primero que tiene
  // que verse, por encima del estado normal.
  const tokenCaido = Boolean(linea?.token_invalido_at);

  const guardar = () => {
    setError(null);
    iniciar(async () => {
      const r = await guardarLinea(embudo.codigo, nombre, id, tel);
      if (r.ok) cerrar();
      else setError(r.error ?? 'No se pudo guardar.');
    });
  };

  if (!abierto) {
    return (
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="font-medium">{embudo.etiqueta}</h2>
            {tokenCaido ? (
              <span className="inline-flex items-center gap-1 rounded-4xl bg-destructive/10 px-2 py-0.5 text-xs font-medium text-destructive">
                <KeyRound className="size-3" />
                Meta rechaza el token
              </span>
            ) : (
              <span
                className={`inline-flex items-center gap-1 rounded-4xl px-2 py-0.5 text-xs font-medium ${
                  conectada ? 'bg-muted text-muted-foreground' : 'bg-warning/10 text-warning'
                }`}
              >
                {conectada ? <Phone className="size-3" /> : <PhoneOff className="size-3" />}
                {conectada ? 'Conectada' : 'Sin conectar'}
              </span>
            )}
            {embudo.bot_atiende && (
              <span className="rounded-4xl bg-primary/10 px-2 py-0.5 text-xs text-primary">
                el bot contesta aquí
              </span>
            )}
          </div>

          {tokenCaido && (
            <div role="alert" className="mt-2 max-w-[60ch] text-sm text-destructive">
              <p>
                Desde el {fechaLarga(linea!.token_invalido_at)} Meta no acepta la
                credencial de esta línea: <b>no sale ni entra ningún mensaje</b> por
                este número. Se arregla volviendo a conectarlo con Meta.
              </p>
              {(linea!.token_error_codigo !== null || linea!.token_error) && (
                <p className="mt-1 text-xs text-muted-foreground">
                  Meta respondió
                  {linea!.token_error_codigo !== null && (
                    <>
                      {' '}
                      <span className="font-mono">{linea!.token_error_codigo}</span>
                    </>
                  )}
                  {linea!.token_error && <>: «{linea!.token_error}»</>}
                </p>
              )}
            </div>
          )}

          {conectada ? (
            <p className="mt-1 flex flex-wrap items-center gap-x-2 text-xs text-muted-foreground">
              <span className="tabular">{linea!.telefono_e164 ?? 'sin teléfono anotado'}</span>
              <span aria-hidden>·</span>
              <span className="font-mono">id {linea!.wa_phone_number_id}</span>
            </p>
          ) : (
            <p className="mt-1 max-w-[52ch] text-xs text-muted-foreground">
              Sin esto, los mensajes que entren por este número se descartan
              sin aviso. Se conecta cuando Meta dé el <code>phone number ID</code>.
            </p>
          )}
        </div>

        {puedeEditar && (
          <div className="flex flex-wrap items-center gap-2">
            {/* El camino de verdad: la ventana de Meta, en la plataforma, que
                es quien guarda el token. El formulario de al lado queda para
                el número de prueba de Meta, que no pasa por esa ventana. */}
            {urlConectar && (
              <Button size="sm" variant={conectada && !tokenCaido ? 'ghost' : 'default'} asChild>
                <a
                  href={`${urlConectar}?embudo=${encodeURIComponent(embudo.codigo)}`}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  <MessageCircle className="size-3.5" />
                  {conectada ? 'Reconectar con WhatsApp' : 'Conectar con WhatsApp'}
                </a>
              </Button>
            )}
            <Button
              size="sm"
              variant={conectada || urlConectar ? 'ghost' : 'default'}
              onClick={abrir}
            >
              <Pencil className="size-3.5" />
              {urlConectar ? (conectada ? 'Cambiar a mano' : 'A mano') : conectada ? 'Cambiar' : 'Conectar'}
            </Button>
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <h2 className="font-medium">{embudo.etiqueta}</h2>

      <div className="flex flex-col gap-1.5">
        <Label htmlFor={`id-${embudo.codigo}`}>Phone number ID de Meta</Label>
        <Input
          id={`id-${embudo.codigo}`}
          value={id}
          onChange={(e) => setId(e.target.value)}
          placeholder="109876543210987"
          disabled={guardando}
          inputMode="numeric"
        />
        {/* Es EL error de configuración: pegar el teléfono aquí. */}
        <p className="text-xs text-muted-foreground">
          Son solo dígitos y lo da Meta en el panel de la app.{' '}
          <b>No es el número de teléfono</b>, aunque se parezca.
        </p>
      </div>

      <div className="flex flex-col gap-1.5">
        <Label htmlFor={`tel-${embudo.codigo}`}>El número, para saber cuál es</Label>
        <Input
          id={`tel-${embudo.codigo}`}
          value={tel}
          onChange={(e) => setTel(e.target.value)}
          placeholder="+573001234567"
          disabled={guardando}
        />
      </div>

      <div className="flex flex-col gap-1.5">
        <Label htmlFor={`nom-${embudo.codigo}`}>Nombre</Label>
        <Input
          id={`nom-${embudo.codigo}`}
          value={nombre}
          onChange={(e) => setNombre(e.target.value)}
          disabled={guardando}
        />
      </div>

      {error && (
        <p role="alert" className="text-sm text-destructive">
          {error}
        </p>
      )}

      <div className="flex gap-2">
        <Button size="sm" onClick={guardar} disabled={guardando}>
          {guardando ? <Loader2 className="animate-spin" /> : <Check className="size-3.5" />}
          Guardar
        </Button>
        <Button size="sm" variant="ghost" onClick={cerrar} disabled={guardando}>
          Cancelar
        </Button>
      </div>
    </div>
  );
}
