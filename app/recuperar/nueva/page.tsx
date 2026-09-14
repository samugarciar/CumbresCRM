'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { Check, Loader2 } from 'lucide-react';
import { cambiarContrasena } from '@/app/actions/auth';
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

const MINIMO = 8;

export default function PaginaNuevaContrasena() {
  const [password, setPassword] = useState('');
  const [repetida, setRepetida] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [listo, setListo] = useState(false);
  const [enviando, iniciarTransicion] = useTransition();
  const router = useRouter();

  const corta = password.length > 0 && password.length < MINIMO;
  const distintas = repetida.length > 0 && password !== repetida;

  const manejarEnvio = (evento: React.FormEvent<HTMLFormElement>) => {
    evento.preventDefault();
    setError(null);
    const formData = new FormData(evento.currentTarget);
    iniciarTransicion(async () => {
      const r = await cambiarContrasena(formData);
      if (!r.ok) {
        setError(r.error ?? 'No se pudo cambiar la contraseña.');
        return;
      }
      setListo(true);
      // El cambio de contraseña deja la sesión abierta, así que se entra
      // directo. Pedirle que vuelva a escribir la contraseña que acaba de
      // inventar sería castigar a quien ya demostró ser quien dice.
      router.push('/contactos');
      router.refresh();
    });
  };

  return (
    <main className="flex min-h-full flex-1 items-center justify-center p-6">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle className="text-2xl">Nueva contraseña</CardTitle>
          <CardDescription>
            Al menos {MINIMO} caracteres. Es la misma que usarás para la
            plataforma de inventario: son la misma cuenta.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={manejarEnvio} className="flex flex-col gap-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="password">Contraseña nueva</Label>
              <Input
                id="password"
                name="password"
                type="password"
                autoComplete="new-password"
                required
                autoFocus
                disabled={enviando || listo}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                aria-invalid={corta || undefined}
              />
              {corta && (
                <p className="text-xs text-muted-foreground">
                  Le faltan {MINIMO - password.length} caracteres.
                </p>
              )}
            </div>

            <div className="flex flex-col gap-2">
              <Label htmlFor="repetida">Repítela</Label>
              <Input
                id="repetida"
                name="repetida"
                type="password"
                autoComplete="new-password"
                required
                disabled={enviando || listo}
                value={repetida}
                onChange={(e) => setRepetida(e.target.value)}
                aria-invalid={distintas || undefined}
              />
              {distintas && (
                <p className="text-xs text-destructive">No coinciden.</p>
              )}
            </div>

            {error && (
              <p role="alert" className="text-sm text-destructive">
                {error}
              </p>
            )}

            <Button
              type="submit"
              disabled={enviando || listo || corta || distintas || !password}
              className="mt-1"
            >
              {enviando && <Loader2 className="animate-spin" />}
              {listo && <Check className="size-4" />}
              {listo ? 'Lista, entrando…' : enviando ? 'Guardando…' : 'Guardar y entrar'}
            </Button>
          </form>
        </CardContent>
      </Card>
    </main>
  );
}
