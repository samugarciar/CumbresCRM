import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { ShellNavegacion } from '@/components/ShellNavegacion';

// Layout autenticado. proxy.ts ya desvía a quien no tiene sesión, pero esto
// se vuelve a verificar aquí a propósito: el proxy corre en el borde y puede
// ser evitado; la verificación que cuenta es la que ocurre donde se leen los
// datos. Defensa en profundidad.
export default async function LayoutApp({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect('/login');

  const { data: perfil, error: errorPerfil } = await supabase
    .from('usuarios')
    .select('nombre_completo, rol, inmobiliaria_id, activo')
    .eq('id', user.id)
    .maybeSingle();

  // Lo desactivaron con la sesión abierta. A un desactivado la RLS no le
  // deja leer ni su propia fila (get_my_inmobiliaria() es NULL para él), así
  // que «sin fila» es la señal. Un Server Component no puede borrar cookies
  // (solo un Route Handler o una Server Function): la sesión la cierra
  // /login/salir, que luego lo manda a /login con el aviso. Mandarlo directo
  // a /login no serviría: con la sesión viva, proxy.ts lo devolvería aquí.
  if (!errorPerfil && (!perfil || perfil.activo === false)) redirect('/login/salir');

  const usuario = {
    email: user.email ?? '',
    nombre: perfil?.nombre_completo ?? user.email ?? 'Asesor Cumbres',
    rol: perfil?.rol ?? 'asesor',
  };

  return <ShellNavegacion usuario={usuario}>{children}</ShellNavegacion>;
}
