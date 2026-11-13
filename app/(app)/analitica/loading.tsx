import { Skeleton } from '@/components/ui/skeleton';

// La analítica de 30 días tarda unos 2,5 s en producción (medido el 13
// nov): mejor enseñar la forma de la página que una pantalla en blanco.
export default function CargandoAnalitica() {
  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-6" aria-busy="true">
      <header className="flex flex-col gap-4 border-b pb-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-foreground">Analítica</h1>
          <p className="mt-0.5 text-sm text-muted-foreground">Calculando los números del periodo…</p>
        </div>
        <Skeleton className="h-10 w-full max-w-xl rounded-xl" />
      </header>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6">
        {Array.from({ length: 6 }).map((_, i) => (
          <Skeleton key={i} className="h-32 rounded-xl" />
        ))}
      </div>
      <Skeleton className="h-24 rounded-xl" />
      <Skeleton className="h-72 rounded-xl" />
      <div className="grid gap-6 lg:grid-cols-2">
        <Skeleton className="h-80 rounded-xl" />
        <Skeleton className="h-80 rounded-xl" />
      </div>
    </div>
  );
}
