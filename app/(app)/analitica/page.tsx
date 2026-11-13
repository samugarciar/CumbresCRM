import {
  ArrowDownRight,
  ArrowRight,
  ArrowUpRight,
  CalendarCheck,
  Clock,
  Lightbulb,
  MessageCircle,
  TrendingUp,
  Trophy,
  UserPlus,
  Users,
} from 'lucide-react';
import type { ComponentType, ReactNode } from 'react';
import { createClient } from '@/lib/supabase/server';
import { FiltrosAnalitica } from './FiltrosAnalitica';
import { GraficoActividad } from './GraficoActividad';
import {
  EMBUDOS,
  MOTIVOS,
  PERIODOS,
  duracion,
  numero,
  porcentaje,
  type Analitica,
  type Periodo,
} from './tipos';

interface Busqueda {
  periodo?: string;
  embudo?: string;
}

const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
  'septiembre', 'octubre', 'noviembre', 'diciembre'];

function rango(a: Analitica): string {
  // Las fechas llegan en hora de Bogotá ('YYYY-MM-DDTHH:MM'): se leen tal cual.
  const f = (s: string) => {
    const [y, m, d] = s.slice(0, 10).split('-').map(Number);
    return { y, m, d };
  };
  const d = f(a.periodo.desde);
  if (a.periodo.codigo === 'hoy') return `Hoy, ${d.d} de ${MESES[d.m - 1]}, hasta ahora`;
  if (a.periodo.codigo === 'mes') return `${MESES[d.m - 1][0].toUpperCase()}${MESES[d.m - 1].slice(1)} de ${d.y}`;
  return `Del ${d.d} de ${MESES[d.m - 1]} a hoy`;
}

export default async function PaginaAnalitica({
  searchParams,
}: {
  searchParams: Promise<Busqueda>;
}) {
  const sp = await searchParams;
  const periodo: Periodo = (PERIODOS.find((p) => p.id === sp.periodo)?.id ?? '30d') as Periodo;
  const embudo = EMBUDOS.find((e) => e.id === sp.embudo)?.id ?? 'comercial';

  const supabase = await createClient();
  const { data, error } = await supabase
    .schema('crm')
    .rpc('analitica', { p_periodo: periodo, p_embudo: embudo });

  const cabecera = (
    <header className="flex flex-col gap-4 border-b pb-4">
      <div>
        <h1 className="text-2xl font-bold tracking-tight text-foreground">Analítica</h1>
        <p className="mt-0.5 text-sm text-muted-foreground">
          Cómo va la actividad comercial: quién escribe, a quién se atiende, qué avanza y dónde se pierde.
        </p>
      </div>
      <FiltrosAnalitica />
    </header>
  );

  if (error || !data) {
    return (
      <div className="mx-auto flex w-full max-w-6xl flex-col gap-6">
        {cabecera}
        <p className="text-sm text-destructive">
          No se pudo cargar la analítica: {error?.message ?? 'sin datos'}
        </p>
      </div>
    );
  }

  const a = data as unknown as Analitica;
  const k = a.kpis.actual;
  const ant = a.kpis.anterior;
  const contra = PERIODOS.find((p) => p.id === periodo)!.contra;
  const esComercial = embudo === 'comercial';
  const ideas = hallazgos(a);

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-6">
      {cabecera}

      <p className="-mt-2 text-sm font-medium text-foreground">
        {rango(a)}
        <span className="font-normal text-muted-foreground"> · comparado con {contra}</span>
      </p>

      {/* ---------------- Indicadores ---------------- */}
      <section
        aria-label="Indicadores"
        className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6"
      >
        <Indicador
          icono={UserPlus}
          titulo="Leads nuevos"
          valor={numero(k.leads_nuevos)}
          actual={k.leads_nuevos}
          anterior={ant.leads_nuevos}
        />
        <Indicador
          icono={MessageCircle}
          titulo="Conversaciones atendidas"
          valor={numero(k.atendidas)}
          detalle={
            k.conversaciones
              ? `de ${numero(k.conversaciones)} (${porcentaje(k.atendidas, k.conversaciones)} %)`
              : 'nadie escribió'
          }
          actual={k.atendidas}
          anterior={ant.atendidas}
        />
        <Indicador
          icono={Users}
          titulo="Atendidas por el equipo"
          valor={numero(k.atendidas_humano)}
          detalle={
            k.conversaciones
              ? `${porcentaje(k.atendidas_humano, k.conversaciones)} % de las conversaciones`
              : undefined
          }
          actual={k.atendidas_humano}
          anterior={ant.atendidas_humano}
        />
        <Indicador
          icono={Clock}
          titulo="Primera respuesta"
          valor={duracion(k.mediana_respuesta_min)}
          detalle={
            k.mediana_respuesta_humana_min !== null
              ? `${duracion(k.mediana_respuesta_humana_min)} si contesta una persona`
              : 'mediana'
          }
          actual={k.mediana_respuesta_min}
          anterior={ant.mediana_respuesta_min}
          menosEsMejor
        />
        {esComercial ? (
          <Indicador
            icono={CalendarCheck}
            titulo="Citas agendadas"
            valor={numero(k.citas_agendadas)}
            detalle={k.citas_agendadas ? `${numero(k.citas_por_bot)} las agendó el bot` : undefined}
            actual={k.citas_agendadas}
            anterior={ant.citas_agendadas}
          />
        ) : (
          <Indicador
            icono={Trophy}
            titulo="Ganadas"
            valor={numero(k.ganadas)}
            detalle={`${numero(k.perdidas)} perdidas`}
            actual={k.ganadas}
            anterior={ant.ganadas}
          />
        )}
        <Indicador
          icono={TrendingUp}
          titulo="Avanzaron de etapa"
          valor={numero(k.avanzaron)}
          detalle={`${numero(k.avances)} movimientos hacia adelante`}
          actual={k.avanzaron}
          anterior={ant.avanzaron}
        />
      </section>

      {/* ---------------- Lo que dicen los números ---------------- */}
      {ideas.length > 0 && (
        <section className="rounded-xl border border-primary/20 bg-primary/5 p-4">
          <h2 className="mb-2 flex items-center gap-2 text-sm font-semibold text-foreground">
            <Lightbulb className="size-4 text-primary" /> Lo que dicen los números
          </h2>
          <ul className="flex flex-col gap-1.5 text-sm text-foreground">
            {ideas.map((t) => (
              <li key={t} className="flex gap-2">
                <span className="mt-2 size-1.5 shrink-0 rounded-full bg-primary" />
                <span>{t}</span>
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* ---------------- Actividad en el tiempo ---------------- */}
      <Tarjeta
        titulo={a.periodo.unidad === 'hour' ? 'Actividad por hora' : 'Actividad por día'}
        nota="Pasa el cursor por una barra para ver el dato."
      >
        <GraficoActividad serie={a.serie} unidad={a.periodo.unidad} mostrarCitas={esComercial} />
      </Tarjeta>

      <div className="grid gap-6 lg:grid-cols-2">
        {/* ---------------- Embudo ---------------- */}
        <Tarjeta
          titulo="Hasta dónde llegan los leads"
          nota={`De los ${numero(a.cohorte.total)} leads que entraron en el periodo, cuántos llegaron a cada etapa.`}
        >
          <Embudo a={a} />
        </Tarjeta>

        {/* ---------------- Dónde mueren ---------------- */}
        <Tarjeta
          titulo="Dónde se pierden"
          nota="Oportunidades cerradas como perdidas en el periodo, según la etapa en la que estaban."
        >
          <Perdidas a={a} />
        </Tarjeta>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        {/* ---------------- Estancadas ---------------- */}
        <Tarjeta
          titulo="Estancadas ahora mismo"
          nota="Foto de hoy, no del periodo: abiertas que llevan en su etapa más días de los que deberían."
        >
          <Estancadas a={a} />
        </Tarjeta>

        {/* ---------------- Movimientos ---------------- */}
        <Tarjeta titulo="Movimientos entre etapas" nota="Los cambios de etapa más frecuentes del periodo.">
          {a.flujos.length === 0 ? (
            <Vacio>No hubo cambios de etapa en el periodo.</Vacio>
          ) : (
            <ul className="flex flex-col divide-y">
              {a.flujos.map((f) => (
                <li key={`${f.desde}-${f.hasta}`} className="flex items-center gap-2 py-2 text-sm">
                  <span className="min-w-0 truncate text-muted-foreground">{f.desde}</span>
                  <ArrowRight
                    className={`size-3.5 shrink-0 ${f.avance ? 'text-primary' : 'text-warning'}`}
                  />
                  <span className="min-w-0 flex-1 truncate font-medium">{f.hasta}</span>
                  {!f.avance && (
                    <span className="rounded-full bg-warning/10 px-2 py-0.5 text-[11px] text-warning">
                      retroceso
                    </span>
                  )}
                  <span className="tabular-nums font-semibold">{numero(f.cantidad)}</span>
                  <span className="w-24 text-right text-xs text-muted-foreground tabular-nums">
                    {f.por_equipo ? `${numero(f.por_equipo)} a mano` : 'automáticos'}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Tarjeta>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        {/* ---------------- Mensajes ---------------- */}
        <Tarjeta titulo="Mensajes" nota="Todo lo que entró y salió por WhatsApp en el periodo.">
          <Mensajes a={a} />
        </Tarjeta>

        {/* ---------------- Visitas ---------------- */}
        {esComercial ? (
          <Tarjeta
            titulo="Visitas del periodo"
            nota="Visitas cuya fecha cayó en el periodo. «Realizada» incluye las confirmadas que ya pasaron."
          >
            <Visitas a={a} />
          </Tarjeta>
        ) : (
          <Tarjeta titulo="Resultado de los leads del periodo">
            <Cohorte a={a} />
          </Tarjeta>
        )}
      </div>

      {/* ---------------- Equipo ---------------- */}
      <Tarjeta titulo="El equipo" nota="Lo que hizo cada persona en el periodo, en este embudo.">
        <Equipo a={a} />
      </Tarjeta>
    </div>
  );
}

// =====================================================================
// Hallazgos: frases cortas que sacan lo importante sin tener que leer
// cada gráfico. Solo se dicen cuando hay datos que las sostengan.
// =====================================================================
function hallazgos(a: Analitica): string[] {
  const k = a.kpis.actual;
  const out: string[] = [];

  const sinRespuesta = k.conversaciones - k.atendidas;
  if (k.conversaciones >= 5 && sinRespuesta > 0) {
    out.push(
      `${numero(sinRespuesta)} de ${numero(k.conversaciones)} conversaciones (${porcentaje(sinRespuesta, k.conversaciones)} %) no recibieron ninguna respuesta.`
    );
  }

  // La caída más grande entre dos etapas seguidas del embudo.
  let peor: { de: string; a: string; caida: number; perdidos: number } | null = null;
  for (let i = 1; i < a.embudo.length; i++) {
    const prev = a.embudo[i - 1];
    const cur = a.embudo[i];
    if (prev.alcanzaron < 5) continue;
    const caida = 100 - Math.round((cur.alcanzaron / prev.alcanzaron) * 100);
    if (!peor || caida > peor.caida) {
      peor = { de: prev.etiqueta, a: cur.etiqueta, caida, perdidos: prev.alcanzaron - cur.alcanzaron };
    }
  }
  if (peor && peor.caida >= 30) {
    out.push(
      `El salto más difícil es de «${peor.de}» a «${peor.a}»: no lo da el ${peor.caida} % (${numero(peor.perdidos)} leads).`
    );
  }

  const muertes = [...a.perdidas_por_etapa].sort((x, y) => y.perdidas - x.perdidas);
  const totalMuertes = muertes.reduce((s, e) => s + e.perdidas, 0);
  if (totalMuertes >= 3 && muertes[0].perdidas > 0) {
    const motivo = a.perdidas_por_motivo[0];
    out.push(
      `${porcentaje(muertes[0].perdidas, totalMuertes)} % de las perdidas se van en «${muertes[0].etiqueta}»` +
        (motivo ? `; el motivo más común es «${MOTIVOS[motivo.motivo] ?? motivo.motivo}».` : '.')
    );
  }

  const estancadas = a.estancadas.reduce((s, e) => s + e.estancadas, 0);
  if (estancadas > 0) {
    const peorEtapa = [...a.estancadas].sort((x, y) => y.estancadas - x.estancadas)[0];
    out.push(
      `Hoy hay ${numero(estancadas)} oportunidades estancadas; la mayoría en «${peorEtapa.etiqueta}» (${numero(peorEtapa.estancadas)}).`
    );
  }

  if (k.mediana_respuesta_humana_min !== null && k.mediana_respuesta_humana_min > 60) {
    out.push(
      `Cuando contesta una persona, tarda en mediana ${duracion(k.mediana_respuesta_humana_min)} desde el primer mensaje.`
    );
  }

  return out.slice(0, 4);
}

// =====================================================================
// Piezas
// =====================================================================
function Tarjeta({
  titulo,
  nota,
  children,
}: {
  titulo: string;
  nota?: string;
  children: ReactNode;
}) {
  return (
    <section className="flex flex-col gap-4 rounded-xl bg-card p-4 ring-1 ring-foreground/10 sm:p-5">
      <div>
        <h2 className="text-base font-semibold text-foreground">{titulo}</h2>
        {nota && <p className="mt-0.5 text-xs text-muted-foreground">{nota}</p>}
      </div>
      {children}
    </section>
  );
}

function Vacio({ children }: { children: ReactNode }) {
  return <p className="py-6 text-center text-sm text-muted-foreground">{children}</p>;
}

function Indicador({
  icono: Icono,
  titulo,
  valor,
  detalle,
  actual,
  anterior,
  menosEsMejor = false,
}: {
  icono: ComponentType<{ className?: string }>;
  titulo: string;
  valor: string;
  detalle?: string;
  actual: number | null;
  anterior: number | null;
  menosEsMejor?: boolean;
}) {
  let cambio: ReactNode = null;
  if (actual !== null && anterior !== null) {
    if (anterior === 0 && actual === 0) {
      cambio = <span className="text-muted-foreground">sin cambio</span>;
    } else if (anterior === 0) {
      cambio = <span className="text-muted-foreground">antes: 0</span>;
    } else {
      const pct = Math.round(((actual - anterior) / anterior) * 100);
      const sube = pct > 0;
      const bueno = pct === 0 ? null : menosEsMejor ? !sube : sube;
      const Flecha = sube ? ArrowUpRight : ArrowDownRight;
      cambio = (
        <span
          className={`flex items-center gap-0.5 font-medium ${
            bueno === null ? 'text-muted-foreground' : bueno ? 'text-primary' : 'text-destructive'
          }`}
        >
          {pct !== 0 && <Flecha className="size-3" />}
          {pct === 0 ? 'igual' : `${Math.abs(pct)} %`}
        </span>
      );
    }
  }

  return (
    <div className="flex flex-col gap-1 rounded-xl bg-card p-3.5 ring-1 ring-foreground/10">
      <div className="flex items-start gap-1.5 text-xs font-medium leading-tight text-muted-foreground">
        <Icono className="mt-px size-3.5 shrink-0" />
        <span>{titulo}</span>
      </div>
      <div className="text-2xl font-bold tracking-tight tabular-nums text-foreground">{valor}</div>
      {detalle && <div className="text-xs text-muted-foreground">{detalle}</div>}
      {cambio && <div className="mt-auto pt-1 text-xs">{cambio}</div>}
    </div>
  );
}

function Barra({ valor, maximo, tono = 'bg-chart-1' }: { valor: number; maximo: number; tono?: string }) {
  const ancho = maximo ? Math.max(valor ? 2 : 0, (valor / maximo) * 100) : 0;
  return (
    <div className="h-2.5 w-full overflow-hidden rounded-full bg-muted">
      <div className={`h-full rounded-full ${tono}`} style={{ width: `${ancho}%` }} />
    </div>
  );
}

function Embudo({ a }: { a: Analitica }) {
  if (a.cohorte.total === 0) return <Vacio>No entraron leads en este periodo.</Vacio>;
  const tope = a.embudo[0]?.alcanzaron || a.cohorte.total;
  return (
    <div className="flex flex-col gap-3">
      <ol className="flex flex-col gap-2.5">
        {a.embudo.map((e, i) => {
          const prev = i > 0 ? a.embudo[i - 1].alcanzaron : null;
          const paso = prev ? porcentaje(e.alcanzaron, prev) : null;
          return (
            <li key={e.codigo} className="flex flex-col gap-1">
              <div className="flex items-baseline justify-between gap-2 text-sm">
                <span className="font-medium">{e.etiqueta}</span>
                <span className="tabular-nums">
                  <span className="font-semibold">{numero(e.alcanzaron)}</span>
                  <span className="ml-2 text-xs text-muted-foreground">
                    {porcentaje(e.alcanzaron, tope)} % del total
                    {paso !== null && ` · ${paso} % de la anterior`}
                  </span>
                </span>
              </div>
              <Barra valor={e.alcanzaron} maximo={tope} />
            </li>
          );
        })}
      </ol>
      <Cohorte a={a} />
    </div>
  );
}

function Cohorte({ a }: { a: Analitica }) {
  const c = a.cohorte;
  if (c.total === 0) return <Vacio>No entraron leads en este periodo.</Vacio>;
  return (
    <div className="grid grid-cols-3 gap-2 text-center">
      {[
        { t: 'Siguen abiertas', v: c.abiertas, tono: 'text-foreground' },
        { t: 'Ganadas', v: c.ganadas, tono: 'text-primary' },
        { t: 'Perdidas', v: c.perdidas, tono: 'text-destructive' },
      ].map((x) => (
        <div key={x.t} className="rounded-lg bg-muted/60 p-2">
          <div className={`text-lg font-bold tabular-nums ${x.tono}`}>{numero(x.v)}</div>
          <div className="text-[11px] text-muted-foreground">{x.t}</div>
        </div>
      ))}
    </div>
  );
}

function Perdidas({ a }: { a: Analitica }) {
  const total = a.perdidas_por_etapa.reduce((s, e) => s + e.perdidas, 0);
  const reclas = a.reclasificadas.reduce((s, r) => s + r.cantidad, 0);
  if (total === 0)
    return (
      <Vacio>
        No se perdió ninguna oportunidad en el periodo.
        {reclas > 0 && ` (${numero(reclas)} se reclasificaron.)`}
      </Vacio>
    );
  const max = Math.max(...a.perdidas_por_etapa.map((e) => e.perdidas));
  const maxMotivo = Math.max(1, ...a.perdidas_por_motivo.map((m) => m.cantidad));
  return (
    <div className="flex flex-col gap-5">
      <ol className="flex flex-col gap-2.5">
        {a.perdidas_por_etapa.map((e) => (
          <li key={e.codigo} className="flex flex-col gap-1">
            <div className="flex justify-between text-sm">
              <span className={e.perdidas === max ? 'font-semibold' : ''}>{e.etiqueta}</span>
              <span className="tabular-nums">
                <span className="font-semibold">{numero(e.perdidas)}</span>
                <span className="ml-2 text-xs text-muted-foreground">{porcentaje(e.perdidas, total)} %</span>
              </span>
            </div>
            <Barra valor={e.perdidas} maximo={max} tono="bg-destructive/70" />
          </li>
        ))}
      </ol>
      <div>
        <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
          Por qué
        </h3>
        <ul className="flex flex-col gap-1.5">
          {a.perdidas_por_motivo.map((m) => (
            <li key={m.motivo} className="grid grid-cols-[8.5rem_1fr_2.5rem] items-center gap-2 text-sm">
              <span className="truncate">{MOTIVOS[m.motivo] ?? m.motivo}</span>
              <Barra valor={m.cantidad} maximo={maxMotivo} tono="bg-chart-4" />
              <span className="text-right tabular-nums">{numero(m.cantidad)}</span>
            </li>
          ))}
        </ul>
      </div>
      {reclas > 0 && (
        <p className="text-xs text-muted-foreground">
          Aparte, {numero(reclas)} se cerraron por reclasificación (
          {a.reclasificadas.map((r) => `${MOTIVOS[r.motivo] ?? r.motivo}: ${r.cantidad}`).join(', ')}
          ): no son leads perdidos.
        </p>
      )}
    </div>
  );
}

function Estancadas({ a }: { a: Analitica }) {
  const abiertas = a.estancadas.reduce((s, e) => s + e.abiertas, 0);
  if (abiertas === 0) return <Vacio>No hay oportunidades abiertas en este embudo.</Vacio>;
  const max = Math.max(1, ...a.estancadas.map((e) => e.abiertas));
  return (
    <div className="flex flex-col gap-3">
      <div className="flex gap-4 text-xs text-muted-foreground">
        <span className="flex items-center gap-1.5">
          <span className="size-2.5 rounded-sm bg-chart-1" /> Al día
        </span>
        <span className="flex items-center gap-1.5">
          <span className="size-2.5 rounded-sm bg-warning" /> Estancadas
        </span>
      </div>
      <ol className="flex flex-col gap-2.5">
        {a.estancadas.map((e) => (
          <li key={e.codigo} className="flex flex-col gap-1">
            <div className="flex justify-between text-sm">
              <span>
                {e.etiqueta}
                {e.dias_pudricion !== null && (
                  <span className="ml-1.5 text-xs text-muted-foreground">
                    (más de {e.dias_pudricion} {e.dias_pudricion === 1 ? 'día' : 'días'})
                  </span>
                )}
              </span>
              <span className="tabular-nums">
                <span className="font-semibold text-warning">{numero(e.estancadas)}</span>
                <span className="text-muted-foreground"> / {numero(e.abiertas)}</span>
              </span>
            </div>
            <div className="flex h-2.5 w-full overflow-hidden rounded-full bg-muted">
              <div
                className="h-full bg-chart-1"
                style={{ width: `${((e.abiertas - e.estancadas) / max) * 100}%` }}
              />
              <div className="h-full bg-warning" style={{ width: `${(e.estancadas / max) * 100}%` }} />
            </div>
          </li>
        ))}
      </ol>
    </div>
  );
}

function Mensajes({ a }: { a: Analitica }) {
  const m = a.mensajes;
  const salientes = m.salientes_bot + m.salientes_humano + m.salientes_sistema;
  if (m.entrantes + salientes === 0) return <Vacio>No hubo mensajes en el periodo.</Vacio>;
  const filas = [
    { t: 'Recibidos de clientes', v: m.entrantes, tono: 'bg-chart-2' },
    { t: 'Respondidos por el bot', v: m.salientes_bot, tono: 'bg-chart-3' },
    { t: 'Respondidos por el equipo', v: m.salientes_humano, tono: 'bg-chart-1' },
    { t: 'Automáticos (plantillas, envíos)', v: m.salientes_sistema, tono: 'bg-chart-5' },
  ];
  const max = Math.max(...filas.map((f) => f.v));
  return (
    <div className="flex flex-col gap-3">
      <ul className="flex flex-col gap-2.5">
        {filas.map((f) => (
          <li key={f.t} className="flex flex-col gap-1">
            <div className="flex justify-between text-sm">
              <span>{f.t}</span>
              <span className="font-semibold tabular-nums">{numero(f.v)}</span>
            </div>
            <Barra valor={f.v} maximo={max} tono={f.tono} />
          </li>
        ))}
      </ul>
      {salientes > 0 && (
        <p className="text-xs text-muted-foreground">
          El bot escribió el {porcentaje(m.salientes_bot, salientes)} % de lo que salió.
        </p>
      )}
    </div>
  );
}

function Visitas({ a }: { a: Analitica }) {
  const v = a.visitas;
  if (v.programadas === 0) return <Vacio>No hubo visitas con fecha en este periodo.</Vacio>;
  const celdas = [
    { t: 'Programadas', v: v.programadas, tono: 'text-foreground' },
    { t: 'Realizadas', v: v.realizadas, tono: 'text-primary' },
    { t: 'Canceladas', v: v.canceladas, tono: 'text-destructive' },
    { t: 'Sin confirmar', v: v.sin_confirmar, tono: 'text-warning' },
    { t: 'Por venir', v: v.pendientes, tono: 'text-foreground' },
  ];
  return (
    <div className="flex flex-col gap-3">
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
        {celdas.map((c) => (
          <div key={c.t} className="rounded-lg bg-muted/60 p-2 text-center">
            <div className={`text-lg font-bold tabular-nums ${c.tono}`}>{numero(c.v)}</div>
            <div className="text-[11px] text-muted-foreground">{c.t}</div>
          </div>
        ))}
      </div>
      <p className="text-xs text-muted-foreground">
        Se realizaron el {porcentaje(v.realizadas, v.programadas)} % de las visitas programadas.
        {v.sin_confirmar > 0 &&
          ` ${numero(v.sin_confirmar)} ya pasaron sin que nadie las confirmara: no se sabe si ocurrieron.`}
      </p>
    </div>
  );
}

function Equipo({ a }: { a: Analitica }) {
  if (a.asesores.length === 0)
    return <Vacio>Nadie del equipo registró actividad en este embudo durante el periodo.</Vacio>;
  return (
    <div className="-mx-4 overflow-x-auto sm:mx-0">
      <table className="w-full min-w-[36rem] text-sm">
        <thead>
          <tr className="border-b text-left text-xs text-muted-foreground">
            <th className="px-4 py-2 font-medium sm:pl-0">Persona</th>
            <th className="px-2 py-2 text-right font-medium">Clientes atendidos</th>
            <th className="px-2 py-2 text-right font-medium">Mensajes</th>
            <th className="px-2 py-2 text-right font-medium">Notas y llamadas</th>
            <th className="px-2 py-2 text-right font-medium">Avances de etapa</th>
            <th className="px-2 py-2 text-right font-medium">Ganadas</th>
            <th className="px-4 py-2 text-right font-medium sm:pr-0">Perdidas</th>
          </tr>
        </thead>
        <tbody className="divide-y">
          {a.asesores.map((p) => (
            <tr key={p.usuario_id}>
              <td className="px-4 py-2 font-medium sm:pl-0">{p.nombre}</td>
              <td className="px-2 py-2 text-right tabular-nums">{numero(p.contactos)}</td>
              <td className="px-2 py-2 text-right tabular-nums">{numero(p.mensajes)}</td>
              <td className="px-2 py-2 text-right tabular-nums">{numero(p.notas_llamadas)}</td>
              <td className="px-2 py-2 text-right tabular-nums">{numero(p.avances)}</td>
              <td className="px-2 py-2 text-right tabular-nums text-primary">{numero(p.ganadas)}</td>
              <td className="px-4 py-2 text-right tabular-nums sm:pr-0">{numero(p.perdidas)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
