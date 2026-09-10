import { createClient } from '@/lib/supabase/server';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';

// Página de comprobación de la fase 0. No es la pantalla de inicio real:
// existe para demostrar que sesión, RLS y lectura de datos funcionan de
// extremo a extremo. La fase 1 la reemplaza por la lista de contactos.
export default async function PaginaInicio() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: perfil, error } = await supabase
    .from('usuarios')
    .select('nombre_completo, email, rol, inmobiliaria_id')
    .eq('id', user!.id)
    .single();

  return (
    <div className="mx-auto flex w-full max-w-2xl flex-col gap-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">
          Fase 0 · andamiaje
        </h1>
        <p className="text-muted-foreground">
          El repo arranca, la sesión de Supabase funciona y la RLS deja leer
          tu perfil. De aquí cuelga todo lo demás.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Sesión activa</CardTitle>
          <CardDescription>
            Leído de <code className="font-mono text-xs">public.usuarios</code>{' '}
            con tu propio token, no con la service role.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {error ? (
            <p className="text-sm text-destructive">
              No se pudo leer el perfil: {error.message}
            </p>
          ) : (
            <dl className="grid grid-cols-[auto_1fr] gap-x-6 gap-y-2 text-sm">
              <dt className="text-muted-foreground">Nombre</dt>
              <dd>{perfil?.nombre_completo}</dd>

              <dt className="text-muted-foreground">Correo</dt>
              <dd>{perfil?.email}</dd>

              <dt className="text-muted-foreground">Rol</dt>
              <dd className="capitalize">{perfil?.rol}</dd>

              <dt className="text-muted-foreground">Inmobiliaria</dt>
              <dd className="font-mono text-xs tabular">
                {perfil?.inmobiliaria_id}
              </dd>
            </dl>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
