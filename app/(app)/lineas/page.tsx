import { createClient } from '@/lib/supabase/server';
import { canalConfigurado } from '@/lib/canal';
import { Lineas, type Embudo, type Linea } from './Lineas';

export default async function PaginaLineas() {
  const supabase = await createClient();
  const crm = supabase.schema('crm');

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const [{ data: embudos }, { data: lineas }, { data: perfil }] = await Promise.all([
    crm.from('embudos').select('codigo, etiqueta, bot_atiende').eq('activo', true).order('orden'),
    crm.from('lineas').select('embudo, nombre, wa_phone_number_id, telefono_e164').eq('activa', true),
    user
      ? supabase.from('usuarios').select('rol').eq('id', user.id).single()
      : Promise.resolve({ data: null }),
  ]);

  const listo = canalConfigurado();

  return (
    <div className="mx-auto flex w-full max-w-3xl flex-col gap-5">
      <header>
        <h1 className="text-xl font-semibold tracking-tight">Líneas de WhatsApp</h1>
        <p className="max-w-[64ch] text-sm text-muted-foreground">
          Qué número atiende cada embudo. Un mensaje que entra por un número
          sin conectar aquí se descarta sin aviso, así que esta pantalla es lo
          primero que hay que llenar el día que el canal esté vivo.
        </p>
      </header>

      {/* El estado del canal va arriba porque explica por qué, aunque se
          llenen estas fichas, todavía no se puede enviar. */}
      <p
        className={`rounded-lg px-3.5 py-3 text-sm ${
          listo ? 'bg-muted text-muted-foreground' : 'bg-warning/10 text-warning'
        }`}
      >
        {listo ? (
          <>
            <b>El canal está conectado.</b> Los mensajes que escribas desde una
            ficha salen por la Cloud API de Meta.
          </>
        ) : (
          <>
            <b>El canal todavía no está montado.</b> Faltan las credenciales de
            Meta en la plataforma, así que el botón de enviar sigue apagado
            aunque conectes las líneas aquí. Estas fichas se pueden ir llenando
            igual.
          </>
        )}
      </p>

      <Lineas
        embudos={(embudos ?? []) as Embudo[]}
        lineas={(lineas ?? []) as Linea[]}
        puedeEditar={perfil?.rol === 'admin'}
      />
    </div>
  );
}
