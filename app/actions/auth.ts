'use server';

import { headers } from 'next/headers';
import { createClient } from '@/lib/supabase/server';
import { AVISO_DESACTIVADO } from '@/app/login/avisos';

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
    // Desactivar a alguien en /asesores de la plataforma también lo banea en
    // Auth: Supabase lo dice con este código, después de comprobar la
    // contraseña, así que no sirve para enumerar cuentas.
    if (error.code === 'user_banned') {
      return { ok: false, error: AVISO_DESACTIVADO };
    }
    // No se devuelve el mensaje crudo de Supabase: distingue "usuario no
    // existe" de "contraseña incorrecta" y eso permite enumerar cuentas.
    return { ok: false, error: 'Correo o contraseña incorrectos.' };
  }

  // Y si no estaba baneado (desactivado a mano en la base, o el baneo
  // falló), la contraseña sigue sirviendo. A un desactivado la RLS no le
  // deja leer ni su propia fila de usuarios (get_my_inmobiliaria() es NULL
  // para él, migración 2026-10-23 de la plataforma): sin fila, se le cierra
  // la sesión que se acaba de abrir y se le dice por qué.
  if (await sinAccesoAlCrm(supabase)) {
    await supabase.auth.signOut();
    return { ok: false, error: AVISO_DESACTIVADO };
  }

  return { ok: true };
}

/**
 * true si quien tiene la sesión no puede usar el CRM: su usuario está
 * desactivado (o no tiene fila en usuarios). Un error de la consulta NO
 * cuenta como desactivado: ante la duda se deja entrar, y la RLS hace el
 * resto.
 */
async function sinAccesoAlCrm(supabase: Awaited<ReturnType<typeof createClient>>): Promise<boolean> {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return false;
  const { data: perfil, error } = await supabase
    .from('usuarios')
    .select('activo')
    .eq('id', user.id)
    .maybeSingle();
  if (error) return false;
  return !perfil || perfil.activo === false;
}

export async function cerrarSesion(): Promise<void> {
  const supabase = await createClient();
  await supabase.auth.signOut();
}

/**
 * Pide el correo de recuperación.
 *
 * SIEMPRE devuelve ok, exista la cuenta o no. Si respondiera "ese correo
 * no está registrado", cualquiera podría averiguar quién trabaja aquí
 * probando direcciones — el mismo motivo por el que el login no
 * distingue "no existe" de "contraseña incorrecta".
 */
export async function solicitarRecuperacion(
  formData: FormData
): Promise<ResultadoAuth> {
  const email = String(formData.get('email') ?? '').trim().toLowerCase();
  if (!email || !email.includes('@')) {
    return { ok: false, error: 'Escribe un correo válido.' };
  }

  // El destino se arma con el host de ESTA petición, no con una variable
  // de entorno: así el enlace funciona igual en local, en staging y en
  // producción sin tener que acordarse de cambiar nada.
  const cabeceras = await headers();
  const host = cabeceras.get('x-forwarded-host') ?? cabeceras.get('host');
  const protocolo = cabeceras.get('x-forwarded-proto')
    ?? (host?.startsWith('localhost') || host?.startsWith('127.') ? 'http' : 'https');

  const supabase = await createClient();
  await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${protocolo}://${host}/recuperar/confirmar`,
  });

  // El error de Supabase se ignora a propósito: informar de él sería
  // justo la fuga que esta función evita.
  return { ok: true };
}

/**
 * Cambia la contraseña de quien tiene la sesión abierta.
 *
 * No recibe la contraseña vieja ni un token: llega aquí con sesión, que
 * puede venir del enlace del correo o de haber entrado normalmente. La
 * RLS de Supabase se encarga de que solo se pueda cambiar la propia.
 */
export async function cambiarContrasena(
  formData: FormData
): Promise<ResultadoAuth> {
  const password = String(formData.get('password') ?? '');
  const repetida = String(formData.get('repetida') ?? '');

  // Se valida en el servidor aunque el formulario ya valide: el cliente
  // es una sugerencia, no una garantía.
  if (password.length < 8) {
    return { ok: false, error: 'La contraseña necesita al menos 8 caracteres.' };
  }
  if (password !== repetida) {
    return { ok: false, error: 'Las dos contraseñas no coinciden.' };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return {
      ok: false,
      error: 'El enlace caducó. Pide uno nuevo desde "Olvidé mi contraseña".',
    };
  }

  const { error } = await supabase.auth.updateUser({ password });
  if (error) {
    return { ok: false, error: 'No se pudo cambiar la contraseña. Prueba con otra.' };
  }

  return { ok: true };
}
