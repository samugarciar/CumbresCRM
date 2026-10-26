'use client';

import { useEffect, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { Download, Loader2, Pause, Play, Send, Settings2, TriangleAlert, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { descargarResultados } from '@/lib/archivos';
import {
  HORARIO_POR_DEFECTO,
  MOTIVOS,
  RESULTADOS,
  horarioDesdeFormulario,
  type EstadoEnvioMasivo,
  type Horario,
} from '@/lib/envios-masivos';
import {
  ajustarEnvioMasivo,
  cambiarEstadoEnvioMasivo,
  lanzarEnvioMasivo,
  resultadosEnvioMasivo,
} from '../acciones';

interface Ajustes {
  tamanoLote: number;
  minutosEntreLotes: number;
  topeDiario: number;
  frecuenciaDias: number;
  horario: Horario;
}

/** Mientras envía, la página se refresca sola: los acuses llegan solos. */
const REFRESCO_MS = 30_000;

export function PanelEnvio({
  id,
  estado,
  listos,
  plantillaAprobada,
  ajustes,
}: {
  id: string;
  estado: EstadoEnvioMasivo;
  listos: number;
  plantillaAprobada: boolean;
  ajustes: Ajustes;
}) {
  const router = useRouter();
  const [pendiente, iniciar] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [confirmacion, setConfirmacion] = useState('');
  const [cancelando, setCancelando] = useState(false);
  const [viendoAjustes, setViendoAjustes] = useState(false);

  useEffect(() => {
    if (estado !== 'en_curso') return;
    const t = setInterval(() => router.refresh(), REFRESCO_MS);
    return () => clearInterval(t);
  }, [estado, router]);

  function correr(accion: () => Promise<{ ok: boolean; error?: string }>) {
    setError(null);
    iniciar(async () => {
      const r = await accion();
      if (!r.ok) setError(r.error ?? 'No se pudo.');
      else {
        setCancelando(false);
        setConfirmacion('');
        router.refresh();
      }
    });
  }

  function descargar() {
    setError(null);
    iniciar(async () => {
      const r = await resultadosEnvioMasivo(id);
      if (!r.ok || !r.filas || !r.columnas) {
        setError(r.error ?? 'No se pudieron leer los resultados.');
        return;
      }
      await descargarResultados({
        nombreArchivo: r.archivo ?? 'envio.xlsx',
        columnas: r.columnas,
        filas: r.filas,
        etiquetaResultado: (x) => RESULTADOS[x] ?? x,
        etiquetaMotivo: (x) => MOTIVOS[x] ?? x,
      });
    });
  }

  const puedeAjustar = estado === 'borrador' || estado === 'pausado';
  const puedeCancelar = estado === 'borrador' || estado === 'en_curso' || estado === 'pausado';

  return (
    <section className="flex flex-col gap-3 rounded-xl border border-border/70 bg-card p-4">
      {estado === 'borrador' && (
        <div className="flex flex-col gap-2">
          <h2 className="text-sm font-semibold">Lanzar</h2>
          {!plantillaAprobada ? (
            <p className="flex items-start gap-2 text-xs text-warning">
              <TriangleAlert className="mt-0.5 size-3.5 shrink-0" />
              La plantilla todavía no está aprobada por Meta. Cuando la apruebe (y se sincronice en
              «Plantillas»), se podrá lanzar.
            </p>
          ) : listos === 0 ? (
            <p className="text-xs text-muted-foreground">No queda nadie a quien enviarle.</p>
          ) : (
            <>
              <p className="text-xs text-muted-foreground">
                Para lanzarlo, escribe cuántas personas lo van a recibir: <b className="text-foreground">{listos}</b>.
                Antes de salir se vuelve a mirar quién pidió no recibir más mensajes.
              </p>
              <div className="flex flex-wrap items-center gap-2">
                <Input
                  inputMode="numeric"
                  value={confirmacion}
                  onChange={(e) => setConfirmacion(e.target.value.replace(/\D/g, ''))}
                  placeholder={String(listos)}
                  className="h-9 w-28 rounded-xl text-sm tabular"
                  aria-label="Número de destinatarios"
                />
                <Button
                  className="h-9 rounded-xl gap-1.5"
                  disabled={pendiente || Number(confirmacion) !== listos}
                  onClick={() => correr(() => lanzarEnvioMasivo(id, Number(confirmacion)))}
                >
                  {pendiente ? <Loader2 className="size-4 animate-spin" /> : <Send className="size-4" />}
                  Lanzar a {listos} {listos === 1 ? 'persona' : 'personas'}
                </Button>
              </div>
            </>
          )}
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2">
        {estado === 'en_curso' && (
          <Button
            variant="outline"
            className="h-9 rounded-xl gap-1.5"
            disabled={pendiente}
            onClick={() => correr(() => cambiarEstadoEnvioMasivo(id, 'pausar'))}
          >
            <Pause className="size-4" />
            Pausar
          </Button>
        )}
        {estado === 'pausado' && (
          <Button
            className="h-9 rounded-xl gap-1.5"
            disabled={pendiente}
            onClick={() => correr(() => cambiarEstadoEnvioMasivo(id, 'reanudar'))}
          >
            <Play className="size-4" />
            Reanudar
          </Button>
        )}
        {puedeAjustar && (
          <Button
            variant="outline"
            className="h-9 rounded-xl gap-1.5"
            onClick={() => setViendoAjustes((v) => !v)}
          >
            <Settings2 className="size-4" />
            Ritmo y horario
          </Button>
        )}
        {estado !== 'borrador' && (
          <Button variant="outline" className="h-9 rounded-xl gap-1.5" disabled={pendiente} onClick={descargar}>
            <Download className="size-4" />
            Descargar resultados
          </Button>
        )}
        {puedeCancelar &&
          (cancelando ? (
            <span className="flex flex-wrap items-center gap-2 text-xs">
              {estado === 'borrador'
                ? 'Se descarta el borrador.'
                : 'Lo que no ha salido ya no saldrá y pasa a «Gestión manual». Lo que salió, salió.'}
              <Button
                variant="destructive"
                size="sm"
                disabled={pendiente}
                onClick={() => correr(() => cambiarEstadoEnvioMasivo(id, 'cancelar'))}
              >
                Sí, cancelar
              </Button>
              <Button variant="ghost" size="sm" onClick={() => setCancelando(false)}>
                No
              </Button>
            </span>
          ) : (
            <Button
              variant="ghost"
              className="h-9 rounded-xl gap-1.5 text-muted-foreground hover:text-destructive"
              onClick={() => setCancelando(true)}
            >
              <X className="size-4" />
              {estado === 'borrador' ? 'Descartar' : 'Cancelar envío'}
            </Button>
          ))}
      </div>

      {viendoAjustes && puedeAjustar && (
        <FormularioAjustes
          inicial={ajustes}
          guardando={pendiente}
          guardar={(a) => correr(() => ajustarEnvioMasivo(id, a))}
        />
      )}

      {error && (
        <p className="flex items-start gap-2 rounded-xl border border-destructive/30 bg-destructive/10 p-3 text-xs text-destructive">
          <TriangleAlert className="mt-0.5 size-3.5 shrink-0" />
          {error}
        </p>
      )}
    </section>
  );
}

function FormularioAjustes({
  inicial,
  guardando,
  guardar,
}: {
  inicial: Ajustes;
  guardando: boolean;
  guardar: (a: Ajustes & { horario: { zona: 'America/Bogota'; franjas: Horario['franjas'] } }) => void;
}) {
  const semanaInicial = inicial.horario.franjas['1'] ?? HORARIO_POR_DEFECTO.franjas['1'];
  const sabadoInicial = inicial.horario.franjas['6'] ?? null;

  const [tamanoLote, setTamanoLote] = useState(inicial.tamanoLote);
  const [minutos, setMinutos] = useState(inicial.minutosEntreLotes);
  const [tope, setTope] = useState(inicial.topeDiario);
  const [frecuencia, setFrecuencia] = useState(inicial.frecuenciaDias);
  const [desde, setDesde] = useState(semanaInicial[0]);
  const [hasta, setHasta] = useState(semanaInicial[1]);
  const [conSabado, setConSabado] = useState(Boolean(sabadoInicial));
  const [sabDesde, setSabDesde] = useState(sabadoInicial?.[0] ?? '08:00');
  const [sabHasta, setSabHasta] = useState(sabadoInicial?.[1] ?? '13:00');

  const numero = (valor: number, cambiar: (n: number) => void, id: string, etiqueta: string, ayuda: string) => (
    <div className="flex flex-col gap-1">
      <Label htmlFor={id} className="text-xs font-semibold">
        {etiqueta}
      </Label>
      <Input
        id={id}
        inputMode="numeric"
        value={String(valor)}
        onChange={(e) => cambiar(Number(e.target.value.replace(/\D/g, '') || 0))}
        className="h-9 rounded-xl text-sm tabular"
      />
      <span className="text-[11px] text-muted-foreground">{ayuda}</span>
    </div>
  );

  return (
    <div className="flex flex-col gap-3 rounded-xl border border-border/60 bg-muted/20 p-3">
      <div className="grid gap-3 sm:grid-cols-4">
        {numero(tamanoLote, setTamanoLote, 'lote', 'Por lote', 'De 1 a 250 mensajes')}
        {numero(minutos, setMinutos, 'minutos', 'Minutos entre lotes', 'Para ver la calidad entre uno y otro')}
        {numero(tope, setTope, 'tope', 'Tope por día', 'Personas distintas en 24 h en la línea')}
        {numero(frecuencia, setFrecuencia, 'frecuencia', 'Días sin repetir', 'A quien recibió otro envío masivo')}
      </div>

      <div className="flex flex-wrap items-end gap-3 text-xs">
        <div className="flex items-center gap-2">
          <span className="font-semibold">Lunes a viernes de</span>
          <Input type="time" value={desde} onChange={(e) => setDesde(e.target.value)} className="h-8 w-28 rounded-lg" />
          <span>a</span>
          <Input type="time" value={hasta} onChange={(e) => setHasta(e.target.value)} className="h-8 w-28 rounded-lg" />
        </div>
        <label className="flex items-center gap-2">
          <input type="checkbox" checked={conSabado} onChange={(e) => setConSabado(e.target.checked)} />
          <span className="font-semibold">Sábados de</span>
        </label>
        <div className="flex items-center gap-2">
          <Input
            type="time"
            disabled={!conSabado}
            value={sabDesde}
            onChange={(e) => setSabDesde(e.target.value)}
            className="h-8 w-28 rounded-lg"
          />
          <span>a</span>
          <Input
            type="time"
            disabled={!conSabado}
            value={sabHasta}
            onChange={(e) => setSabHasta(e.target.value)}
            className="h-8 w-28 rounded-lg"
          />
        </div>
      </div>
      <p className="text-[11px] text-muted-foreground">
        Nunca domingos ni festivos. La Ley 2300 de 2023 limita el horario y la frecuencia de la cobranza: estas cifras
        las debe confirmar el abogado.
      </p>

      <div>
        <Button
          size="sm"
          disabled={guardando}
          onClick={() =>
            guardar({
              tamanoLote,
              minutosEntreLotes: minutos,
              topeDiario: tope,
              frecuenciaDias: frecuencia,
              horario: horarioDesdeFormulario(
                { desde, hasta },
                conSabado ? { desde: sabDesde, hasta: sabHasta } : null
              ) as { zona: 'America/Bogota'; franjas: Horario['franjas'] },
            })
          }
        >
          Guardar ritmo y horario
        </Button>
      </div>
    </div>
  );
}
