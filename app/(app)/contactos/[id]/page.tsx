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
import { Recomendaciones, type Recomendable } from './Recomendaciones';
import { UsarPlantilla, type PlantillaResumen } from './UsarPlantilla';
import { TareaNueva } from '@/app/(app)/mi-dia/TareaNueva';

export default async function FichaContacto({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const crm = supabase.schema('crm');

  // El nombre de quien mira, para la variable {{asesor}} de las plantillas.
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { data: perfil } = user
    ? await supabase.from('usuarios').select('nombre_completo').eq('id', user.id).single()
    : { data: null };
  const asesor = perfil?.nombre_completo ?? null;

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

  const [
    { data: identidades },
    { data: timeline },
    { data: resumenFilas },
    { data: recomendables },
    { data: plantillas },
    { data: ventanaCierraAt },
  ] = await Promise.all([
    crm.from('identidades').select('tipo, valor').eq('contacto_id', id).order('tipo'),
    crm
      .from('v_timeline')
      .select('id, tipo, origen, cuerpo, ocurrido_at, inmueble_titulo, inmueble_barrio')
      .eq('contacto_id', id)
      .order('ocurrido_at', { ascending: false })
      .limit(500),
    crm.rpc('resumen_contacto', { p_contacto_id: id }),
    // De VIEJOS a NUEVOS: lo recién entrado se mueve solo; lo que lleva
    // meses parado necesita salir. El puntaje filtra pero no ordena.
    crm.rpc('inmuebles_para', {
      p_contacto_id: id,
      p_minimo: 50,
      p_limite: 6,
      p_rotar: true,
    }),
    crm.from('plantillas').select('id, nombre, categoria').eq('activa', true).order('nombre'),
    // Cuándo se cierra la ventana de 24 h de WhatsApp. Se calcula en la
    // base, del último mensaje ENTRANTE: es lo único que la abre.
    crm.rpc('ventana_whatsapp', { p_contacto_id: id }),
  ]);

  // El resumen se lee ANTES de marcar como leído, para que el separador
  // "nuevo desde tu última visita" sepa dónde va.
  const resumen = resumenFilas?.[0] ?? null;

  // Un solo reloj para toda la página, y es el del servidor: el del
  // celular del asesor puede estar desajustado.
  const ahora = new Date().toISOString();

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
            <h1 className="text-xl font-semibold tracking-tight">
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

        <div className="flex flex-wrap items-center gap-2">
          <UsarPlantilla
            plantillas={(plantillas ?? []) as PlantillaResumen[]}
            contactoId={contacto.id}
            asesor={asesor}
            ventanaCierraAt={ventanaCierraAt}
            ahora={ahora}
          />
          <TareaNueva contactoId={contacto.id} nombre={contacto.nombre} />
          {wa && (
          <Button asChild>
            <a href={wa} target="_blank" rel="noopener noreferrer">
              <MessageCircle className="size-4" />
              Abrir WhatsApp
            </a>
          </Button>
          )}
        </div>
      </header>

      <div className="grid gap-6 md:grid-cols-[18rem_1fr]">
        {/* Los datos del lead, y justo debajo lo que se le puede
            ofrecer. En móvil la rejilla se apila, así que el orden queda
            igual: información, recomendaciones, conversación. */}
        <div className="flex flex-col gap-4">
          <PanelDatos
            contactoId={contacto.id}
            nombre={contacto.nombre}
            tipo={contacto.tipo}
            origen={contacto.origen}
            telefonoCrudo={contacto.telefono_crudo}
            creadoAt={contacto.created_at}
            identidades={identidades ?? []}
            botActivo={contacto.bot_activo ?? true}
            botMotivo={contacto.bot_motivo}
            botCambiadoAt={contacto.bot_cambiado_at}
            ventanaCierraAt={ventanaCierraAt}
            ahora={ahora}
          />
          <Recomendaciones
            inmuebles={(recomendables ?? []) as Recomendable[]}
            plantillas={(plantillas ?? []) as PlantillaResumen[]}
            contactoId={contacto.id}
            asesor={asesor}
            ventanaCierraAt={ventanaCierraAt}
            ahora={ahora}
          />
        </div>

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
