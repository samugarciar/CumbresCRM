/**
 * Lo que ve quien tiene el usuario desactivado (/asesores de la plataforma).
 * Vive aquí y no en app/actions/auth.ts: un archivo 'use server' solo puede
 * exportar funciones async.
 */
export const AVISO_DESACTIVADO = 'Tu usuario está desactivado. Habla con la administración.';
