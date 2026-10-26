import Link from 'next/link';
import { ArrowLeft } from 'lucide-react';
import { createClient } from '@/lib/supabase/server';
import { NuevoEnvio, type LineaEnvio, type PlantillaEnvio } from './NuevoEnvio';

export default async function PaginaNuevoEnvio() {
  const supabase = await createClient();
  const crm = supabase.schema('crm');

  const [{ data: lineas }, { data: plantillas }] = await Promise.all([
    crm
      .from('lineas')
      .select('wa_phone_number_id, nombre, embudo')
      .eq('activa', true)
      .not('wa_phone_number_id', 'is', null)
      .order('nombre'),
    // Solo las de WhatsApp que viven en una línea: un envío masivo sale
    // fuera de la ventana de 24 h, y ahí solo entra una plantilla de Meta.
    crm
      .from('plantillas')
      .select('id, nombre, cuerpo, categoria, estado_meta, wa_phone_number_id')
      .eq('activa', true)
      .eq('tipo', 'whatsapp')
      .not('wa_phone_number_id', 'is', null)
      .order('nombre'),
  ]);

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-5 [&>*]:max-w-4xl">
      <header>
        <Link
          href="/envios-masivos"
          className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
        >
          <ArrowLeft className="size-3.5" />
          Envíos masivos
        </Link>
        <h1 className="mt-1 text-xl font-semibold tracking-tight">Nuevo envío masivo</h1>
        <p className="max-w-[68ch] text-sm text-muted-foreground mt-1">
          Sube el archivo, di de qué columna sale cada dato y revisa cómo le llegaría el mensaje a cada persona.
          Esto prepara un borrador: no sale nada hasta que alguien lo lance.
        </p>
      </header>

      <NuevoEnvio
        lineas={(lineas ?? []) as LineaEnvio[]}
        plantillas={(plantillas ?? []) as PlantillaEnvio[]}
      />
    </div>
  );
}
