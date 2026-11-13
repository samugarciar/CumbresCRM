import Link from 'next/link';
import { ArrowLeft } from 'lucide-react';
import { createClient } from '@/lib/supabase/server';
import {
  PanelReciclador,
  type Candidato,
  type ConfigReciclador,
  type Intento,
  type PlantillaReciclador,
  type Resumen,
} from './PanelReciclador';

/**
 * El reciclador de leads: la versión automática de la bandeja de
 * Reactivación (decisiones de Samuel del 13 nov 2026).
 *
 * La bandeja manual mira a quien lleva 14 días o más callado; esto mira
 * las últimas horas: conversaciones en las que hablamos de último y el
 * cliente no contestó. La regla vive entera en crm.candidatos_reciclaje,
 * y esta pantalla enseña lo mismo que va a mandar el despachador.
 */
export default async function PaginaReciclador() {
  const supabase = await createClient();
  const crm = supabase.schema('crm');

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const [{ data: perfil }, { data: linea }] = await Promise.all([
    user
      ? supabase.from('usuarios').select('rol').eq('id', user.id).single()
      : Promise.resolve({ data: null }),
    crm
      .from('lineas')
      .select('id, nombre, wa_phone_number_id, telefono_e164')
      .eq('embudo', 'comercial')
      .eq('activa', true)
      .maybeSingle(),
  ]);

  const encabezado = (
    <header className="flex flex-col gap-1">
      <Link
        href="/reactivacion"
        className="inline-flex w-fit items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
      >
        <ArrowLeft className="size-3" /> Reactivación
      </Link>
      <h1 className="text-xl font-semibold tracking-tight">Reciclador automático</h1>
      <p className="max-w-[64ch] text-sm text-muted-foreground">
        Le escribe solo, con una plantilla aprobada por Meta, a quien dejó de contestarnos:
        conversaciones en las que hablamos de último y la persona no respondió. Nunca a quien nos
        dejó esperando a nosotros.
      </p>
    </header>
  );

  if (!linea) {
    return (
      <div className="mx-auto flex w-full max-w-6xl flex-col gap-5 [&>*]:max-w-3xl">
        {encabezado}
        <p className="rounded-xl bg-muted px-3.5 py-3 text-sm text-muted-foreground">
          No hay una línea comercial activa. El reciclador escribe por la línea comercial: conéctala
          primero en <Link href="/lineas" className="text-primary hover:underline">Líneas</Link>.
        </p>
      </div>
    );
  }

  const [{ data: config }, { data: plantillas }, { data: resumen }, { data: candidatos }, { data: historial }] =
    await Promise.all([
      crm
        .from('reciclador_config')
        .select(
          'activo, simulacion, horas_silencio, max_intentos, dias_atras, tope_diario, plantilla_id, horario, ultimo_aviso, ultima_pasada_at'
        )
        .eq('linea_id', linea.id)
        .maybeSingle(),
      crm
        .from('plantillas')
        .select('id, nombre, cuerpo, categoria, estado_meta')
        .eq('activa', true)
        .eq('wa_phone_number_id', linea.wa_phone_number_id ?? '')
        .order('nombre'),
      crm.rpc('resumen_reciclaje', { p_linea_id: linea.id, p_dias: 7 }),
      // Sin configuración guardada devuelve vacío: no hay horas ni ventana.
      crm.rpc('candidatos_reciclaje', { p_linea_id: linea.id, p_limite: 30 }),
      crm.rpc('historial_reciclaje', { p_linea_id: linea.id, p_limite: 50 }),
    ]);

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-5">
      {encabezado}
      <PanelReciclador
        linea={{ id: linea.id, nombre: linea.nombre, telefono: linea.telefono_e164 }}
        config={(config ?? null) as ConfigReciclador | null}
        plantillas={(plantillas ?? []) as PlantillaReciclador[]}
        resumen={((resumen ?? [])[0] ?? null) as Resumen | null}
        candidatos={(candidatos ?? []) as Candidato[]}
        historial={(historial ?? []) as Intento[]}
        puedeEditar={perfil?.rol === 'admin'}
      />
    </div>
  );
}
