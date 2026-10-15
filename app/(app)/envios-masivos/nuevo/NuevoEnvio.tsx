'use client';

import { useMemo, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { FileSpreadsheet, Info, Loader2, TriangleAlert, Upload } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { comoPesos, leerArchivo, type ArchivoLeido } from '@/lib/archivos';
import { variablesDe } from '@/lib/plantillas';
import { crearEnvioMasivo } from '../acciones';

export interface LineaEnvio {
  wa_phone_number_id: string;
  nombre: string;
  embudo: string;
}

export interface PlantillaEnvio {
  id: string;
  nombre: string;
  cuerpo: string;
  categoria: string;
  estado_meta: string;
  wa_phone_number_id: string;
}

/** Cómo suelen llamarse las columnas en un archivo de cartera. */
const PISTAS: Record<string, RegExp> = {
  telefono: /cel|tel[eé]f|m[oó]vil|whats|contacto/i,
  nombre: /nombre|inquilino|arrendatario|cliente|deudor/i,
  inmueble: /inmueble|direcci[oó]n|propiedad|predio|apto|apartamento/i,
  barrio: /barrio|sector/i,
  ciudad: /ciudad|municipio/i,
  monto: /saldo|valor|monto|deuda|canon|total|debe/i,
  fecha_limite: /fecha|vence|venc|l[ií]mite|pago/i,
  dias_mora: /mora|d[ií]as/i,
  referencia: /ref|contrato|c[oó]digo|n[uú]mero/i,
};

const SUFIJO_PESOS = ' (en pesos)';

function adivinar(columnas: string[], pista: RegExp | undefined): string {
  return (pista && columnas.find((c) => pista.test(c))) ?? '';
}

function pareceNumero(valores: string[]): boolean {
  const muestra = valores.filter(Boolean).slice(0, 20);
  return muestra.length > 0 && muestra.every((v) => /^\$?\s*[\d.]+$/.test(v));
}

export function NuevoEnvio({
  lineas,
  plantillas,
}: {
  lineas: LineaEnvio[];
  plantillas: PlantillaEnvio[];
}) {
  const router = useRouter();
  const [archivo, setArchivo] = useState<ArchivoLeido | null>(null);
  const [leyendo, setLeyendo] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [columnaTelefono, setColumnaTelefono] = useState('');
  const [columnaNombre, setColumnaNombre] = useState('');
  const [plantillaId, setPlantillaId] = useState('');
  const [mapeo, setMapeo] = useState<Record<string, string>>({});
  const [montoEnPesos, setMontoEnPesos] = useState(true);
  const [abrirCaso, setAbrirCaso] = useState(true);
  const [nombre, setNombre] = useState('');
  const [preparando, iniciar] = useTransition();

  const plantilla = plantillas.find((p) => p.id === plantillaId) ?? null;
  const linea = lineas.find((l) => l.wa_phone_number_id === plantilla?.wa_phone_number_id) ?? null;
  const variables = useMemo(() => (plantilla ? variablesDe(plantilla.cuerpo) : []), [plantilla]);

  async function cargar(f: File | undefined) {
    if (!f) return;
    setError(null);
    setLeyendo(true);
    try {
      const leido = await leerArchivo(f);
      setArchivo(leido);
      setColumnaTelefono(adivinar(leido.columnas, PISTAS.telefono));
      setColumnaNombre(adivinar(leido.columnas, PISTAS.nombre));
      setNombre((n) => n || leido.nombre.replace(/\.(xlsx|csv|txt)$/i, ''));
      setMapeo({});
    } catch (e) {
      setArchivo(null);
      setError(e instanceof Error ? e.message : 'No se pudo leer el archivo.');
    } finally {
      setLeyendo(false);
    }
  }

  function elegirPlantilla(id: string) {
    setPlantillaId(id);
    const p = plantillas.find((x) => x.id === id);
    if (!p || !archivo) return;
    // Propuesta inicial: el nombre sale de la columna del nombre y lo demás
    // de la columna que se le parezca. Se puede cambiar todo.
    const propuesta: Record<string, string> = {};
    for (const v of variablesDe(p.cuerpo)) {
      propuesta[v] = v === 'nombre' ? columnaNombre : adivinar(archivo.columnas, PISTAS[v]);
    }
    setMapeo(propuesta);
    if (propuesta.monto) {
      setMontoEnPesos(pareceNumero(archivo.filas.map((f) => f[propuesta.monto])));
    }
  }

  /**
   * Lo que de verdad se manda: si el monto va en pesos, se añade una
   * columna «… (en pesos)» con el valor ya formateado. La original no se
   * toca, porque vuelve tal cual en el archivo de resultados.
   */
  const preparado = useMemo(() => {
    if (!archivo) return null;
    const columnaMonto = mapeo.monto;
    if (!columnaMonto || !montoEnPesos) {
      return { columnas: archivo.columnas, filas: archivo.filas, variables: mapeo };
    }
    const nueva = `${columnaMonto}${SUFIJO_PESOS}`;
    return {
      columnas: [...archivo.columnas, nueva],
      filas: archivo.filas.map((f) => ({ ...f, [nueva]: comoPesos(f[columnaMonto] ?? '') })),
      variables: { ...mapeo, monto: nueva },
    };
  }, [archivo, mapeo, montoEnPesos]);

  const vistaPrevia = useMemo(() => {
    if (!preparado || !plantilla) return [];
    return preparado.filas.slice(0, 3).map((f) =>
      plantilla.cuerpo.replace(/\{\{\s*([a-z_]+)\s*\}\}/g, (_, v: string) => {
        const valor = f[preparado.variables[v] ?? '']?.trim();
        return valor || `[sin ${v.replace('_', ' ')}]`;
      })
    );
  }, [preparado, plantilla]);

  const sinTelefono = archivo && columnaTelefono
    ? archivo.filas.filter((f) => !f[columnaTelefono]?.trim()).length
    : 0;
  const faltaMapeo = variables.filter((v) => !mapeo[v]);
  const listo = Boolean(archivo && columnaTelefono && plantilla && faltaMapeo.length === 0 && nombre.trim());

  function preparar() {
    if (!preparado || !plantilla || !archivo) return;
    setError(null);
    iniciar(async () => {
      const r = await crearEnvioMasivo({
        nombre: nombre.trim(),
        archivoNombre: archivo.nombre,
        columnas: preparado.columnas,
        filas: preparado.filas,
        columnaTelefono,
        columnaNombre: columnaNombre || null,
        plantillaId: plantilla.id,
        variables: preparado.variables,
        abrirCaso: linea?.embudo === 'administrativa' && abrirCaso,
      });
      if (!r.ok || !r.id) {
        setError(r.error ?? 'No se pudo preparar el envío.');
        return;
      }
      router.push(`/envios-masivos/${r.id}`);
    });
  }

  const columnaSelect = (valor: string, cambiar: (v: string) => void, id: string, opcional = false) => (
    <select
      id={id}
      value={valor}
      onChange={(e) => cambiar(e.target.value)}
      className="h-9 w-full rounded-xl border border-input bg-background px-3 text-xs"
    >
      <option value="">{opcional ? '— Ninguna —' : '— Elige una columna —'}</option>
      {archivo?.columnas.map((c) => (
        <option key={c} value={c}>
          {c}
        </option>
      ))}
    </select>
  );

  if (lineas.length === 0) {
    return (
      <div className="flex items-start gap-2 rounded-xl border border-warning/30 bg-warning/10 p-4 text-sm text-warning">
        <TriangleAlert className="mt-0.5 size-4 shrink-0" />
        <span>
          Todavía no hay ninguna línea de WhatsApp conectada. Un envío masivo sale por una línea y con una
          plantilla aprobada en ella: primero hay que conectar la línea (por ejemplo, la administrativa) en
          «Líneas».
        </span>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-5">
      {/* 1 · El archivo */}
      <section className="flex flex-col gap-3 rounded-2xl border border-border/70 bg-card p-4">
        <h2 className="text-sm font-semibold">1 · El archivo</h2>
        <label
          htmlFor="archivo"
          className="flex cursor-pointer flex-col items-center gap-2 rounded-xl border border-dashed border-border/80 bg-muted/20 p-6 text-center text-xs text-muted-foreground hover:bg-muted/40"
        >
          {leyendo ? (
            <Loader2 className="size-6 animate-spin text-primary" />
          ) : archivo ? (
            <FileSpreadsheet className="size-6 text-emerald-600" />
          ) : (
            <Upload className="size-6" />
          )}
          {archivo ? (
            <span>
              <b className="text-foreground">{archivo.nombre}</b> · {archivo.filas.length.toLocaleString('es-CO')}{' '}
              filas · {archivo.columnas.length} columnas. Pulsa para cambiarlo.
            </span>
          ) : (
            <span>Sube el archivo de cartera (.xlsx o .csv). Se lee aquí, en tu navegador.</span>
          )}
        </label>
        <input
          id="archivo"
          type="file"
          accept=".xlsx,.csv,.txt"
          className="sr-only"
          onChange={(e) => cargar(e.target.files?.[0])}
        />
      </section>

      {archivo && (
        <>
          {/* 2 · Las columnas */}
          <section className="flex flex-col gap-3 rounded-2xl border border-border/70 bg-card p-4">
            <h2 className="text-sm font-semibold">2 · A quién</h2>
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="col-telefono" className="text-xs font-semibold">
                  Columna del teléfono
                </Label>
                {columnaSelect(columnaTelefono, setColumnaTelefono, 'col-telefono')}
                {sinTelefono > 0 && (
                  <span className="text-[11px] text-warning">
                    {sinTelefono} {sinTelefono === 1 ? 'fila no tiene' : 'filas no tienen'} teléfono: no se les
                    enviará.
                  </span>
                )}
              </div>
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="col-nombre" className="text-xs font-semibold">
                  Columna del nombre
                </Label>
                {columnaSelect(columnaNombre, setColumnaNombre, 'col-nombre', true)}
                <span className="text-[11px] text-muted-foreground">
                  Con él se crea el contacto de quien todavía no está en el CRM.
                </span>
              </div>
            </div>
          </section>

          {/* 3 · La plantilla */}
          <section className="flex flex-col gap-3 rounded-2xl border border-border/70 bg-card p-4">
            <h2 className="text-sm font-semibold">3 · Qué se le dice</h2>
            {plantillas.length === 0 ? (
              <p className="flex items-start gap-2 rounded-xl border border-warning/30 bg-warning/10 p-3 text-xs text-warning">
                <TriangleAlert className="mt-0.5 size-3.5 shrink-0" />
                No hay plantillas de WhatsApp en ninguna línea. Créala en «Plantillas» y mándala a Meta: la de un
                recordatorio de pago es de utilidad.
              </p>
            ) : (
              <select
                value={plantillaId}
                onChange={(e) => elegirPlantilla(e.target.value)}
                className="h-9 w-full rounded-xl border border-input bg-background px-3 text-xs"
              >
                <option value="">— Elige la plantilla —</option>
                {lineas.map((l) => (
                  <optgroup key={l.wa_phone_number_id} label={l.nombre}>
                    {plantillas
                      .filter((p) => p.wa_phone_number_id === l.wa_phone_number_id)
                      .map((p) => (
                        <option key={p.id} value={p.id}>
                          {p.nombre}
                          {p.estado_meta !== 'aprobada' ? ' (todavía sin aprobar)' : ''}
                        </option>
                      ))}
                  </optgroup>
                ))}
              </select>
            )}

            {plantilla && plantilla.estado_meta !== 'aprobada' && (
              <p className="flex items-start gap-2 rounded-xl border border-blue-500/30 bg-blue-500/10 p-2.5 text-xs text-blue-900 dark:text-blue-300">
                <Info className="mt-0.5 size-3.5 shrink-0" />
                Meta todavía no aprobó esta plantilla. Puedes preparar el borrador, pero no se podrá lanzar hasta
                que la apruebe.
              </p>
            )}

            {plantilla && variables.length > 0 && (
              <div className="grid gap-3 sm:grid-cols-2">
                {variables.map((v) => (
                  <div key={v} className="flex flex-col gap-1.5">
                    <Label htmlFor={`var-${v}`} className="text-xs font-semibold">
                      <code className="font-mono">{`{{${v}}}`}</code> sale de
                    </Label>
                    {columnaSelect(mapeo[v] ?? '', (c) => setMapeo((m) => ({ ...m, [v]: c })), `var-${v}`)}
                    {v === 'monto' && mapeo.monto && (
                      <label className="flex items-center gap-2 text-[11px] text-muted-foreground">
                        <input
                          type="checkbox"
                          checked={montoEnPesos}
                          onChange={(e) => setMontoEnPesos(e.target.checked)}
                        />
                        Escribirlo en pesos (1250000 → $1.250.000)
                      </label>
                    )}
                  </div>
                ))}
              </div>
            )}

            {linea?.embudo === 'administrativa' && (
              <label className="flex items-start gap-2 rounded-xl border border-border/60 bg-muted/20 p-3 text-xs">
                <input
                  type="checkbox"
                  className="mt-0.5"
                  checked={abrirCaso}
                  onChange={(e) => setAbrirCaso(e.target.checked)}
                />
                <span>
                  <b>Abrir o mover su caso administrativo a «En mora».</b> Quien no tenga caso lo tendrá; quien esté
                  «Al día» pasa a «En mora». Un caso en acuerdo de pago o en terminación no se toca.
                </span>
              </label>
            )}
          </section>

          {/* 4 · La vista previa y el nombre */}
          {plantilla && (
            <section className="flex flex-col gap-3 rounded-2xl border border-border/70 bg-card p-4">
              <h2 className="text-sm font-semibold">4 · Así le llega</h2>
              <div className="grid gap-3 md:grid-cols-3">
                {vistaPrevia.map((texto, i) => (
                  <div
                    key={i}
                    className="rounded-xl bg-[#efeae2] p-3 dark:bg-[#0b141a] border border-border/40"
                  >
                    <p className="mb-1 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
                      Fila {i + 2}
                    </p>
                    <p className="whitespace-pre-wrap rounded-xl rounded-tl-xs bg-white p-2.5 text-xs shadow-xs dark:bg-[#202c33]">
                      {texto}
                    </p>
                  </div>
                ))}
              </div>

              <div className="flex flex-col gap-1.5">
                <Label htmlFor="nombre-envio" className="text-xs font-semibold">
                  Nombre del envío
                </Label>
                <Input
                  id="nombre-envio"
                  value={nombre}
                  onChange={(e) => setNombre(e.target.value)}
                  maxLength={120}
                  className="h-9 rounded-xl text-sm"
                  placeholder="Cartera de octubre"
                />
              </div>
            </section>
          )}
        </>
      )}

      {error && (
        <p className="flex items-start gap-2 rounded-xl border border-destructive/30 bg-destructive/10 p-3 text-xs text-destructive">
          <TriangleAlert className="mt-0.5 size-3.5 shrink-0" />
          {error}
        </p>
      )}

      {archivo && (
        <div className="flex flex-wrap items-center justify-end gap-3">
          {faltaMapeo.length > 0 && plantilla && (
            <span className="text-xs text-muted-foreground">
              Falta decir de qué columna sale: {faltaMapeo.map((v) => `{{${v}}}`).join(', ')}
            </span>
          )}
          <Button className="h-9 rounded-xl gap-1.5" disabled={!listo || preparando} onClick={preparar}>
            {preparando && <Loader2 className="size-4 animate-spin" />}
            Preparar borrador
          </Button>
        </div>
      )}
    </div>
  );
}
