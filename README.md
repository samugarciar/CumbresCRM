# Cumbres CRM

CRM propio de **Cumbres Inmobiliaria**, en construcción. Reemplazará el uso
actual de Kommo: primero el pipeline y la memoria de clientes, y al final el
canal de WhatsApp.

Va **en paralelo** a [CumbresStateInventory](https://github.com/samugarciar/CumbresStateInventory),
con el que **comparte base de datos y Auth** — mismo proyecto de Supabase,
distinto esquema.

> **Stack:** Next.js 16 (App Router + Turbopack) · React 19 · TypeScript ·
> Tailwind v4 + shadcn/ui · Supabase (PostgreSQL + RLS + Auth).

## Estado

| Fase | Qué es | Estado |
|---|---|---|
| 0-A | Andamiaje: app, diseño, sesión compartida | ✅ hecho |
| 0-B | CLI de Supabase, línea base y pruebas de RLS con pgTAP | ✅ hecho |
| 1 | Esquema `crm`, contactos unificados y timeline | ⏳ siguiente |
| 2 | Pipeline comercial y kanban | pendiente |
| 3 | Requerimientos y matching contra el catálogo | pendiente |
| 4 | Tareas y "Mi día" | pendiente |
| 5 | Canal propio de WhatsApp — salida de Kommo | pendiente |
| 6 | Captación como segundo pipeline | pendiente |
| 7 | Reportes y cierre de ciclo con Meta | pendiente |

## Desarrollo local

Requisitos: Node 20+ y acceso al proyecto de Supabase de Cumbres.

```bash
npm install
cp .env.example .env.local   # y completa los tres valores
supabase start               # levanta Postgres, Auth y Studio en Docker
npm run db:reset             # aplica la línea base y siembra datos de prueba
npm run db:test              # 16 pruebas pgTAP: aislamiento RLS y proyección
npm run dev
```

El Studio local queda en http://localhost:54323 y los correos de prueba
en http://localhost:54324.

> ⚠️ Hoy `.env.local` apunta a **producción**. Cambiarlo a la base local es
> el siguiente ajuste pendiente.

Abre http://localhost:3000 — redirige a `/login`. Entra con la **misma
cuenta** que usas en la plataforma actual.

## Reglas de arquitectura

Están en [`AGENTS.md`](./AGENTS.md). La corta: **el CRM es dueño del esquema
`crm` y nunca escribe en `public`**.
