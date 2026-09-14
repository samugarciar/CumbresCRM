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
      {/* A 400px esta cabecera se partía en tres líneas y se comía el alto
          justo en el aparato donde menos sobra: el teléfono del asesor,
          en la calle. Nada se esconde que haga falta para trabajar. */}
      <header className="flex items-center justify-between gap-3 border-b bg-card px-4 py-2.5 md:gap-4 md:px-6 md:py-3">
        <div className="flex items-center gap-4 md:gap-6">
          <Link
            href="/contactos"
            className="whitespace-nowrap font-semibold tracking-tight"
          >
            Cumbres CRM
          </Link>
          <nav className="flex items-center gap-4 whitespace-nowrap text-sm text-muted-foreground">
            <Link href="/contactos" className="hover:text-foreground">
              Contactos
            </Link>
            <Link href="/tablero" className="hover:text-foreground">
              Tablero
            </Link>
            <Link href="/coincidencias" className="hover:text-foreground">
              Coincidencias
            </Link>
          </nav>
        </div>

        <div className="flex items-center gap-3 md:gap-4">
          {/* El nombre y el rol se esconden en móvil: son identificación,
              no herramienta. Quién eres ya lo sabes. */}
          <div className="hidden text-right leading-tight sm:block">
            <p className="truncate text-sm font-medium">
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

      <main className="flex min-h-0 flex-1 flex-col p-4 md:p-6">{children}</main>
    </div>
  );
}
