'use client';

import { useState, useTransition } from 'react';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { Loader2 } from 'lucide-react';
import { iniciarSesion } from '@/app/actions/auth';
import { AVISO_DESACTIVADO } from './avisos';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';

/**
 * `siguiente` solo si es de ESTE sitio. Con `startsWith('/')` bastaba
 * «//evil.com» para que el login mandara a otro dominio después de entrar
 * (redirección abierta). Se resuelve contra el origen propio y se compara.
 */
function destinoSeguro(siguiente: string | null): string {
  if (!siguiente) return '/mi-dia';
  try {
    const url = new URL(siguiente, window.location.origin);
    if (url.origin !== window.location.origin) return '/mi-dia';
    return `${url.pathname}${url.search}${url.hash}`;
  } catch {
    return '/mi-dia';
  }
}

export function FormularioLogin() {
  const params = useSearchParams();
  // /login/salir manda aquí con ?aviso=desactivado a quien tenía la sesión
  // abierta cuando lo desactivaron.
  const [error, setError] = useState<string | null>(
    params.get('aviso') === 'desactivado' ? AVISO_DESACTIVADO : null
  );
  const [enviando, iniciarTransicion] = useTransition();
  const router = useRouter();

  const manejarEnvio = (evento: React.FormEvent<HTMLFormElement>) => {
    evento.preventDefault();
    setError(null);
    const formData = new FormData(evento.currentTarget);

    iniciarTransicion(async () => {
      const resultado = await iniciarSesion(formData);
      if (resultado.ok) {
        // `siguiente` lo pone proxy.ts al desviar a alguien sin sesión.
        router.push(destinoSeguro(params.get('siguiente')));
        router.refresh();
      } else {
        setError(resultado.error ?? 'No se pudo iniciar sesión.');
      }
    });
  };

  return (
    <main className="flex min-h-full flex-1 items-center justify-center p-6">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle className="text-2xl">Cumbres CRM</CardTitle>
          <CardDescription>
            Entra con la misma cuenta de la plataforma.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={manejarEnvio} className="flex flex-col gap-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="email">Correo</Label>
              <Input
                id="email"
                name="email"
                type="email"
                autoComplete="email"
                placeholder="nombre@cumbres.com"
                required
                disabled={enviando}
              />
            </div>

            <div className="flex flex-col gap-2">
              <Label htmlFor="password">Contraseña</Label>
              <Input
                id="password"
                name="password"
                type="password"
                autoComplete="current-password"
                required
                disabled={enviando}
              />
            </div>

            {error && (
              <p role="alert" className="text-sm text-destructive">
                {error}
              </p>
            )}

            <Button type="submit" disabled={enviando} className="mt-1">
              {enviando && <Loader2 className="animate-spin" />}
              {enviando ? 'Entrando…' : 'Entrar'}
            </Button>

            <Button variant="ghost" size="sm" asChild>
              <Link href="/recuperar">Olvidé mi contraseña</Link>
            </Button>
          </form>
        </CardContent>
      </Card>
    </main>
  );
}
