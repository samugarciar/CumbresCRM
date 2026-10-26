'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { useTransition, useRef } from 'react';
import { Search, X, Loader2, SlidersHorizontal } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';

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

const ADMINISTRATIVOS = ['administrativa_captacion', 'administrativa', 'captacion'];

/**
 * Los filtros de la bandeja, en una sola fila: de qué línea, solo los que
 * esperan, y buscar. Lo que se usa poco (tipo de contacto, sin teléfono,
 * administrativa o captación por separado) vive en «Más filtros».
 *
 * Los filtros viven en la URL, no en estado de React. Así una búsqueda se
 * puede compartir por chat, recargar sin perderse y volver atrás con el
 * botón del navegador. Los parámetros son los mismos de siempre.
 */
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
  const enAdministrativa = ADMINISTRATIVOS.includes(canalActual);

  // Lo que hay dentro de «Más filtros», para que el botón diga si hay algo puesto.
  const masFiltros =
    (tipo ? 1 : 0) + (soloSinTelefono ? 1 : 0) + (canalActual === 'administrativa' || canalActual === 'captacion' ? 1 : 0);
  const hayFiltros = Boolean(params.get('q') || tipo || soloSinTelefono || soloEsperando);

  const pestanas = [
    {
      clave: 'comercial',
      etiqueta: 'Comercial',
      total: conteos.comercial_total,
      esperando: conteos.comercial_esperando,
      activa: canalActual === 'comercial',
    },
    {
      clave: 'administrativa_captacion',
      etiqueta: 'Administrativa y captación',
      total: conteos.admin_captacion_total,
      esperando: conteos.admin_captacion_esperando,
      activa: enAdministrativa,
    },
    {
      clave: 'todos',
      etiqueta: 'Todas',
      total: conteos.total,
      esperando: conteos.total_esperando,
      activa: canalActual === 'todos',
    },
  ];

  return (
    <div className="flex flex-wrap items-center gap-2">
      {/* Pestañas de línea */}
      <div role="tablist" aria-label="Línea" className="flex max-w-full items-center gap-1 overflow-x-auto rounded-lg bg-muted/60 p-1">
        {pestanas.map((p) => (
          <button
            key={p.clave}
            type="button"
            role="tab"
            aria-selected={p.activa}
            onClick={() => aplicar({ canal: p.clave })}
            className={`flex h-7 shrink-0 items-center gap-1.5 rounded-md px-2.5 text-xs font-medium transition-colors ${
              p.activa
                ? 'bg-background text-foreground shadow-2xs'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            <span>{p.etiqueta}</span>
            <span className="tabular text-muted-foreground">{p.total.toLocaleString('es-CO')}</span>
            {p.esperando > 0 && (
              <span
                className="tabular rounded-full bg-amber-600 px-1.5 py-px text-[11px] font-semibold text-white"
                title={`${p.esperando} esperando respuesta`}
              >
                🔥 {p.esperando}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Solo los que esperan respuesta */}
      <button
        type="button"
        role="switch"
        aria-checked={soloEsperando}
        onClick={() => aplicar({ esperando: soloEsperando ? null : '1' })}
        className={`flex h-9 items-center gap-2 rounded-lg border px-2.5 text-xs font-medium transition-colors ${
          soloEsperando
            ? 'border-amber-600/40 bg-amber-500/10 text-amber-900 dark:text-amber-200'
            : 'bg-background text-muted-foreground hover:text-foreground'
        }`}
      >
        <span
          aria-hidden
          className={`relative inline-flex h-4 w-7 shrink-0 rounded-full transition-colors ${
            soloEsperando ? 'bg-amber-600' : 'bg-muted-foreground/30'
          }`}
        >
          <span
            className={`absolute top-0.5 size-3 rounded-full bg-white shadow-xs transition-all ${
              soloEsperando ? 'left-3.5' : 'left-0.5'
            }`}
          />
        </span>
        Solo esperando
      </button>

      {/* Buscar */}
      <div className="relative min-w-52 flex-1">
        <Search className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          defaultValue={params.get('q') ?? ''}
          onChange={(e) => buscar(e.target.value)}
          placeholder="Buscar por nombre o teléfono"
          className="h-9 rounded-lg bg-background pl-8 text-sm"
          aria-label="Buscar por nombre o teléfono"
        />
        {navegando && (
          <Loader2 className="absolute right-2.5 top-1/2 size-4 -translate-y-1/2 animate-spin text-muted-foreground" />
        )}
      </div>

      {/* Lo que se usa poco */}
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="outline" size="sm" className="h-9 gap-1.5 rounded-lg text-xs">
            <SlidersHorizontal className="size-3.5" />
            Más filtros
            {masFiltros > 0 && (
              <span className="tabular rounded-full bg-primary px-1.5 text-[11px] font-semibold text-primary-foreground">
                {masFiltros}
              </span>
            )}
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-60">
          <DropdownMenuLabel className="text-xs font-normal text-muted-foreground">Tipo de contacto</DropdownMenuLabel>
          <DropdownMenuCheckboxItem
            checked={tipo === 'cliente'}
            onCheckedChange={() => aplicar({ tipo: tipo === 'cliente' ? null : 'cliente' })}
          >
            Clientes
          </DropdownMenuCheckboxItem>
          <DropdownMenuCheckboxItem
            checked={tipo === 'propietario'}
            onCheckedChange={() => aplicar({ tipo: tipo === 'propietario' ? null : 'propietario' })}
          >
            Propietarios
          </DropdownMenuCheckboxItem>

          {(sinTelefono > 0 || soloSinTelefono) && (
            <>
              <DropdownMenuSeparator />
              <DropdownMenuCheckboxItem
                checked={soloSinTelefono}
                onCheckedChange={() => aplicar({ sin_telefono: soloSinTelefono ? null : '1' })}
              >
                Sin teléfono ({sinTelefono})
              </DropdownMenuCheckboxItem>
            </>
          )}

          {enAdministrativa && (
            <>
              <DropdownMenuSeparator />
              <DropdownMenuLabel className="text-xs font-normal text-muted-foreground">
                Administrativa y captación
              </DropdownMenuLabel>
              <DropdownMenuRadioGroup value={canalActual} onValueChange={(v) => aplicar({ canal: v })}>
                <DropdownMenuRadioItem value="administrativa_captacion">
                  Las dos ({conteos.admin_captacion_total})
                </DropdownMenuRadioItem>
                <DropdownMenuRadioItem value="administrativa">
                  Solo administrativa ({conteos.admin_total})
                </DropdownMenuRadioItem>
                <DropdownMenuRadioItem value="captacion">
                  Solo captación ({conteos.captacion_total})
                </DropdownMenuRadioItem>
              </DropdownMenuRadioGroup>
            </>
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      {hayFiltros && (
        <Button
          variant="ghost"
          size="sm"
          onClick={() => iniciarNavegacion(() => router.push(`/contactos?canal=${canalActual}`))}
          className="h-9 gap-1 rounded-lg text-xs text-muted-foreground hover:text-foreground"
        >
          <X className="size-3.5" />
          Limpiar
        </Button>
      )}
    </div>
  );
}
