import Link from 'next/link';
import { BotOff, MessageCircle } from 'lucide-react';
import { createClient } from '@/lib/supabase/server';
import { iniciales, telefonoLegible, tiempoRelativo } from '@/lib/formato';

interface Callado {
  contacto_id: string;
  nombre: string | null;
  telefono_e164: string | null;
  motivo: 'escalamiento' | 'manual' | 'relevo' | null;
  callado_desde: string | null;
  callado_por_nombre: string | null;
  bot_caduca: boolean;
  atendido: boolean | null;
  vuelve_at: string | null;
  ultimo_entrante_at: string | null;
}

const MOTIVO: Record<string, string> = {
  escalamiento: 'Pidió una persona',
  manual: 'Apagado a mano',
  relevo: 'Escribió el equipo',
};

/**
 * Todas las conversaciones con el bot callado (decisión 25).
 *
 * No es un aviso: los avisos están en «Mi día», que ya grita por los
 * escalados que nadie atendió. Esto es el sitio donde mirar el resto —el
 * manual, el relevo, el escalado que alguien atendió y por eso ya no
 * caduca— para que ninguno se quede callado para siempre sin que nadie lo
 * note. Arriba van los que NO vuelven solos, que son los que se pudren.
 *
 * Lo que no dice es «sin responder»: las asesoras contestan en Kommo y el
 * CRM no lo ve. Dice cuándo escribió la persona, y si fue después de que
 * el bot se callara. El juicio lo pone quien mira.
 */
export default async function PaginaBotCallado() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema('crm')
    .from('v_bot_callado')
    .select(
      'contacto_id, nombre, telefono_e164, motivo, callado_desde, callado_por_nombre, bot_caduca, atendido, vuelve_at, ultimo_entrante_at',
    )
    .order('callado_desde', { ascending: true });

  if (error) {
    return (
      <p className="text-sm text-destructive">
        No se pudo cargar la lista: {error.message}
      </p>
    );
  }

  const filas = (data ?? []) as Callado[];
  const noVuelven = filas.filter((f) => !f.vuelve_at);
  const vuelven = filas
    .filter((f) => f.vuelve_at)
    .sort((a, b) => ms(a.vuelve_at) - ms(b.vuelve_at));
  // Una sola hora para toda la página, tomada en el servidor.
  const ahora = new Date().getTime();

  return (
    <div className="mx-auto flex w-full max-w-4xl flex-col gap-6">
      <header>
        <h1 className="text-xl font-semibold tracking-tight">Bot callado</h1>
        <p className="max-w-[64ch] text-sm text-muted-foreground">
          {filas.length === 0
            ? 'El bot está respondiendo en todas las conversaciones.'
            : `${filas.length} ${filas.length === 1 ? 'conversación' : 'conversaciones'} donde el bot no está respondiendo, sea por lo que sea. Las de arriba no vuelven solas: si nadie las mira, se quedan así.`}
        </p>
      </header>

      {filas.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-lg border border-dashed py-16 text-center">
          <BotOff className="size-8 text-muted-foreground" />
          <p className="font-medium">Ninguna conversación con el bot callado</p>
        </div>
      ) : (
        <>
          <Seccion
            titulo="No vuelven solas"
            explicacion="El bot no va a volver por su cuenta. Alguien tiene que atenderlas o encenderlo desde la ficha."
            filas={noVuelven}
            ahora={ahora}
            vacio="Ninguna: todos los silencios de ahora terminan solos."
          />
          <Seccion
            titulo="Vuelven solas"
            explicacion="El bot recupera la voz a la hora indicada si nadie del equipo interviene."
            filas={vuelven}
            ahora={ahora}
            vacio="Ninguna."
          />
        </>
      )}
    </div>
  );
}

function Seccion({
  titulo,
  explicacion,
  filas,
  ahora,
  vacio,
}: {
  titulo: string;
  explicacion: string;
  filas: Callado[];
  ahora: number;
  vacio: string;
}) {
  return (
    <section className="flex flex-col gap-2">
      <div>
        <h2 className="text-sm font-semibold">
          {titulo} <span className="tabular font-normal text-muted-foreground">· {filas.length}</span>
        </h2>
        <p className="text-xs text-muted-foreground">{explicacion}</p>
      </div>

      {filas.length === 0 ? (
        <p className="rounded-lg border border-dashed px-4 py-3 text-sm text-muted-foreground">{vacio}</p>
      ) : (
        <ul className="divide-y rounded-lg border bg-card">
          {filas.map((f) => (
            <Fila key={f.contacto_id} f={f} ahora={ahora} />
          ))}
        </ul>
      )}
    </section>
  );
}

function Fila({ f, ahora }: { f: Callado; ahora: number }) {
  // Escribió DESPUÉS de que el bot se callara: es la señal de que una
  // conversación se puede estar pudriendo. Es un hecho, no un juicio.
  const escribioDespues =
    f.ultimo_entrante_at !== null &&
    f.callado_desde !== null &&
    ms(f.ultimo_entrante_at) > ms(f.callado_desde);

  return (
    <li className="flex flex-wrap items-start justify-between gap-x-4 gap-y-2 px-4 py-3">
      <div className="flex min-w-0 items-start gap-3">
        <span className="grid size-8 shrink-0 place-items-center rounded-full bg-accent text-xs font-semibold text-accent-foreground">
          {iniciales(f.nombre)}
        </span>
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
            <Link href={`/contactos/${f.contacto_id}`} className="font-medium hover:text-primary">
              {f.nombre || 'Sin nombre'}
            </Link>
            <span className="rounded-4xl bg-muted px-2 py-0.5 text-xs text-muted-foreground">
              {f.motivo ? MOTIVO[f.motivo] : 'Sin motivo anotado'}
            </span>
          </div>
          <p className="text-xs text-muted-foreground">
            {f.telefono_e164 && <span className="tabular">{telefonoLegible(f.telefono_e164)} · </span>}
            {porQue(f, ahora)}
          </p>
        </div>
      </div>

      <div className="flex flex-col items-start gap-0.5 text-xs sm:items-end sm:text-right">
        <span className="text-foreground">Callado {tiempoRelativo(f.callado_desde)}</span>
        {f.ultimo_entrante_at ? (
          <span
            className={`inline-flex items-center gap-1 ${
              escribioDespues ? 'font-medium text-warning' : 'text-muted-foreground'
            }`}
          >
            <MessageCircle className="size-3" />
            {escribioDespues ? 'Escribió después, ' : 'Escribió '}
            {tiempoRelativo(f.ultimo_entrante_at)}
          </span>
        ) : (
          <span className="text-muted-foreground">No ha escrito</span>
        )}
      </div>
    </li>
  );
}

/** Por qué está callado y si vuelve: lo que la persona que mira necesita para decidir. */
function porQue(f: Callado, ahora: number): string {
  // Los crones pasan cada 5 minutos: entre que vence y que vuelve, "vuelve
  // solo hace 3 minutos" no se entendería.
  const vuelve =
    f.vuelve_at && ms(f.vuelve_at) <= ahora
      ? 'Ya le toca volver: el bot lo retoma en unos minutos'
      : `Vuelve solo ${tiempoRelativo(f.vuelve_at)}`;
  switch (f.motivo) {
    case 'relevo':
      return `Le escribió alguien del equipo. ${vuelve} si nadie más le escribe.`;
    case 'manual':
      return f.callado_por_nombre
        ? `Lo apagó ${f.callado_por_nombre}. Un apagado a mano no vuelve solo.`
        : 'Se apagó a mano. Un apagado a mano no vuelve solo.';
    case 'escalamiento':
      if (f.vuelve_at) return `Nadie lo ha atendido todavía. ${vuelve}.`;
      if (f.atendido) return 'Alguien del equipo lo atendió, así que el bot ya no vuelve solo.';
      if (!f.bot_caduca) return 'Callado desde antes del 1 oct: se dejó para que lo atienda una persona.';
      return 'No vuelve solo.';
    default:
      return 'No vuelve solo.';
  }
}

function ms(fecha: string | null): number {
  return fecha ? new Date(fecha).getTime() : 0;
}
