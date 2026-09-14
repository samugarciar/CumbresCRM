import { NextResponse, type NextRequest } from 'next/server';
import { createClient } from '@/lib/supabase/server';

/**
 * Donde aterriza el enlace del correo.
 *
 * ACEPTA LAS DOS FORMAS QUE PUEDE TOMAR ESE ENLACE, y no es por indecisión:
 *
 *   ?code=…        Flujo PKCE, el que usa @supabase/ssr por defecto con la
 *                  plantilla de correo de fábrica. Exige que el enlace se
 *                  abra en EL MISMO NAVEGADOR que lo pidió, porque hace
 *                  falta la cookie con el verificador.
 *
 *   ?token_hash=…  Flujo OTP. Funciona en cualquier aparato: se pide desde
 *     &type=recovery   el portátil y se abre en el teléfono. Requiere que la
 *                  plantilla del correo use {{ .TokenHash }}.
 *
 * Soportar las dos cuesta diez líneas y evita el fallo más frustrante que
 * puede tener esta pantalla: que el enlace "no haga nada" porque el asesor
 * lo pidió en el computador de la oficina y lo abrió en su celular.
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = request.nextUrl;
  const supabase = await createClient();

  const tokenHash = searchParams.get('token_hash');
  const tipo = searchParams.get('type');
  const code = searchParams.get('code');

  let fallo: string | null = null;

  if (tokenHash && tipo) {
    const { error } = await supabase.auth.verifyOtp({
      type: tipo as 'recovery',
      token_hash: tokenHash,
    });
    if (error) fallo = error.message;
  } else if (code) {
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (error) fallo = error.message;
  } else {
    fallo = 'El enlace no trae nada que verificar';
  }

  if (fallo) {
    // No se pasa el motivo a la pantalla: a quien le caducó el enlace no le
    // sirve de nada leer el error de la librería, y a quien esté probando
    // enlaces ajenos tampoco hay que contarle en qué falló.
    const url = new URL('/recuperar', origin);
    url.searchParams.set('caducado', '1');
    return NextResponse.redirect(url);
  }

  return NextResponse.redirect(new URL('/recuperar/nueva', origin));
}
