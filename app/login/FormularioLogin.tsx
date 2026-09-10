'use client';

import { useState, useTransition } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { Loader2 } from 'lucide-react';
import { iniciarSesion } from '@/app/actions/auth';
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

export function FormularioLogin() {
  const [error, setError] = useState<string | null>(null);
  const [enviando, iniciarTransicion] = useTransition();
  const router = useRouter();
  const params = useSearchParams();

  const manejarEnvio = (evento: React.FormEvent<HTMLFormElement>) => {
    evento.preventDefault();
    setError(null);
    const formData = new FormData(evento.currentTarget);

    iniciarTransicion(async () => {
      const resultado = await iniciarSesion(formData);
      if (resultado.ok) {
        // `siguiente` lo pone proxy.ts al desviar a alguien sin sesión.
        const siguiente = params.get('siguiente');
        router.push(siguiente && siguiente.startsWith('/') ? siguiente : '/inicio');
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
          </form>
        </CardContent>
      </Card>
    </main>
  );
}
