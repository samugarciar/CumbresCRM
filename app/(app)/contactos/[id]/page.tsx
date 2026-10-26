import Link from 'next/link';
import { notFound } from 'next/navigation';
import { ArrowLeft, BotOff, PhoneOff, UserRound } from 'lucide-react';
import { createClient } from '@/lib/supabase/server';
import { canalConfigurado } from '@/lib/canal';
import { iniciales, telefonoLegible, tiempoRelativo } from '@/lib/formato';
import { variablesDe } from '@/lib/plantillas';
import { Button } from '@/components/ui/button';
import { PanelDatos } from './PanelDatos';
import { Historial, type Actividad } from './Historial';
import { conMedios } from './medios';
import { PonerseAlDia } from './PonerseAlDia';
import { MarcarLeido } from './MarcarLeido';
import { ChatEnVivo } from './ChatEnVivo';
import { Recomendaciones, type Recomendable } from './Recomendaciones';
import type { PlantillaResumen } from './UsarPlantilla';
import { TareaNueva } from '@/app/(app)/mi-dia/TareaNueva';
import { lineaDeEnvio } from './lineaDeEnvio';
import { CasosYEmbudos, type OportunidadContacto, type EtapaConfig } from './CasosYEmbudos';
import { ContenedorChat } from './ContenedorChat';
import { DatosDelContacto } from './DatosDelContacto';
import { CopiarNumero } from './CopiarNumero';
import { describirBot } from './estadoBot';

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
    { data: embudos },
  ] = await Promise.all([
    crm.from('identidades').select('tipo, valor').eq('contacto_id', id).order('tipo'),
    crm
      .from('v_timeline')
      .select('id, tipo, origen, cuerpo, ocurrido_at, inmueble_titulo, inmueble_barrio, metadata')
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
    // El cuerpo solo para saber qué variables usa cada una (ver abajo).
    crm
      .from('plantillas')
      .select('id, nombre, categoria, tipo, estado_meta, wa_phone_number_id, cuerpo')
      .eq('activa', true)
      .order('nombre'),
    // Cuándo se cierra la ventana de 24 h de WhatsApp. Se calcula en la
    // base, del último mensaje ENTRANTE: es lo único que la abre.
    crm.rpc('ventana_whatsapp', { p_contacto_id: id }),
    // Quién lleva esta conversación. Casi siempre nadie, todavía.
    crm.rpc('responsable_de', { p_contacto_id: id }),
    // Cuándo vuelve el bot. La perilla vive en la base: si la ficha sumara
    // las horas por su cuenta, mentiría el día que cambie.
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
    // Qué embudos atiende el bot: en los que no, la ficha no ofrece el
    // interruptor (encenderlo ahí no haría nada).
    crm.from('embudos').select('codigo, bot_atiende'),
  ]);

  // Fotos, audios y documentos de WhatsApp: viven en el bucket privado de
  // la plataforma, y la sesión del usuario solo firma los de su inmobiliaria.
  const actividades = await conMedios(supabase, (timeline ?? []) as Actividad[]);

  // El resumen se lee ANTES de marcar como leído, para que el separador
  // "nuevo desde tu última visita" sepa dónde va.
  const resumen = resumenFilas?.[0] ?? null;

  // Un solo reloj para toda la página, y es el del servidor: el del
  // celular del asesor puede estar desajustado.
  const ahora = new Date().toISOString();

  const responsable = responsableFilas?.[0] ?? null;
  const telefono = telefonoLegible(contacto.telefono_e164);

  // Qué variables NO se pueden llenar aquí: sin inmueble elegido ni archivo
  // de cartera, una plantilla con {{monto}} o {{inmueble}} saldría con
  // huecos. La caja de escribir lo usa para no ofrecerla por defecto.
  const llenables: Record<string, boolean> = {
    nombre: Boolean(contacto.nombre?.trim()),
    telefono: Boolean(contacto.telefono_e164),
    asesor: Boolean(asesor?.trim()),
  };
  const plantillasFicha: PlantillaResumen[] = (plantillas ?? []).map(({ cuerpo, ...p }) => ({
    ...p,
    faltan: variablesDe(cuerpo ?? '').filter((v) => !llenables[v]),
  }));

  // ¿Lo atiende el bot? Si todas sus oportunidades abiertas son de
  // embudos sin bot (administrativa, captación), no.
  const atiendeBot = new Map((embudos ?? []).map((e) => [e.codigo, e.bot_atiende]));
  const abiertas = (oportunidades ?? []) as OportunidadContacto[];
  const botNoAtiende =
    abiertas.length > 0 && abiertas.every((o) => atiendeBot.get(o.embudo) === false);

  const estadoBot = describirBot({
    activo: contacto.bot_activo ?? true,
    motivo: contacto.bot_motivo,
    cambiadoAt: contacto.bot_cambiado_at,
    vuelveAt: botVuelveAt ?? null,
    ahora,
  });
  const chipBot = botNoAtiende ? null : estadoBot.chip;

  return (
    <div className="flex w-full flex-col gap-4">
      <div>
        <Button
          variant="ghost"
          size="sm"
          asChild
          className="-ml-2 h-8 gap-1.5 rounded-lg text-muted-foreground hover:text-foreground"
        >
          <Link href="/contactos">
            <ArrowLeft className="size-4" />
            <span>Bandeja</span>
          </Link>
        </Button>
      </div>

      <header className="flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-card p-4">
        <div className="flex min-w-0 items-center gap-3">
          <div className="flex size-11 shrink-0 items-center justify-center rounded-full bg-primary/10 text-sm font-semibold text-primary">
            {contacto.nombre?.trim() ? (
              iniciales(contacto.nombre)
            ) : (
              <UserRound className="size-5" aria-hidden />
            )}
          </div>

          <div className="min-w-0 space-y-1">
            <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
              <h1 className="truncate text-lg font-semibold tracking-tight text-foreground">
                {contacto.nombre?.trim() || telefono || 'Sin nombre'}
              </h1>
              {chipBot && (
                <span
                  className="inline-flex items-center gap-1 rounded-full bg-warning/10 px-2 py-0.5 text-xs font-medium text-warning"
                  title={[estadoBot.porQue, estadoBot.vuelve].filter(Boolean).join(' ')}
                >
                  <BotOff className="size-3" aria-hidden />
                  {chipBot}
                </span>
              )}
            </div>

            <p className="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-muted-foreground">
              {contacto.telefono_e164 ? (
                <>
                  {contacto.nombre?.trim() && (
                    <span className="tabular font-medium text-foreground/80">{telefono}</span>
                  )}
                  <CopiarNumero telefono={contacto.telefono_e164} />
                </>
              ) : (
                <span className="inline-flex items-center gap-1 text-warning">
                  <PhoneOff className="size-3.5" />
                  Sin número registrado
                </span>
              )}
              <span aria-hidden>·</span>
              <span>Última actividad {tiempoRelativo(contacto.ultima_actividad_at)}</span>
            </p>
          </div>
        </div>

        <TareaNueva contactoId={contacto.id} nombre={contacto.nombre} />
      </header>

      {/* Escritorio: datos a la izquierda, conversación a la derecha.
          Celular: la conversación primero y los datos plegados debajo. */}
      <div className="grid items-start gap-4 lg:grid-cols-[20rem_minmax(0,1fr)]">
        <DatosDelContacto className="order-2 lg:order-1">
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
            botVuelveAt={botVuelveAt ?? null}
            botNoAtiende={botNoAtiende}
            ahora={ahora}
            responsableNombre={responsable?.nombre ?? null}
            responsableEsMio={
              responsable?.asesor_id != null && responsable.asesor_id === user?.id
            }
          />

          <CasosYEmbudos
            contactoId={contacto.id}
            nombre={contacto.nombre}
            oportunidades={abiertas}
            etapas={(etapas ?? []) as EtapaConfig[]}
          />

          <Recomendaciones inmuebles={(recomendables ?? []) as Recomendable[]} />
        </DatosDelContacto>

        <div className="order-1 flex min-w-0 flex-col gap-3 lg:order-2">
          {resumen && <PonerseAlDia resumen={resumen} contactoId={contacto.id} />}

          <ContenedorChat>
            <Historial
              actividades={actividades}
              vistoHasta={resumen?.visto_hasta ?? null}
              contactoId={contacto.id}
              canalListo={canalConfigurado()}
              linea={linea}
              ventanaCierraAt={ventanaCierraAt}
              ahora={ahora}
              plantillas={plantillasFicha}
              asesor={asesor}
              telefono={contacto.telefono_e164 ?? null}
            />
          </ContenedorChat>
        </div>

        <MarcarLeido contactoId={contacto.id} />
        <ChatEnVivo contactoId={contacto.id} />
      </div>
    </div>
  );
}
