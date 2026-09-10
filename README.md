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
| 0-B | CLI de Supabase, línea base, staging, pruebas de RLS con pgTAP | ⏳ siguiente |
| 1 | Esquema `crm`, contactos unificados y timeline | pendiente |
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
npm run dev
```

Abre http://localhost:3000 — redirige a `/login`. Entra con la **misma
cuenta** que usas en la plataforma actual.

## Reglas de arquitectura

Están en [`AGENTS.md`](./AGENTS.md). La corta: **el CRM es dueño del esquema
`crm` y nunca escribe en `public`**.
