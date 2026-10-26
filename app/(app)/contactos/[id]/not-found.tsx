import Link from 'next/link';
import { ArrowLeft, UserX } from 'lucide-react';
import { Button } from '@/components/ui/button';

/**
 * La ficha que no existe y la que es de otra inmobiliaria se ven igual a
 * propósito: la RLS las devuelve vacías a las dos, y decir «no tienes
 * acceso» solo cuando existe confirmaría que existe.
 */
export default function ContactoNoEncontrado() {
  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col items-center gap-3 rounded-xl border border-dashed bg-card/60 px-4 py-16 text-center">
      <div className="grid size-12 place-items-center rounded-full bg-muted">
        <UserX className="size-6 text-muted-foreground" />
      </div>
      <h1 className="text-lg font-semibold text-foreground">
        Este contacto no existe o no tienes acceso
      </h1>
      <p className="max-w-sm text-sm text-muted-foreground">
        Puede que el enlace esté incompleto o que la conversación sea de otra inmobiliaria.
      </p>
      <Button asChild size="sm" className="mt-1 h-8 gap-1.5 rounded-lg">
        <Link href="/contactos">
          <ArrowLeft className="size-4" />
          Volver a la bandeja
        </Link>
      </Button>
    </div>
  );
}
