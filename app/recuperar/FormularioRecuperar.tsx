'use client';

import { useState, useTransition } from 'react';
import { useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { ArrowLeft, Loader2, MailCheck, TriangleAlert } from 'lucide-react';
import { solicitarRecuperacion } from '@/app/actions/auth';
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

export function FormularioRecuperar() {
  const [enviado, setEnviado] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [enviando, iniciarTransicion] = useTransition();
  const caducado = useSearchParams().get('caducado') === '1';

  const manejarEnvio = (evento: React.FormEvent<HTMLFormElement>) => {
    evento.preventDefault();
    setError(null);
    const formData = new FormData(evento.currentTarget);
    iniciarTransicion(async () => {
      const r = await solicitarRecuperacion(formData);
      if (r.ok) setEnviado(true);
      else setError(r.error ?? 'No se pudo enviar el correo.');
    });
  };

  return (
    <main className="flex min-h-full flex-1 items-center justify-center p-6">
      <Card className="w-full max-w-sm">
        {enviado ? (
          <>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-2xl">
                <MailCheck className="size-6 text-primary" />
                Revisa tu correo
              </CardTitle>
              <CardDescription>
                Si esa dirección tiene cuenta, le acaba de llegar un enlace para
                poner una contraseña nueva. Caduca en una hora.
              </CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-3">
              {/* Se dice "si esa dirección tiene cuenta" y no "te enviamos un
                  correo" a propósito: confirmar que existe permitiría
                  averiguar quién trabaja aquí probando direcciones. */}
              <p className="text-sm text-muted-foreground">
                ¿No llega? Mira en spam. Y comprueba que escribiste el mismo
                correo con el que entras a la plataforma.
              </p>
              <Button variant="outline" asChild>
                <Link href="/login">
                  <ArrowLeft className="size-4" />
                  Volver a entrar
                </Link>
              </Button>
            </CardContent>
          </>
        ) : (
          <>
            <CardHeader>
              <CardTitle className="text-2xl">Olvidé mi contraseña</CardTitle>
              <CardDescription>
                Escribe tu correo y te mandamos un enlace para cambiarla.
              </CardDescription>
            </CardHeader>
            <CardContent>
              {/* Un enlace vencido o ya usado tiene que DECIRLO. Devolver
                  el formulario en blanco deja a la persona pensando que
                  hizo algo mal, y lo que pasó es que el enlace caducó. */}
              {caducado && (
                <p className="mb-4 flex items-start gap-2 rounded-lg bg-warning/10 px-3 py-2 text-sm text-warning">
                  <TriangleAlert className="mt-0.5 size-4 shrink-0" />
                  Ese enlace ya no vale: caducó o se usó. Pide uno nuevo.
                </p>
              )}
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
                    autoFocus
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
                  {enviando ? 'Enviando…' : 'Enviar enlace'}
                </Button>

                <Button variant="ghost" size="sm" asChild>
                  <Link href="/login">
                    <ArrowLeft className="size-4" />
                    Me acordé, volver
                  </Link>
                </Button>
              </form>
            </CardContent>
          </>
        )}
      </Card>
    </main>
  );
}
