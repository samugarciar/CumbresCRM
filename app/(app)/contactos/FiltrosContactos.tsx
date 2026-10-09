'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { useTransition, useRef } from 'react';
import { Search, X, Loader2, PhoneOff, Users, Flame, MessageSquare, Building2, Briefcase, Globe } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';

export interface ConteosBandeja {
  total: number;
  total_esperando: number;
  comercial_total: number;
  comercial_esperando: number;
  admin_captacion_total: number;
  admin_captacion_esperando: number;
  admin_total: number;
  admin_esperando: number;
  captacion_total: number;
  captacion_esperando: number;
}

interface Props {
  sinTelefono: number;
  canalActual: string;
  conteos: ConteosBandeja;
}

// Los filtros viven en la URL, no en estado de React. Así una búsqueda se
// puede compartir por chat, recargar sin perderse y volver atrás con el
// botón del navegador.
export function FiltrosContactos({ sinTelefono, canalActual, conteos }: Props) {
  const router = useRouter();
  const params = useSearchParams();
  const [navegando, iniciarNavegacion] = useTransition();
  const temporizador = useRef<ReturnType<typeof setTimeout> | null>(null);

  const aplicar = (cambios: Record<string, string | null>) => {
    const siguientes = new URLSearchParams(params.toString());
    for (const [clave, valor] of Object.entries(cambios)) {
      if (valor === null || valor === '') siguientes.delete(clave);
      else siguientes.set(clave, valor);
    }
    // Cualquier filtro nuevo invalida el cursor
    siguientes.delete('cursor_at');
    siguientes.delete('cursor_id');
    iniciarNavegacion(() => router.push(`/contactos?${siguientes.toString()}`));
  };

  const buscar = (texto: string) => {
    if (temporizador.current) clearTimeout(temporizador.current);
    temporizador.current = setTimeout(() => aplicar({ q: texto }), 350);
  };

  const tipo = params.get('tipo');
  const soloSinTelefono = params.get('sin_telefono') === '1';
  const soloEsperando = params.get('esperando') === '1';
  const hayFiltros = Boolean(params.get('q') || tipo || params.get('sin_telefono') || params.get('esperando'));

  const esperandoEnCanal =
    canalActual === 'comercial'
      ? conteos.comercial_esperando
      : canalActual === 'administrativa'
      ? conteos.admin_esperando
      : canalActual === 'captacion'
      ? conteos.captacion_esperando
      : canalActual === 'administrativa_captacion'
      ? conteos.admin_captacion_esperando
      : conteos.total_esperando;

  return (
    <div className="flex flex-col gap-3.5">
      {/* Nivel 1: Selector principal de Canal / Línea */}
      <div className="flex flex-wrap items-center justify-between gap-2.5 border-b border-border/50 pb-3">
        <div className="flex flex-wrap items-center gap-2">
          {/* Vista Comercial */}
          <Button
            variant={canalActual === 'comercial' ? 'default' : 'outline'}
            size="sm"
            onClick={() => aplicar({ canal: 'comercial' })}
            className={`h-9 rounded-xl text-xs font-semibold px-3.5 transition-all ${
              canalActual === 'comercial'
                ? 'bg-sky-600 text-white hover:bg-sky-700 shadow-2xs'
                : 'text-muted-foreground hover:text-foreground hover:bg-muted/80'
            }`}
          >
            <Briefcase className="size-3.5 mr-1.5" />
            <span>Comercial · Línea 324</span>
            <span
              className={`ml-2 rounded-full px-1.5 py-0.2 tabular text-[10px] font-bold ${
                canalActual === 'comercial' ? 'bg-white/20 text-white' : 'bg-muted text-muted-foreground'
              }`}
            >
              {conteos.comercial_total}
            </span>
            {conteos.comercial_esperando > 0 && (
              <span className="ml-1 flex items-center gap-0.5 rounded-full bg-amber-500/20 text-amber-700 dark:text-amber-300 px-1.5 py-0.2 text-[10px] font-bold">
                🔥 {conteos.comercial_esperando}
              </span>
            )}
          </Button>

          {/* Vista Administrativo y Captaciones */}
          <Button
            variant={
              canalActual === 'administrativa_captacion' ||
              canalActual === 'administrativa' ||
              canalActual === 'captacion'
                ? 'default'
                : 'outline'
            }
            size="sm"
            onClick={() => aplicar({ canal: 'administrativa_captacion' })}
            className={`h-9 rounded-xl text-xs font-semibold px-3.5 transition-all ${
              canalActual === 'administrativa_captacion' ||
              canalActual === 'administrativa' ||
              canalActual === 'captacion'
                ? 'bg-purple-600 text-white hover:bg-purple-700 shadow-2xs'
                : 'text-muted-foreground hover:text-foreground hover:bg-muted/80'
            }`}
          >
            <Building2 className="size-3.5 mr-1.5" />
            <span>Administrativo y Captaciones · Línea 320</span>
            <span
              className={`ml-2 rounded-full px-1.5 py-0.2 tabular text-[10px] font-bold ${
                canalActual === 'administrativa_captacion' ||
                canalActual === 'administrativa' ||
                canalActual === 'captacion'
                  ? 'bg-white/20 text-white'
                  : 'bg-muted text-muted-foreground'
              }`}
            >
              {conteos.admin_captacion_total}
            </span>
            {conteos.admin_captacion_esperando > 0 && (
              <span className="ml-1 flex items-center gap-0.5 rounded-full bg-amber-500/20 text-amber-700 dark:text-amber-300 px-1.5 py-0.2 text-[10px] font-bold">
                🔥 {conteos.admin_captacion_esperando}
              </span>
            )}
          </Button>

          {/* Todos los canales */}
          <Button
            variant={canalActual === 'todos' ? 'default' : 'ghost'}
            size="sm"
            onClick={() => aplicar({ canal: 'todos' })}
            className={`h-9 rounded-xl text-xs font-medium px-3 transition-all ${
              canalActual === 'todos'
                ? 'bg-muted text-foreground font-semibold shadow-2xs'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            <Globe className="size-3.5 mr-1 opacity-70" />
            <span>Todos ({conteos.total})</span>
            {conteos.total_esperando > 0 && (
              <span className="ml-1.5 flex items-center gap-0.5 rounded-full bg-amber-500/20 text-amber-700 dark:text-amber-300 px-1.5 py-0.2 text-[10px] font-bold">
                🔥 {conteos.total_esperando}
              </span>
            )}
          </Button>
        </div>

        {/* Sub-filtro para Administrativo y Captaciones */}
        {(canalActual === 'administrativa_captacion' ||
          canalActual === 'administrativa' ||
          canalActual === 'captacion') && (
          <div className="flex items-center gap-1 rounded-xl bg-purple-500/10 p-1 border border-purple-500/20 text-xs">
            <button
              type="button"
              onClick={() => aplicar({ canal: 'administrativa_captacion' })}
              className={`px-2.5 py-1 rounded-lg text-[11px] font-medium transition-all cursor-pointer ${
                canalActual === 'administrativa_captacion'
                  ? 'bg-purple-600 text-white font-semibold shadow-2xs'
                  : 'text-purple-800 dark:text-purple-300 hover:bg-purple-500/15'
              }`}
            >
              Ambos ({conteos.admin_captacion_total})
            </button>
            <button
              type="button"
              onClick={() => aplicar({ canal: 'administrativa' })}
              className={`px-2.5 py-1 rounded-lg text-[11px] font-medium transition-all cursor-pointer ${
                canalActual === 'administrativa'
                  ? 'bg-purple-600 text-white font-semibold shadow-2xs'
                  : 'text-purple-800 dark:text-purple-300 hover:bg-purple-500/15'
              }`}
            >
              Solo Administrativa ({conteos.admin_total})
            </button>
            <button
              type="button"
              onClick={() => aplicar({ canal: 'captacion' })}
              className={`px-2.5 py-1 rounded-lg text-[11px] font-medium transition-all cursor-pointer ${
                canalActual === 'captacion'
                  ? 'bg-purple-600 text-white font-semibold shadow-2xs'
                  : 'text-purple-800 dark:text-purple-300 hover:bg-purple-500/15'
              }`}
            >
              Solo Captación ({conteos.captacion_total})
            </button>
          </div>
        )}
      </div>

      {/* Nivel 2: Turno de respuesta (Todos vs Esperando respuesta) */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-1 rounded-xl bg-muted/60 p-1 border border-border/50 shadow-2xs">
          <Button
            variant={!soloEsperando ? 'default' : 'ghost'}
            size="sm"
            onClick={() => aplicar({ esperando: null })}
            className={`h-8 rounded-lg text-xs font-medium px-3.5 transition-all ${
              !soloEsperando
                ? 'bg-background text-foreground shadow-2xs font-semibold'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            <MessageSquare className="size-3.5 mr-1.5 opacity-70" />
            Todos los mensajes
          </Button>

          <Button
            variant={soloEsperando ? 'default' : 'ghost'}
            size="sm"
            onClick={() => aplicar({ esperando: soloEsperando ? null : '1' })}
            className={`h-8 rounded-lg text-xs font-medium px-3.5 transition-all ${
              soloEsperando
                ? 'bg-amber-600 text-white hover:bg-amber-700 shadow-2xs font-semibold'
                : 'text-amber-700 dark:text-amber-400 hover:text-amber-800 hover:bg-amber-500/10'
            }`}
          >
            <Flame className={`size-3.5 mr-1.5 ${soloEsperando ? 'text-white' : 'text-amber-500'}`} />
            Esperando respuesta
            {esperandoEnCanal > 0 && (
              <span
                className={`ml-1.5 rounded-full px-1.5 py-0.2 tabular text-[11px] font-bold ${
                  soloEsperando ? 'bg-white/20 text-white' : 'bg-amber-500/20 text-amber-700 dark:text-amber-300'
                }`}
              >
                {esperandoEnCanal}
              </span>
            )}
          </Button>
        </div>
      </div>

      {/* Nivel 3: Barra de búsqueda y filtros secundarios */}
      <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-border/60 bg-card/60 p-2 shadow-2xs backdrop-blur-xs">
        <div className="relative min-w-64 flex-1">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            defaultValue={params.get('q') ?? ''}
            onChange={(e) => buscar(e.target.value)}
            placeholder="Buscar por nombre, teléfono o mensaje…"
            className="h-9 rounded-xl border-border/60 bg-background/70 pl-9 text-sm focus-visible:bg-background"
            aria-label="Buscar contactos"
          />
          {navegando && (
            <Loader2 className="absolute right-3 top-1/2 size-4 -translate-y-1/2 animate-spin text-muted-foreground" />
          )}
        </div>

        <div className="flex flex-wrap items-center gap-1.5">
          <div className="flex items-center gap-1">
            {(['cliente', 'propietario'] as const).map((t) => (
              <Button
                key={t}
                variant={tipo === t ? 'default' : 'outline'}
                size="sm"
                onClick={() => aplicar({ tipo: tipo === t ? null : t })}
                className={`h-9 rounded-xl text-xs font-medium capitalize transition-all ${
                  tipo === t ? 'shadow-xs' : ''
                }`}
              >
                <Users className="size-3.5 opacity-60" />
                {t}s
              </Button>
            ))}
          </div>

          <div className="mx-1 hidden h-5 w-px bg-border/60 sm:block" />

          <Button
            variant={soloSinTelefono ? 'default' : 'outline'}
            size="sm"
            onClick={() => aplicar({ sin_telefono: soloSinTelefono ? null : '1' })}
            className={`h-9 rounded-xl text-xs font-medium transition-all ${
              soloSinTelefono
                ? 'bg-amber-600 text-white hover:bg-amber-700 dark:bg-amber-700 shadow-xs'
                : 'hover:border-amber-500/40 hover:text-amber-600 dark:hover:text-amber-400'
            }`}
            title="Personas reales con conversación, pero sin un número al que llamar"
          >
            <PhoneOff className="size-3.5" />
            <span>Sin teléfono</span>
            <span
              className={`ml-1.5 rounded-full px-1.5 py-0.2 tabular text-[11px] font-semibold ${
                soloSinTelefono ? 'bg-black/20 text-white' : 'bg-muted text-muted-foreground'
              }`}
            >
              {sinTelefono}
            </span>
          </Button>

          {hayFiltros && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => iniciarNavegacion(() => router.push(`/contactos?canal=${canalActual}`))}
              className="h-9 rounded-xl text-xs text-muted-foreground hover:text-foreground"
            >
              <X className="size-3.5" />
              Limpiar
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}
