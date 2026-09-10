import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

// Cliente con el JWT del usuario: la RLS aplica. Es el que se usa en todo
// lo que renderiza o muta desde la app.
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            );
          } catch {
            // Llamado desde un Server Component: las cookies son de solo
            // lectura ahí. El refresco lo hace proxy.ts.
          }
        },
      },
    }
  );
}
