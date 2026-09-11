import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { cerrarSesion } from '@/app/actions/auth';
import { Button } from '@/components/ui/button';

// Layout autenticado. proxy.ts ya desvía a quien no tiene sesión, pero esto
// se vuelve a verificar aquí a propósito: el proxy corre en el borde y puede
// ser evitado; la verificación que cuenta es la que ocurre donde se leen los
// datos. Defensa en profundidad, el mismo criterio que usa el kill switch de
// los agentes en la plataforma actual.
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

  // TEMPORAL: lee public.usuarios directo. Desde la fase 1 esto pasa por
  // una vista de solo lectura en el esquema crm, para que el CRM no dependa
  // de la forma exacta de las tablas del repo de inventario.
  const { data: perfil } = await supabase
    .from('usuarios')
    .select('nombre_completo, rol, inmobiliaria_id')
    .eq('id', user.id)
    .single();

  return (
    <div className="flex min-h-full flex-1 flex-col">
      <header className="flex items-center justify-between gap-4 border-b bg-card px-6 py-3">
        <div className="flex items-center gap-6">
          <Link href="/contactos" className="font-semibold tracking-tight">
            Cumbres CRM
          </Link>
          <nav className="flex items-center gap-4 text-sm text-muted-foreground">
            <Link href="/contactos" className="hover:text-foreground">
              Contactos
            </Link>
          </nav>
        </div>

        <div className="flex items-center gap-4">
          <div className="text-right leading-tight">
            <p className="text-sm font-medium">
              {perfil?.nombre_completo ?? user.email}
            </p>
            <p className="text-xs text-muted-foreground capitalize">
              {perfil?.rol ?? 'sin perfil'}
            </p>
          </div>

          <form
            action={async () => {
              'use server';
              await cerrarSesion();
              redirect('/login');
            }}
          >
            <Button type="submit" variant="outline" size="sm">
              Salir
            </Button>
          </form>
        </div>
      </header>

      <main className="flex-1 p-6">{children}</main>
    </div>
  );
}
