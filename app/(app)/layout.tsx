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

  const { data: perfil } = await supabase
    .from('usuarios')
    .select('nombre_completo, rol, inmobiliaria_id')
    .eq('id', user.id)
    .single();

  const usuario = {
    email: user.email ?? '',
    nombre: perfil?.nombre_completo ?? user.email ?? 'Asesor Cumbres',
    rol: perfil?.rol ?? 'asesor',
  };

  return <ShellNavegacion usuario={usuario}>{children}</ShellNavegacion>;
}
