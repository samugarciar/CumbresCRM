'use client';

import * as React from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import {
  Sun,
  Users,
  Kanban,
  Sparkles,
  Flame,
  BotOff,
  FileText,
  Smartphone,
  Menu,
  X,
  ChevronLeft,
  ChevronRight,
  LogOut,
  Building2,
} from 'lucide-react';
import { iniciales } from '@/lib/formato';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { cerrarSesion } from '@/app/actions/auth';

interface UsuarioSesion {
  email: string;
  nombre: string;
  rol: string;
}

interface ElementoNav {
  href: string;
  etiqueta: string;
  icono: React.ComponentType<{ className?: string }>;
  descripcion?: string;
}

interface GrupoNav {
  titulo: string;
  elementos: ElementoNav[];
}

const GRUPOS_NAV: GrupoNav[] = [
  {
    titulo: 'Operación',
    elementos: [
      {
        href: '/mi-dia',
        etiqueta: 'Mi día',
        icono: Sun,
        descripcion: 'Prioridades y tareas de hoy',
      },
      {
        href: '/contactos',
        etiqueta: 'Contactos',
        icono: Users,
        descripcion: 'Directorio y fichas de clientes',
      },
      {
        href: '/tablero',
        etiqueta: 'Tablero',
        icono: Kanban,
        descripcion: 'Pipeline comercial y etapas',
      },
    ],
  },
  {
    titulo: 'Oportunidades',
    elementos: [
      {
        href: '/coincidencias',
        etiqueta: 'Coincidencias',
        icono: Sparkles,
        descripcion: 'Cruce catálogo vs requerimientos',
      },
      {
        href: '/reactivacion',
        etiqueta: 'Reactivación',
        icono: Flame,
        descripcion: 'Leads fríos para reenganche',
      },
    ],
  },
  {
    titulo: 'Canal & Supervisión',
    elementos: [
      {
        href: '/bot-callado',
        etiqueta: 'Bot callado',
        icono: BotOff,
        descripcion: 'Conversaciones con bot silenciado',
      },
      {
        href: '/plantillas',
        etiqueta: 'Plantillas',
        icono: FileText,
        descripcion: 'Mensajes aprobados por Meta',
      },
      {
        href: '/lineas',
        etiqueta: 'Líneas',
        icono: Smartphone,
        descripcion: 'Estado de WhatsApp y tokens',
      },
    ],
  },
];

export function ShellNavegacion({
  usuario,
  children,
}: {
  usuario: UsuarioSesion;
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const [colapsado, setColapsado] = React.useState(false);
  const [menuMovilAbierto, setMenuMovilAbierto] = React.useState(false);

  // Cierra el drawer móvil al cambiar de ruta
  const [rutaPrevia, setRutaPrevia] = React.useState(pathname);
  if (pathname !== rutaPrevia) {
    setRutaPrevia(pathname);
    setMenuMovilAbierto(false);
  }

  // Cierra con Escape en móvil
  React.useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === 'Escape') setMenuMovilAbierto(false);
    }
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);

  function esActivo(href: string) {
    if (pathname === href) return true;
    if (href !== '/mi-dia' && pathname.startsWith(href + '/')) return true;
    return false;
  }

  // Obtiene el título legible de la sección actual para el breadcrumb contextual
  const elementoActual = GRUPOS_NAV.flatMap((g) => g.elementos).find((item) =>
    esActivo(item.href)
  );

  return (
    <div className="flex min-h-screen bg-background">
      {/* ==============================================================
          SIDEBAR DE ESCRITORIO (Desktop)
          ============================================================== */}
      <aside
        className={`hidden md:flex flex-col border-r bg-card transition-all duration-200 select-none z-30 shrink-0 ${
          colapsado ? 'w-18' : 'w-64'
        }`}
      >
        {/* Cabecera del Sidebar con Marca y Botón de Colapso */}
        <div className="flex h-16 items-center justify-between border-b px-4">
          {!colapsado && (
            <Link
              href="/mi-dia"
              className="flex items-center gap-2.5 transition-opacity hover:opacity-90"
            >
              <div className="flex size-9 items-center justify-center rounded-lg bg-primary text-primary-foreground shadow-xs">
                <Building2 className="size-5" />
              </div>
              <div className="flex flex-col">
                <span className="text-base font-bold leading-none tracking-tight">
                  Cumbres
                </span>
                <span className="text-[11px] font-medium text-muted-foreground uppercase tracking-wider mt-0.5">
                  CRM Inmobiliario
                </span>
              </div>
            </Link>
          )}

          {colapsado && (
            <Link
              href="/mi-dia"
              className="mx-auto flex size-9 items-center justify-center rounded-lg bg-primary text-primary-foreground shadow-xs"
              title="Cumbres CRM"
            >
              <Building2 className="size-5" />
            </Link>
          )}

          <Button
            variant="ghost"
            size="icon-xs"
            onClick={() => setColapsado(!colapsado)}
            className="text-muted-foreground hover:text-foreground hidden lg:flex"
            title={colapsado ? 'Expandir barra lateral' : 'Colapsar barra lateral'}
          >
            {colapsado ? (
              <ChevronRight className="size-4" />
            ) : (
              <ChevronLeft className="size-4" />
            )}
          </Button>
        </div>

        {/* Lista de Navegación por Grupos */}
        <nav className="flex-1 overflow-y-auto px-3 py-4 space-y-6">
          {GRUPOS_NAV.map((grupo) => (
            <div key={grupo.titulo} className="space-y-1">
              {!colapsado && (
                <p className="px-3 pb-1 text-[11px] font-semibold text-muted-foreground uppercase tracking-wider">
                  {grupo.titulo}
                </p>
              )}
              <div className="space-y-1">
                {grupo.elementos.map((item) => {
                  const Icono = item.icono;
                  const activo = esActivo(item.href);

                  return (
                    <Link
                      key={item.href}
                      href={item.href}
                      title={colapsado ? item.etiqueta : undefined}
                      className={`group relative flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-all ${
                        activo
                          ? 'bg-primary/10 text-primary font-semibold'
                          : 'text-muted-foreground hover:bg-muted hover:text-foreground'
                      } ${colapsado ? 'justify-center px-0' : ''}`}
                    >
                      {/* Indicador visual lateral de ruta activa */}
                      {activo && (
                        <span className="absolute left-0 top-1.5 bottom-1.5 w-1 rounded-r-md bg-primary" />
                      )}

                      <Icono
                        className={`size-4.5 shrink-0 transition-transform group-hover:scale-105 ${
                          activo ? 'text-primary' : 'text-muted-foreground group-hover:text-foreground'
                        }`}
                      />

                      {!colapsado && (
                        <div className="flex-1 truncate">
                          <span className="truncate">{item.etiqueta}</span>
                        </div>
                      )}
                    </Link>
                  );
                })}
              </div>
            </div>
          ))}
        </nav>

        {/* Perfil del Usuario y Salida */}
        <div className="border-t p-3 bg-muted/30">
          <div
            className={`flex items-center gap-3 rounded-lg p-2 ${
              colapsado ? 'justify-center p-0' : ''
            }`}
          >
            <div className="flex size-9 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary font-semibold text-xs border border-primary/20">
              {iniciales(usuario.nombre)}
            </div>

            {!colapsado && (
              <div className="min-w-0 flex-1">
                <p className="truncate text-xs font-semibold text-foreground">
                  {usuario.nombre}
                </p>
                <div className="flex items-center gap-1.5 mt-0.5">
                  <Badge variant="outline" className="text-[10px] h-4 px-1.5 py-0 capitalize">
                    {usuario.rol}
                  </Badge>
                </div>
              </div>
            )}

            <form
              action={async () => {
                await cerrarSesion();
                router.push('/login');
                router.refresh();
              }}
            >
              <Button
                type="submit"
                variant="ghost"
                size="icon-xs"
                className="text-muted-foreground hover:text-destructive hover:bg-destructive/10"
                title="Cerrar sesión"
              >
                <LogOut className="size-4" />
              </Button>
            </form>
          </div>
        </div>
      </aside>

      {/* ==============================================================
          CABECERA Y DRAWER MÓVIL (< md)
          ============================================================== */}
      <div className="md:hidden fixed top-0 left-0 right-0 z-40 flex h-14 items-center justify-between border-b bg-card px-4 shadow-2xs">
        <div className="flex items-center gap-3">
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={() => setMenuMovilAbierto(true)}
            className="text-foreground"
            aria-label="Abrir menú"
          >
            <Menu className="size-5" />
          </Button>

          <Link href="/mi-dia" className="flex items-center gap-2">
            <div className="flex size-7 items-center justify-center rounded-md bg-primary text-primary-foreground shadow-2xs">
              <Building2 className="size-4" />
            </div>
            <span className="font-bold tracking-tight text-sm">Cumbres CRM</span>
          </Link>
        </div>

        <div className="flex items-center gap-2">
          <div className="flex size-7 items-center justify-center rounded-full bg-primary/10 text-primary font-semibold text-xs border border-primary/20">
            {iniciales(usuario.nombre)}
          </div>
        </div>
      </div>

      {/* Overlay del Drawer Móvil */}
      {menuMovilAbierto && (
        <div className="md:hidden fixed inset-0 z-50 flex">
          {/* Fondo oscuro con desenfoque */}
          <div
            className="fixed inset-0 bg-black/50 backdrop-blur-xs transition-opacity"
            onClick={() => setMenuMovilAbierto(false)}
          />

          {/* Panel deslizante */}
          <div className="relative flex w-4/5 max-w-xs flex-1 flex-col bg-card border-r shadow-xl">
            <div className="flex h-14 items-center justify-between border-b px-4">
              <Link
                href="/mi-dia"
                onClick={() => setMenuMovilAbierto(false)}
                className="flex items-center gap-2"
              >
                <div className="flex size-7 items-center justify-center rounded-md bg-primary text-primary-foreground">
                  <Building2 className="size-4" />
                </div>
                <span className="font-bold tracking-tight text-sm">Cumbres CRM</span>
              </Link>

              <Button
                variant="ghost"
                size="icon-xs"
                onClick={() => setMenuMovilAbierto(false)}
                className="text-muted-foreground"
              >
                <X className="size-4" />
              </Button>
            </div>

            <nav className="flex-1 overflow-y-auto p-4 space-y-6">
              {GRUPOS_NAV.map((grupo) => (
                <div key={grupo.titulo} className="space-y-1">
                  <p className="px-2 text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                    {grupo.titulo}
                  </p>
                  <div className="space-y-1">
                    {grupo.elementos.map((item) => {
                      const Icono = item.icono;
                      const activo = esActivo(item.href);

                      return (
                        <Link
                          key={item.href}
                          href={item.href}
                          onClick={() => setMenuMovilAbierto(false)}
                          className={`flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors ${
                            activo
                              ? 'bg-primary/10 text-primary font-semibold'
                              : 'text-muted-foreground hover:bg-muted hover:text-foreground'
                          }`}
                        >
                          <Icono
                            className={`size-4.5 ${
                              activo ? 'text-primary' : 'text-muted-foreground'
                            }`}
                          />
                          <span>{item.etiqueta}</span>
                        </Link>
                      );
                    })}
                  </div>
                </div>
              ))}
            </nav>

            <div className="border-t p-4 bg-muted/30">
              <div className="flex items-center justify-between">
                <div className="min-w-0 flex-1 pr-2">
                  <p className="truncate text-xs font-semibold text-foreground">
                    {usuario.nombre}
                  </p>
                  <p className="text-[11px] text-muted-foreground capitalize">
                    {usuario.rol}
                  </p>
                </div>
                <form
                  action={async () => {
                    await cerrarSesion();
                    router.push('/login');
                    router.refresh();
                  }}
                >
                  <Button
                    type="submit"
                    variant="outline"
                    size="sm"
                    className="gap-1.5 text-xs text-destructive hover:bg-destructive/10"
                  >
                    <LogOut className="size-3.5" />
                    Salir
                  </Button>
                </form>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ==============================================================
          CONTENEDOR PRINCIPAL
          ============================================================== */}
      <div className="flex min-w-0 flex-1 flex-col pt-14 md:pt-0">
        {/* Barra superior de contexto (Desktop) */}
        <header className="hidden md:flex h-14 items-center justify-between border-b bg-card/60 backdrop-blur-xs px-6 sticky top-0 z-20">
          <div className="flex items-center gap-2 text-sm">
            <span className="text-muted-foreground font-medium">Cumbres CRM</span>
            <span className="text-muted-foreground/60">/</span>
            <span className="font-semibold text-foreground">
              {elementoActual?.etiqueta ?? 'Espacio de trabajo'}
            </span>
          </div>

          <div className="flex items-center gap-3">
            <div className="text-xs text-muted-foreground font-medium hidden lg:inline-flex items-center gap-1.5 bg-muted/60 px-2.5 py-1 rounded-md border">
              <span>Consejo:</span>
              <kbd className="font-mono text-[10px] bg-background px-1 py-0.5 rounded border shadow-2xs">
                ⌘ + Enter
              </kbd>
              <span>para guardar notas rápido</span>
            </div>
          </div>
        </header>

        {/* Área del Contenido */}
        <main className="flex-1 p-4 md:p-6 lg:p-8 overflow-y-auto">
          {children}
        </main>
      </div>
    </div>
  );
}
