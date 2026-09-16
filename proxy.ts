import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

// En Next.js 16 el convenio `middleware.ts` quedó deprecado y se renombró a
// `proxy.ts`, con la función exportada como `proxy`. Misma funcionalidad.
// Ver node_modules/next/dist/docs/01-app/03-api-reference/03-file-conventions/proxy.md
//
// Su trabajo real es refrescar el token de Supabase en cada petición. Si no
// se refresca, la sesión expira y el usuario no ve un login: ve vistas
// vacías, porque la RLS empieza a devolver cero filas.
export async function proxy(request: NextRequest) {
  let respuesta = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          respuesta = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            respuesta.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const ruta = request.nextUrl.pathname;

  if (ruta === '/') {
    return NextResponse.redirect(new URL(user ? '/mi-dia' : '/login', request.url));
  }

  // Lista de rutas PÚBLICAS, no de privadas: así una ruta nueva nace
  // protegida por olvido, que es el olvido correcto.
  //
  // Coincidencia EXACTA, no `startsWith`: con `startsWith('/recuperar')`,
  // la pantalla que fija la contraseña nueva (/recuperar/nueva) sería
  // pública, y esa es justo la que NO puede serlo.
  const FORMULARIOS_PUBLICOS = ['/login', '/recuperar'];

  // El aterrizaje del enlace del correo va aparte: tiene que ejecutarse
  // aunque ya haya sesión —alguien puede pedir el enlace estando dentro—
  // y él mismo decide a dónde mandar después.
  const esPublica =
    FORMULARIOS_PUBLICOS.includes(ruta) || ruta === '/recuperar/confirmar';

  if (!esPublica && !user) {
    const url = new URL('/login', request.url);
    url.searchParams.set('siguiente', ruta);
    return NextResponse.redirect(url);
  }

  if (FORMULARIOS_PUBLICOS.includes(ruta) && user) {
    return NextResponse.redirect(new URL('/mi-dia', request.url));
  }

  return respuesta;
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
};
