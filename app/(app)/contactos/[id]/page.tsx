import Link from 'next/link';
import { notFound } from 'next/navigation';
import {
  ArrowLeft,
  Bot,
  CalendarCheck,
  CalendarClock,
  CalendarX,
  MessageCircle,
  MessageSquare,
  PhoneOff,
  Send,
  StickyNote,
} from 'lucide-react';
import { createClient } from '@/lib/supabase/server';
import {
  fechaLarga,
  iniciales,
  telefonoLegible,
  tiempoRelativo,
  enlaceWhatsApp,
} from '@/lib/formato';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { NotaNueva } from './NotaNueva';
import { PanelDatos } from './PanelDatos';

// Cada clase de hecho se ve distinta a propósito: en un timeline denso,
// distinguir de un vistazo "el cliente escribió" de "el bot contestó" es
// la mitad del valor de tenerlo.
const ASPECTO: Record<
  string,
  { icono: typeof MessageCircle; etiqueta: string; clase: string }
> = {
  mensaje_entrante: { icono: MessageCircle, etiqueta: 'Mensaje del cliente', clase: 'bg-accent text-accent-foreground' },
  mensaje_saliente: { icono: Send, etiqueta: 'Respuesta enviada', clase: 'bg-muted text-muted-foreground' },
  nota: { icono: StickyNote, etiqueta: 'Nota', clase: 'bg-primary/10 text-primary' },
  llamada: { icono: MessageSquare, etiqueta: 'Llamada', clase: 'bg-muted text-muted-foreground' },
  visita_agendada: { icono: CalendarClock, etiqueta: 'Visita agendada', clase: 'bg-primary/10 text-primary' },
  visita_realizada: { icono: CalendarCheck, etiqueta: 'Visita realizada', clase: 'bg-primary/15 text-primary' },
  visita_cancelada: { icono: CalendarX, etiqueta: 'Visita cancelada', clase: 'bg-destructive/10 text-destructive' },
  solicitud_apertura: { icono: CalendarClock, etiqueta: 'Pidió un horario', clase: 'bg-primary/10 text-primary' },
  sistema: { icono: MessageSquare, etiqueta: 'Sistema', clase: 'bg-muted text-muted-foreground' },
};

export default async function FichaContacto({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const crm = supabase.schema('crm');

  const { data: contacto } = await crm
    .from('contactos')
    .select('*')
    .eq('id', id)
    .is('deleted_at', null)
    .maybeSingle();

  // Si la RLS no lo deja ver, `contacto` viene nulo — igual que si no
  // existiera. Es lo correcto: no confirmar la existencia de datos de
  // otra inmobiliaria.
  if (!contacto) notFound();

  const [{ data: identidades }, { data: timeline }] = await Promise.all([
    crm.from('identidades').select('tipo, valor').eq('contacto_id', id).order('tipo'),
    crm
      .from('v_timeline')
      .select('*')
      .eq('contacto_id', id)
      .order('ocurrido_at', { ascending: false })
      .limit(300),
  ]);

  const telefono = telefonoLegible(contacto.telefono_e164);
  const wa = enlaceWhatsApp(contacto.telefono_e164);

  return (
    <div className="mx-auto flex w-full max-w-5xl flex-col gap-6">
      <Button variant="ghost" size="sm" asChild className="w-fit -ml-2">
        <Link href="/contactos">
          <ArrowLeft className="size-4" />
          Contactos
        </Link>
      </Button>

      <header className="flex flex-wrap items-start justify-between gap-4">
        <div className="flex items-center gap-4">
          <span className="grid size-12 shrink-0 place-items-center rounded-full bg-accent text-base font-semibold text-accent-foreground">
            {iniciales(contacto.nombre)}
          </span>
          <div>
            <h1 className="text-2xl font-semibold tracking-tight">
              {contacto.nombre || 'Sin nombre'}
            </h1>
            <p className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
              {telefono ? (
                <span className="tabular">{telefono}</span>
              ) : (
                <span className="inline-flex items-center gap-1.5">
                  <PhoneOff className="size-3.5" />
                  Sin número al que llamar
                </span>
              )}
              <span aria-hidden>·</span>
              <span>Última actividad {tiempoRelativo(contacto.ultima_actividad_at)}</span>
            </p>
          </div>
        </div>

        {wa && (
          <Button asChild>
            <a href={wa} target="_blank" rel="noopener noreferrer">
              <MessageCircle className="size-4" />
              Abrir WhatsApp
            </a>
          </Button>
        )}
      </header>

      <div className="grid gap-6 md:grid-cols-[18rem_1fr]">
        <PanelDatos
          contactoId={contacto.id}
          nombre={contacto.nombre}
          tipo={contacto.tipo}
          origen={contacto.origen}
          telefonoCrudo={contacto.telefono_crudo}
          creadoAt={contacto.created_at}
          consentimiento={contacto.consentimiento}
          consentimientoAt={contacto.consentimiento_at}
          consentimientoCanal={contacto.consentimiento_canal}
          identidades={identidades ?? []}
        />

        <section className="flex min-w-0 flex-col gap-4">
          <div className="rounded-lg border bg-card p-4">
            <NotaNueva contactoId={contacto.id} />
          </div>

          <h2 className="text-sm font-medium text-muted-foreground">
            Historial · {timeline?.length ?? 0}{' '}
            {timeline?.length === 1 ? 'hecho' : 'hechos'}
          </h2>

          {!timeline || timeline.length === 0 ? (
            <p className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
              Todavía no ha pasado nada con esta persona.
            </p>
          ) : (
            <ol className="flex flex-col">
              {timeline.map((a, i) => {
                const aspecto = ASPECTO[a.tipo ?? 'sistema'] ?? ASPECTO.sistema;
                const Icono = aspecto.icono;
                const ultimo = i === timeline.length - 1;

                return (
                  <li key={a.id} className="flex gap-3">
                    {/* La línea vertical hace que se lea como una
                        secuencia y no como una lista de tarjetas sueltas. */}
                    <div className="flex flex-col items-center">
                      <span
                        className={`grid size-8 shrink-0 place-items-center rounded-full ${aspecto.clase}`}
                      >
                        <Icono className="size-4" />
                      </span>
                      {!ultimo && <span className="w-px flex-1 bg-border" />}
                    </div>

                    <div className={`min-w-0 flex-1 ${ultimo ? '' : 'pb-5'}`}>
                      <div className="flex flex-wrap items-baseline gap-x-2">
                        <span className="text-sm font-medium">{aspecto.etiqueta}</span>

                        {a.origen === 'agente_ia' && (
                          <Badge variant="outline" className="gap-1 text-[10px]">
                            <Bot className="size-3" />
                            Agente
                          </Badge>
                        )}

                        <span
                          className="text-xs text-muted-foreground"
                          title={fechaLarga(a.ocurrido_at)}
                        >
                          {tiempoRelativo(a.ocurrido_at)}
                        </span>
                      </div>

                      {a.cuerpo && (
                        <p className="mt-1 whitespace-pre-wrap break-words text-sm text-muted-foreground">
                          {a.cuerpo}
                        </p>
                      )}

                      {a.inmueble_titulo && (
                        <p className="mt-1 text-xs text-muted-foreground">
                          {a.inmueble_titulo}
                          {a.inmueble_barrio ? ` · ${a.inmueble_barrio}` : ''}
                        </p>
                      )}
                    </div>
                  </li>
                );
              })}
            </ol>
          )}
        </section>
      </div>
    </div>
  );
}
