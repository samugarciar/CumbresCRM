import Link from 'next/link';
import { notFound } from 'next/navigation';
import { ArrowLeft, MessageCircle, PhoneOff } from 'lucide-react';
import { createClient } from '@/lib/supabase/server';
import { canalConfigurado } from '@/lib/canal';
import { iniciales, telefonoLegible, tiempoRelativo, enlaceWhatsApp } from '@/lib/formato';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { PanelDatos } from './PanelDatos';
import { Historial } from './Historial';
import { PonerseAlDia, esperaLegible } from './PonerseAlDia';
import { MarcarLeido } from './MarcarLeido';
import { Recomendaciones, type Recomendable } from './Recomendaciones';
import { UsarPlantilla, type PlantillaResumen } from './UsarPlantilla';
import { TareaNueva } from '@/app/(app)/mi-dia/TareaNueva';
import { BotonMarcarAtendido } from '../BotonMarcarAtendido';
import { lineaDeEnvio } from './lineaDeEnvio';
import { CasosYEmbudos, type OportunidadContacto, type EtapaConfig } from './CasosYEmbudos';

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
    { data: responsableFilas },
    { data: botVuelveAt },
    linea,
    { data: oportunidades },
    { data: etapas },
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
    crm.from('plantillas').select('id, nombre, categoria, tipo, estado_meta').eq('activa', true).order('nombre'),
    // Cuándo se cierra la ventana de 24 h de WhatsApp. Se calcula en la
    // base, del último mensaje ENTRANTE: es lo único que la abre.
    crm.rpc('ventana_whatsapp', { p_contacto_id: id }),
    // Quién lleva esta conversación. Casi siempre nadie, todavía.
    crm.rpc('responsable_de', { p_contacto_id: id }),
    // Cuándo vuelve el bot tras un relevo. La perilla vive en la base: si
    // la ficha sumara las horas por su cuenta, mentiría el día que cambie.
    crm.rpc('bot_vuelve_at', { p_contacto_id: id }),
    // Por qué línea se le escribe: la decide el embudo de sus oportunidades.
    lineaDeEnvio(id),
    crm
      .from('oportunidades')
      .select('id, embudo, etapa, estado, updated_at')
      .eq('contacto_id', id)
      .eq('estado', 'abierta'),
    crm
      .from('etapas')
      .select('codigo, etiqueta, embudo, orden')
      .in('embudo', ['comercial', 'administrativa', 'captacion'])
      .order('orden'),
  ]);

  // El resumen se lee ANTES de marcar como leído, para que el separador
  // "nuevo desde tu última visita" sepa dónde va.
  const resumen = resumenFilas?.[0] ?? null;

  // Un solo reloj para toda la página, y es el del servidor: el del
  // celular del asesor puede estar desajustado.
  const ahora = new Date().toISOString();

  const responsable = responsableFilas?.[0] ?? null;

  const telefono = telefonoLegible(contacto.telefono_e164);
  const wa = enlaceWhatsApp(contacto.telefono_e164);

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-6">
      {/* Botón de retroceso */}
      <div>
        <Button variant="ghost" size="sm" asChild className="-ml-2 gap-1.5 text-muted-foreground hover:text-foreground">
          <Link href="/contactos">
            <ArrowLeft className="size-4" />
            <span>Volver a Bandeja de entrada</span>
          </Link>
        </Button>
      </div>

      {/* Encabezado del Contacto Tipo Cockpit */}
      <header className="rounded-2xl border bg-card p-5 shadow-2xs">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-4 min-w-0">
            <div className="flex size-14 shrink-0 items-center justify-center rounded-2xl bg-primary/10 text-primary text-lg font-bold border border-primary/20 shadow-2xs">
              {iniciales(contacto.nombre)}
            </div>

            <div className="min-w-0 space-y-1">
              <div className="flex flex-wrap items-center gap-2">
                <h1 className="text-xl font-bold tracking-tight text-foreground truncate">
                  {contacto.nombre || 'Sin nombre'}
                </h1>
                <Badge variant="outline" className="text-xs capitalize font-medium">
                  {contacto.tipo}
                </Badge>
              </div>

              <p className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                {telefono ? (
                  <span className="tabular font-medium text-foreground/80">{telefono}</span>
                ) : (
                  <span className="inline-flex items-center gap-1 text-warning">
                    <PhoneOff className="size-3.5" />
                    Sin número registrado
                  </span>
                )}
                <span aria-hidden>·</span>
                <span>Actividad {tiempoRelativo(contacto.ultima_actividad_at)}</span>
              </p>
            </div>
          </div>

          {/* Acciones principales a la derecha */}
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
              <Button asChild size="sm" className="gap-1.5 font-semibold bg-emerald-600 hover:bg-emerald-700 text-white shadow-2xs">
                <a href={wa} target="_blank" rel="noopener noreferrer">
                  <MessageCircle className="size-4" />
                  Abrir WhatsApp
                </a>
              </Button>
            )}
          </div>
        </div>
      </header>

      {/* Distribución en 2 Columnas: Contexto a la izquierda, Conversación y Timeline a la derecha */}
      <div className="grid gap-6 lg:grid-cols-[21rem_1fr] items-start">
        {/* Columna Izquierda: Inteligencia & Datos */}
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
            botVuelveAt={botVuelveAt}
            ventanaCierraAt={ventanaCierraAt}
            ahora={ahora}
            responsableNombre={responsable?.nombre ?? null}
            responsableEsMio={
              responsable?.asesor_id != null && responsable.asesor_id === user?.id
            }
          />

          <CasosYEmbudos
            contactoId={contacto.id}
            oportunidades={(oportunidades ?? []) as OportunidadContacto[]}
            etapas={(etapas ?? []) as EtapaConfig[]}
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

        {/* Columna Derecha: Hub de Conversación y Actividad */}
        <div className="flex min-w-0 flex-col gap-4">
          {resumen?.esperando_segundos !== null && (resumen?.esperando_segundos ?? 0) > 0 && (
            <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-amber-950 dark:text-amber-200 shadow-2xs">
              <div className="flex items-center gap-3">
                <span className="relative flex size-3 shrink-0">
                  <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-amber-400 opacity-75"></span>
                  <span className="relative inline-flex rounded-full size-3 bg-amber-500"></span>
                </span>
                <div>
                  <p className="text-sm font-bold text-foreground">
                    Esta persona está esperando una respuesta tuya
                  </p>
                  <p className="text-xs text-muted-foreground">
                    Último mensaje recibido hace {esperaLegible(resumen!.esperando_segundos!)}. Si ya lo atendiste por llamada, presencial o no requiere mensaje, márcalo como atendido.
                  </p>
                </div>
              </div>
              <BotonMarcarAtendido contactoId={contacto.id} variante="completo" />
            </div>
          )}

          {resumen && <PonerseAlDia resumen={resumen} />}

          <Historial
            actividades={timeline ?? []}
            vistoHasta={resumen?.visto_hasta ?? null}
            contactoId={contacto.id}
            canalListo={canalConfigurado()}
            linea={linea}
            ventanaCierraAt={ventanaCierraAt}
            ahora={ahora}
            plantillas={(plantillas ?? []) as PlantillaResumen[]}
            asesor={asesor}
          />
        </div>

        <MarcarLeido contactoId={contacto.id} />
      </div>
    </div>
  );
}
