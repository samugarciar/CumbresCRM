import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

/**
 * Cierra la sesión de un usuario DESACTIVADO y lo manda al login con el
 * aviso. Lo usa el layout de la app: un Server Component no puede borrar
 * cookies, un Route Handler sí (node_modules/next/dist/docs, cookies.md).
 *
 * Solo cierra la sesión si el usuario de verdad está desactivado: un
 * enlace a esta ruta no le cierra la sesión a nadie más.
 */
export async function GET() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect('/login');

  // A un desactivado la RLS no le deja leer ni su propia fila: sin fila (y
  // sin error) es desactivado.
  const { data: perfil, error } = await supabase
    .from('usuarios')
    .select('activo')
    .eq('id', user.id)
    .maybeSingle();

  if (!error && (!perfil || perfil.activo === false)) {
    await supabase.auth.signOut();
    redirect('/login?aviso=desactivado');
  }

  redirect('/mi-dia');
}
