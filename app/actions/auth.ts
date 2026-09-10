'use server';

import { createClient } from '@/lib/supabase/server';

export interface ResultadoAuth {
  ok: boolean;
  error?: string;
}

export async function iniciarSesion(formData: FormData): Promise<ResultadoAuth> {
  const email = String(formData.get('email') ?? '').trim();
  const password = String(formData.get('password') ?? '');

  if (!email || !password) {
    return { ok: false, error: 'Escribe tu correo y tu contraseña.' };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    // No se devuelve el mensaje crudo de Supabase: distingue "usuario no
    // existe" de "contraseña incorrecta" y eso permite enumerar cuentas.
    return { ok: false, error: 'Correo o contraseña incorrectos.' };
  }

  return { ok: true };
}

export async function cerrarSesion(): Promise<void> {
  const supabase = await createClient();
  await supabase.auth.signOut();
}
