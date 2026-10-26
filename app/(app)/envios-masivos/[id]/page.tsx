import Link from 'next/link';
import { notFound } from 'next/navigation';
import { ArrowLeft, TriangleAlert } from 'lucide-react';
import { z } from 'zod';
import { createClient } from '@/lib/supabase/server';
import { fechaLarga, telefonoLegible } from '@/lib/formato';
import {
  ESTADOS,
  MOTIVOS,
  RESULTADOS,
  costoEstimado,
  describirHorario,
  dolares,
  type EstadoEnvioMasivo,
  type Horario,
} from '@/lib/envios-masivos';
import { PanelEnvio } from './PanelEnvio';

interface Resumen {
  total: number;
  en_cola: number;
  excluidos: number;
  cancelados: number;
  enviando: number;
  sin_confirmar: number;
  enviados: number;
  entregados: number;
  leidos: number;
  fallidos: number;
  respondieron: number;
  bajas: number;
  por_motivo: Record<string, number>;
}

interface Fila {
  fila: number;
  nombre: string | null;
  contacto_id: string | null;
  telefono: string | null;
  resultado: string;
  motivo: string | null;
  detalle: string | null;
  error: string | null;
  respondio_at: string | null;
}

/** Cuántas filas se enseñan aquí. Todas, en el archivo de resultados. */
const FILAS_EN_PANTALLA = 200;

export default async function PaginaEnvioMasivo({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!z.string().uuid().safeParse(id).success) notFound();

  const supabase = await createClient();
  const crm = supabase.schema('crm');

  const { data: envio } = await crm
    .from('envios_masivos')
    .select('*, plantillas(nombre, cuerpo, categoria, estado_meta)')
    .eq('id', id)
    .maybeSingle();
  if (!envio) notFound();

  const [{ data: resumenCrudo }, { data: filasCrudas }, { data: linea }, { data: previas }] =
    await Promise.all([
      crm.rpc('resumen_envio_masivo', { p_id: id }),
      crm.rpc('resultados_envio_masivo', { p_id: id }).range(0, FILAS_EN_PANTALLA - 1),
      crm.from('lineas').select('nombre, embudo').eq('wa_phone_number_id', envio.wa_phone_number_id).maybeSingle(),
      crm
        .from('envios_masivos_destinatarios')
        .select('fila, cuerpo')
        .eq('envio_masivo_id', id)
        .eq('estado', 'listo')
        .order('fila')
        .limit(3),
    ]);

  const resumen = resumenCrudo as Resumen | null;
  const filas = (filasCrudas ?? []) as unknown as Fila[];
  const plantilla = envio.plantillas as {
    nombre: string;
    cuerpo: string;
    categoria: string;
    estado_meta: string;
  } | null;
  const estado = envio.estado as EstadoEnvioMasivo;
  const destinatarios = resumen ? resumen.total - resumen.excluidos : 0;
  const listos = resumen?.en_cola ?? 0;
  const [costoMin, costoMax] = costoEstimado(estado === 'borrador' ? listos : destinatarios, plantilla?.categoria ?? 'utilidad');
  // Con pocos destinatarios los dos extremos dicen «menos de US$0,01»: una
  // sola vez, y con mayúscula porque abre la cifra.
  const [textoMin, textoMax] = [dolares(costoMin), dolares(costoMax)];
  const costo = (textoMin === textoMax ? textoMin : `${textoMin} – ${textoMax}`).replace(/^./, (c) =>
    c.toUpperCase()
  );
  // «p. m.» ya trae su punto.
  const lanzado = envio.lanzado_at ? `Lanzado el ${fechaLarga(envio.lanzado_at)}`.replace(/\.?$/, '.') : null;

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-5">
      <header className="flex flex-col gap-1">
        <Link
          href="/envios-masivos"
          className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
        >
          <ArrowLeft className="size-3.5" />
          Envíos masivos
        </Link>
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-xl font-semibold tracking-tight">{envio.nombre}</h1>
          <span className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${ESTADOS[estado].estilo}`}>
            {ESTADOS[estado].texto}
          </span>
        </div>
        <p className="text-sm text-muted-foreground">
          {plantilla?.nombre ?? 'Plantilla archivada'} · por {linea?.nombre ?? 'una línea que ya no está activa'}
          {envio.archivo_nombre ? ` · ${envio.archivo_nombre}` : ''}
        </p>
      </header>

      {envio.ultimo_aviso && (estado === 'en_curso' || estado === 'pausado') && (
        <p className="flex items-start gap-2 rounded-xl border border-warning/30 bg-warning/10 p-3 text-sm text-warning">
          <TriangleAlert className="mt-0.5 size-4 shrink-0" />
          {envio.ultimo_aviso}
        </p>
      )}

      {/* Las cifras */}
      {resumen && (
        <section className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {(estado === 'borrador'
            ? [
                ['Filas del archivo', resumen.total],
                ['Recibirían el mensaje', listos],
                ['No se les enviará', resumen.excluidos],
                ['Costo estimado en Meta', costo],
              ]
            : [
                ['Enviados', `${resumen.enviados} de ${destinatarios}`],
                ['Entregados', resumen.entregados],
                ['Respondieron', resumen.respondieron],
                ['Fallaron', resumen.fallidos],
              ]
          ).map(([titulo, valor]) => (
            <div key={titulo as string} className="rounded-xl border bg-card p-3">
              <p className="text-xs text-muted-foreground">{titulo}</p>
              <p className="mt-0.5 text-lg font-semibold tabular">{valor}</p>
            </div>
          ))}
        </section>
      )}

      {estado === 'borrador' && (
        <p className="-mt-2 text-xs text-muted-foreground">
          El costo es una estimación con la tarifa de {plantilla?.categoria === 'marketing' ? 'marketing' : 'utilidad'}{' '}
          para Colombia que no está verificada contra la tarjeta oficial de Meta.
        </p>
      )}

      {/* Por qué algunas filas no salen */}
      {resumen && Object.keys(resumen.por_motivo).length > 0 && (
        <section className="flex flex-wrap gap-2">
          {Object.entries(resumen.por_motivo).map(([motivo, n]) => (
            <span key={motivo} className="rounded-full bg-muted px-2.5 py-1 text-xs text-muted-foreground">
              {MOTIVOS[motivo] ?? motivo}: <b className="text-foreground tabular">{n}</b>
            </span>
          ))}
        </section>
      )}

      {/* Cómo le llega, en el borrador */}
      {estado === 'borrador' && (previas ?? []).length > 0 && (
        <section className="grid gap-3 md:grid-cols-3">
          {(previas ?? []).map((p) => (
            <div key={p.fila} className="rounded-xl border border-border/40 bg-[#efeae2] p-3 dark:bg-[#0b141a]">
              <p className="mb-1 text-[11px] font-semibold text-muted-foreground">Fila {p.fila}</p>
              <p className="whitespace-pre-wrap rounded-xl rounded-tl-xs bg-white p-2.5 text-xs shadow-xs dark:bg-[#202c33]">
                {p.cuerpo}
              </p>
            </div>
          ))}
        </section>
      )}

      <PanelEnvio
        id={envio.id}
        estado={estado}
        listos={listos}
        plantillaAprobada={plantilla?.estado_meta === 'aprobada'}
        ajustes={{
          tamanoLote: envio.tamano_lote,
          minutosEntreLotes: envio.minutos_entre_lotes,
          topeDiario: envio.tope_diario,
          frecuenciaDias: envio.frecuencia_dias,
          horario: envio.horario as unknown as Horario,
        }}
      />

      <section className="flex flex-col gap-1 text-xs text-muted-foreground">
        <p>
          <b className="text-foreground">Cuándo sale:</b> {describirHorario(envio.horario as unknown as Horario)}. En
          lotes de {envio.tamano_lote} cada {envio.minutos_entre_lotes} minutos, sin pasar de {envio.tope_diario}{' '}
          personas por día en la línea.
        </p>
        <p>
          <b className="text-foreground">A quién no:</b> a quien pidió no recibir más mensajes, y a quien recibió
          otro envío masivo en los últimos {envio.frecuencia_dias} días.
        </p>
        {lanzado && <p>{lanzado}</p>}
        {envio.abrir_caso && <p>A cada persona se le abre (o se le mueve a «En mora») su caso administrativo.</p>}
      </section>

      {/* Las filas */}
      {filas.length > 0 && (
        <section className="overflow-x-auto rounded-xl border bg-card">
          <table className="w-full text-xs">
            <thead className="bg-muted/40 text-left text-[11px] text-muted-foreground">
              <tr>
                <th className="px-3 py-2 font-semibold">Fila</th>
                <th className="px-3 py-2 font-semibold">Nombre</th>
                <th className="px-3 py-2 font-semibold">Teléfono</th>
                <th className="px-3 py-2 font-semibold">Resultado</th>
                <th className="px-3 py-2 font-semibold">Detalle</th>
              </tr>
            </thead>
            <tbody>
              {filas.map((f) => (
                <tr key={f.fila} className="border-t border-border/50">
                  <td className="px-3 py-2 tabular text-muted-foreground">{f.fila}</td>
                  <td className="px-3 py-2">
                    {f.contacto_id ? (
                      <Link href={`/contactos/${f.contacto_id}`} className="font-medium hover:text-primary hover:underline">
                        {f.nombre ?? 'Sin nombre'}
                      </Link>
                    ) : (
                      (f.nombre ?? '—')
                    )}
                  </td>
                  <td className="px-3 py-2 tabular">{telefonoLegible(f.telefono) ?? f.telefono ?? '—'}</td>
                  <td className="px-3 py-2">
                    {RESULTADOS[f.resultado] ?? f.resultado}
                    {f.respondio_at ? ' · respondió' : ''}
                  </td>
                  <td className="px-3 py-2 text-muted-foreground">
                    {f.motivo ? [MOTIVOS[f.motivo] ?? f.motivo, f.detalle].filter(Boolean).join(': ') : (f.error ?? '')}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {resumen && resumen.total > FILAS_EN_PANTALLA && (
            <p className="border-t border-border/50 px-3 py-2 text-xs text-muted-foreground">
              Se ven las primeras {FILAS_EN_PANTALLA} de {resumen.total} filas. Todas van en el archivo de resultados.
            </p>
          )}
        </section>
      )}
    </div>
  );
}
