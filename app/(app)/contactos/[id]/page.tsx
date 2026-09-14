import Link from 'next/link';
import { notFound } from 'next/navigation';
import { ArrowLeft, MessageCircle, PhoneOff } from 'lucide-react';
import { createClient } from '@/lib/supabase/server';
import { iniciales, telefonoLegible, tiempoRelativo, enlaceWhatsApp } from '@/lib/formato';
import { Button } from '@/components/ui/button';
import { NotaNueva } from './NotaNueva';
import { PanelDatos } from './PanelDatos';
import { Historial } from './Historial';
import { PonerseAlDia } from './PonerseAlDia';
import { MarcarLeido } from './MarcarLeido';

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

  const [{ data: identidades }, { data: timeline }, { data: resumenFilas }] = await Promise.all([
    crm.from('identidades').select('tipo, valor').eq('contacto_id', id).order('tipo'),
    crm
      .from('v_timeline')
      .select('id, tipo, origen, cuerpo, ocurrido_at, inmueble_titulo, inmueble_barrio')
      .eq('contacto_id', id)
      .order('ocurrido_at', { ascending: false })
      .limit(500),
    crm.rpc('resumen_contacto', { p_contacto_id: id }),
  ]);

  // El resumen se lee ANTES de marcar como leído, para que el separador
  // "nuevo desde tu última visita" sepa dónde va.
  const resumen = resumenFilas?.[0] ?? null;

  const telefono = telefonoLegible(contacto.telefono_e164);
  const wa = enlaceWhatsApp(contacto.telefono_e164);

  return (
    <div className="mx-auto flex w-full max-w-5xl flex-col gap-6">
      <Button variant="ghost" size="sm" asChild className="-ml-2 w-fit">
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
          identidades={identidades ?? []}
        />

        <div className="flex min-w-0 flex-col gap-4">
          {resumen && <PonerseAlDia resumen={resumen} />}

          <div className="rounded-lg border bg-card p-4">
            <NotaNueva contactoId={contacto.id} />
          </div>

          <Historial
            actividades={timeline ?? []}
            vistoHasta={resumen?.visto_hasta ?? null}
          />
        </div>

        <MarcarLeido contactoId={contacto.id} />
      </div>
    </div>
  );
}
