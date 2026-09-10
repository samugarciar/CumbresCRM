import { createClient } from '@supabase/supabase-js';

// Service role: IGNORA la RLS. Solo para webhooks y workers, nunca en un
// camino que sirva una petición del navegador. Quien lo use tiene que
// escribir `inmobiliaria_id` a mano, porque la base ya no lo protege.
export function createAdminClient() {
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
    throw new Error('Falta la variable de entorno SUPABASE_SERVICE_ROLE_KEY.');
  }

  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    }
  );
}
