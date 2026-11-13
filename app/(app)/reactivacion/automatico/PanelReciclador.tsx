'use client';

import { useMemo, useState, useTransition } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { AlertTriangle, Loader2, Recycle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { tiempoRelativo, telefonoLegible } from '@/lib/formato';
import { guardarReciclador } from './acciones';

export interface ConfigReciclador {
  activo: boolean;
  simulacion: boolean;
  horas_silencio: number;
  max_intentos: number;
  dias_atras: number;
  tope_diario: number;
  plantilla_id: string | null;
  ultimo_aviso: string | null;
  ultima_pasada_at: string | null;
}

export interface PlantillaReciclador {
  id: string;
  nombre: string;
  cuerpo: string;
  categoria: string;
  estado_meta: string;
}

export interface Resumen {
  enviados: number;
  simulados: number;
  fallidos: number;
  respondieron: number;
  en_espera: number;
}

export interface Candidato {
  contacto_id: string;
  nombre: string | null;
  telefono_e164: string | null;
  ultimo_nuestro_at: string;
  intento: number;
}

export interface Intento {
  intento_id: string;
  contacto_id: string;
  nombre: string | null;
  telefono_e164: string | null;
  numero: number;
  simulado: boolean;
  creado_at: string;
  estado: string;
  error: string | null;
  respondio_at: string | null;
}

// Los valores por defecto son los que decidió Samuel el 13 nov: 2 intentos
// y 7 días hacia atrás. Las horas arrancan en 12.
const POR_DEFECTO: Omit<ConfigReciclador, 'ultimo_aviso' | 'ultima_pasada_at'> = {
  activo: false,
  simulacion: true,
  horas_silencio: 12,
  max_intentos: 2,
  dias_atras: 7,
  tope_diario: 50,
  plantilla_id: null,
};

const HORAS_SUGERIDAS = [9, 12, 24, 48];

const ETIQUETA_ESTADO: Record<string, string> = {
  aprobada: 'aprobada',
  enviada: 'en revisión de Meta',
  rechazada: 'rechazada',
  borrador: 'borrador',
};

function variablesDe(cuerpo: string): string[] {
  return [...cuerpo.matchAll(/\{\{\s*([a-z_]+)\s*\}\}/g)].map((m) => m[1]);
}

// El reciclador solo sabe rellenar {{nombre}} (mismo filtro que la base).
function sirveParaReciclar(p: PlantillaReciclador): boolean {
  return variablesDe(p.cuerpo).every((v) => v === 'nombre');
}

export function PanelReciclador({
  linea,
  config,
  plantillas,
  resumen,
  candidatos,
  historial,
  puedeEditar,
}: {
  linea: { id: string; nombre: string; telefono: string | null };
  config: ConfigReciclador | null;
  plantillas: PlantillaReciclador[];
  resumen: Resumen | null;
  candidatos: Candidato[];
  historial: Intento[];
  puedeEditar: boolean;
}) {
  const router = useRouter();
  const [pendiente, iniciar] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [guardado, setGuardado] = useState(false);

  const inicial = config ?? { ...POR_DEFECTO, ultimo_aviso: null, ultima_pasada_at: null };
  const [activo, setActivo] = useState(inicial.activo);
  const [simulacion, setSimulacion] = useState(inicial.simulacion);
  const [horas, setHoras] = useState(inicial.horas_silencio);
  const [intentos, setIntentos] = useState(inicial.max_intentos);
  const [dias, setDias] = useState(inicial.dias_atras);
  const [tope, setTope] = useState(inicial.tope_diario);
  const [plantillaId, setPlantillaId] = useState<string | null>(inicial.plantilla_id);

  const plantilla = plantillas.find((p) => p.id === plantillaId) ?? null;
  const vistaPrevia = useMemo(
    () => plantilla?.cuerpo.replace(/\{\{\s*nombre\s*\}\}/g, 'Ana') ?? null,
    [plantilla]
  );

  const cambiado =
    !config ||
    activo !== config.activo ||
    simulacion !== config.simulacion ||
    horas !== config.horas_silencio ||
    intentos !== config.max_intentos ||
    dias !== config.dias_atras ||
    tope !== config.tope_diario ||
    plantillaId !== config.plantilla_id;

  const guardar = () => {
    setError(null);
    setGuardado(false);
    iniciar(async () => {
      const r = await guardarReciclador({
        lineaId: linea.id,
        activo,
        simulacion,
        horasSilencio: horas,
        maxIntentos: intentos,
        diasAtras: dias,
        topeDiario: tope,
        plantillaId,
      });
      if (!r.ok) {
        setError(r.error ?? 'No se pudo guardar.');
        return;
      }
      setGuardado(true);
      router.refresh();
    });
  };

  const tasa =
    resumen && resumen.enviados > 0
      ? Math.round((resumen.respondieron / resumen.enviados) * 100)
      : null;

  return (
    <div className="grid grid-cols-[minmax(0,1fr)] gap-5 lg:grid-cols-[minmax(0,26rem)_minmax(0,1fr)]">
      {/* ─── La configuración ─────────────────────────────────────── */}
      <section className="flex flex-col gap-4 rounded-xl border bg-card p-4">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h2 className="flex items-center gap-1.5 font-medium">
              <Recycle className="size-4" /> {linea.nombre}
            </h2>
            <p className="tabular text-xs text-muted-foreground">
              {telefonoLegible(linea.telefono) ?? 'sin número'}
            </p>
          </div>
          <Interruptor
            encendido={activo}
            onCambio={setActivo}
            deshabilitado={!puedeEditar || pendiente}
          />
        </div>

        {config?.ultimo_aviso && (
          <p className="flex gap-2 rounded-lg bg-warning/10 px-3 py-2 text-sm text-warning">
            <AlertTriangle className="mt-0.5 size-4 shrink-0" />
            {config.ultimo_aviso}
          </p>
        )}

        <Campo etiqueta="Modo">
          <div className="grid grid-cols-2 gap-1 rounded-lg border p-1 text-sm">
            {[
              { valor: true, texto: 'Simulación' },
              { valor: false, texto: 'Enviar de verdad' },
            ].map((o) => (
              <button
                key={o.texto}
                type="button"
                disabled={!puedeEditar || pendiente}
                onClick={() => setSimulacion(o.valor)}
                className={`rounded-md px-2 py-1.5 font-medium transition-colors ${
                  simulacion === o.valor
                    ? 'bg-primary text-primary-foreground'
                    : 'text-muted-foreground hover:text-foreground'
                }`}
              >
                {o.texto}
              </button>
            ))}
          </div>
          <p className="text-xs text-muted-foreground">
            {simulacion
              ? 'Anota a quién le escribiría, sin mandar nada. Úsalo primero para revisar la lista.'
              : 'Manda la plantilla por WhatsApp. Cada mensaje de marketing tiene costo en Meta.'}
          </p>
        </Campo>

        <Campo etiqueta="Horas de silencio antes de escribir">
          <div className="flex flex-wrap items-center gap-1.5">
            {HORAS_SUGERIDAS.map((h) => (
              <button
                key={h}
                type="button"
                disabled={!puedeEditar || pendiente}
                onClick={() => setHoras(h)}
                className={`tabular h-8 rounded-lg border px-3 text-sm font-medium ${
                  horas === h
                    ? 'border-primary bg-primary/10 text-primary'
                    : 'bg-background text-muted-foreground hover:text-foreground'
                }`}
              >
                {h} h
              </button>
            ))}
            <input
              type="number"
              min={1}
              max={168}
              value={horas}
              disabled={!puedeEditar || pendiente}
              onChange={(e) => setHoras(Number(e.target.value))}
              aria-label="Horas de silencio, a mano"
              className="tabular h-8 w-20 rounded-lg border bg-background px-2.5 text-sm"
            />
          </div>
          <p className="text-xs text-muted-foreground">
            Cuenta desde nuestro último mensaje sin respuesta. Es también lo que espera entre un
            intento y el siguiente.
          </p>
        </Campo>

        <div className="grid grid-cols-3 gap-3">
          <Campo etiqueta="Intentos">
            <select
              value={intentos}
              disabled={!puedeEditar || pendiente}
              onChange={(e) => setIntentos(Number(e.target.value))}
              className="h-8 rounded-lg border bg-background px-2.5 text-sm"
            >
              {[1, 2, 3].map((n) => (
                <option key={n} value={n}>
                  {n}
                </option>
              ))}
            </select>
          </Campo>
          <Campo etiqueta="Días atrás">
            <input
              type="number"
              min={1}
              max={30}
              value={dias}
              disabled={!puedeEditar || pendiente}
              onChange={(e) => setDias(Number(e.target.value))}
              className="tabular h-8 rounded-lg border bg-background px-2.5 text-sm"
            />
          </Campo>
          <Campo etiqueta="Tope al día">
            <input
              type="number"
              min={1}
              max={1000}
              value={tope}
              disabled={!puedeEditar || pendiente}
              onChange={(e) => setTope(Number(e.target.value))}
              className="tabular h-8 rounded-lg border bg-background px-2.5 text-sm"
            />
          </Campo>
        </div>

        <Campo etiqueta="Plantilla">
          <select
            value={plantillaId ?? ''}
            disabled={!puedeEditar || pendiente}
            onChange={(e) => setPlantillaId(e.target.value || null)}
            className="h-8 rounded-lg border bg-background px-2.5 text-sm"
          >
            <option value="">Elige una plantilla…</option>
            {plantillas.map((p) => (
              <option key={p.id} value={p.id} disabled={!sirveParaReciclar(p)}>
                {p.nombre} · {ETIQUETA_ESTADO[p.estado_meta] ?? p.estado_meta}
                {!sirveParaReciclar(p) ? ' · usa variables que no se pueden llenar' : ''}
              </option>
            ))}
          </select>
          {plantillas.length === 0 && (
            <p className="text-xs text-muted-foreground">
              Esta línea no tiene plantillas. Créala en{' '}
              <Link href="/plantillas" className="text-primary hover:underline">
                Plantillas
              </Link>{' '}
              (categoría marketing) y espera la aprobación de Meta.
            </p>
          )}
          {vistaPrevia && (
            <p className="rounded-lg bg-muted px-3 py-2 text-sm whitespace-pre-wrap">{vistaPrevia}</p>
          )}
        </Campo>

        <p className="text-xs text-muted-foreground">
          Escribe de lunes a viernes de 8:00 a 18:00 y los sábados de 8:00 a 13:00, nunca en
          festivo. No le escribe a quien pidió no recibir mensajes, a quien tiene el bot callado
          (lo atiende una persona), a quien tiene una visita agendada ni a inquilinos con un caso
          abierto.
        </p>

        {puedeEditar ? (
          <div className="flex items-center gap-3">
            <Button onClick={guardar} disabled={pendiente || !cambiado}>
              {pendiente && <Loader2 className="size-4 animate-spin" />}
              Guardar
            </Button>
            {guardado && !cambiado && <span className="text-sm text-muted-foreground">Guardado.</span>}
            {error && <span className="text-sm text-destructive">{error}</span>}
          </div>
        ) : (
          <p className="text-xs text-muted-foreground">Solo un administrador puede cambiar esto.</p>
        )}

        {config?.ultima_pasada_at && (
          <p className="text-xs text-muted-foreground">
            Última revisión {tiempoRelativo(config.ultima_pasada_at)}.
          </p>
        )}
      </section>

      {/* ─── Lo que hace ──────────────────────────────────────────── */}
      <div className="flex min-w-0 flex-col gap-5">
        <section className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          <Cifra etiqueta="Enviados (7 días)" valor={resumen?.enviados ?? 0} />
          <Cifra
            etiqueta="Respondieron en 72 h"
            valor={resumen?.respondieron ?? 0}
            nota={tasa !== null ? `${tasa} %` : undefined}
          />
          <Cifra etiqueta="Simulados (7 días)" valor={resumen?.simulados ?? 0} />
          <Cifra etiqueta="Esperan turno ahora" valor={resumen?.en_espera ?? 0} />
        </section>

        <section className="flex flex-col gap-2">
          <h2 className="text-sm font-medium">
            {config ? 'A quién le escribiría ahora' : 'Guarda la configuración para ver a quién le escribiría'}
          </h2>
          {config && candidatos.length === 0 && (
            <p className="rounded-xl border border-dashed py-8 text-center text-sm text-muted-foreground">
              Nadie cumple las condiciones en este momento.
            </p>
          )}
          {candidatos.length > 0 && (
            <ul className="flex flex-col divide-y rounded-xl border bg-card">
              {candidatos.map((c) => (
                <li key={c.contacto_id} className="flex flex-wrap items-baseline justify-between gap-2 px-3.5 py-2.5">
                  <span className="flex flex-wrap items-baseline gap-x-2">
                    <Link href={`/contactos/${c.contacto_id}`} className="font-medium hover:underline">
                      {c.nombre?.trim() || 'Sin nombre'}
                    </Link>
                    <span className="tabular text-xs text-muted-foreground">
                      {telefonoLegible(c.telefono_e164)}
                    </span>
                  </span>
                  <span className="text-xs text-muted-foreground">
                    sin respuesta {tiempoRelativo(c.ultimo_nuestro_at)} · intento {c.intento}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="flex flex-col gap-2">
          <h2 className="text-sm font-medium">Lo último que hizo</h2>
          {historial.length === 0 ? (
            <p className="rounded-xl border border-dashed py-8 text-center text-sm text-muted-foreground">
              Todavía no ha escrito a nadie.
            </p>
          ) : (
            <ul className="flex flex-col divide-y rounded-xl border bg-card">
              {historial.map((i) => (
                <li key={i.intento_id} className="flex flex-wrap items-baseline justify-between gap-2 px-3.5 py-2.5">
                  <span className="flex flex-wrap items-baseline gap-x-2">
                    <Link href={`/contactos/${i.contacto_id}`} className="font-medium hover:underline">
                      {i.nombre?.trim() || 'Sin nombre'}
                    </Link>
                    <span className="text-xs text-muted-foreground">
                      intento {i.numero} · {tiempoRelativo(i.creado_at)}
                    </span>
                  </span>
                  <span className="flex items-center gap-2 text-xs">
                    <EstadoIntento estado={i.estado} error={i.error} />
                    {i.respondio_at && (
                      <span className="font-medium text-primary">
                        respondió {tiempoRelativo(i.respondio_at)}
                      </span>
                    )}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
    </div>
  );
}

function Interruptor({
  encendido,
  onCambio,
  deshabilitado,
}: {
  encendido: boolean;
  onCambio: (v: boolean) => void;
  deshabilitado: boolean;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={encendido}
      disabled={deshabilitado}
      onClick={() => onCambio(!encendido)}
      className="flex items-center gap-2 text-sm font-medium disabled:opacity-60"
    >
      <span className={encendido ? 'text-foreground' : 'text-muted-foreground'}>
        {encendido ? 'Encendido' : 'Apagado'}
      </span>
      <span
        aria-hidden
        className={`relative inline-flex h-5 w-9 shrink-0 rounded-full transition-colors ${
          encendido ? 'bg-primary' : 'bg-muted-foreground/30'
        }`}
      >
        <span
          className={`absolute top-0.5 size-4 rounded-full bg-white shadow-xs transition-all ${
            encendido ? 'left-4.5' : 'left-0.5'
          }`}
        />
      </span>
    </button>
  );
}

function Campo({ etiqueta, children }: { etiqueta: string; children: React.ReactNode }) {
  return (
    // div y no label: dentro hay grupos de botones, y un label activa el
    // primero al hacer clic en el texto.
    <div className="flex flex-col gap-1.5">
      <span className="text-xs font-medium text-muted-foreground">{etiqueta}</span>
      {children}
    </div>
  );
}

function Cifra({ etiqueta, valor, nota }: { etiqueta: string; valor: number; nota?: string }) {
  return (
    <div className="rounded-xl border bg-card px-3.5 py-3">
      <p className="text-xs text-muted-foreground">{etiqueta}</p>
      <p className="tabular text-xl font-semibold">
        {valor}
        {nota && <span className="ml-1.5 text-sm font-normal text-muted-foreground">{nota}</span>}
      </p>
    </div>
  );
}

function EstadoIntento({ estado, error }: { estado: string; error: string | null }) {
  const texto: Record<string, string> = {
    simulado: 'simulado',
    pendiente: 'saliendo',
    enviado: 'enviado',
    fallido: 'no salió',
  };
  return (
    <span
      title={error ?? undefined}
      className={estado === 'fallido' ? 'text-destructive' : 'text-muted-foreground'}
    >
      {texto[estado] ?? estado}
    </span>
  );
}
