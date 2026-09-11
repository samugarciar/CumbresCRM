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
| 1-A | Esquema `crm`, contactos y normalizador de teléfonos | ✅ hecho |
| 1-B | Eventos, actividades, identidades, triggers de proyección y backfill | ✅ hecho |
| 1-C | Lista de contactos y ficha con timeline | ✅ hecho |
| 2 | Pipeline comercial y kanban | ⏳ siguiente |
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
supabase start               # levanta Postgres, Auth y Studio en Docker
npm run db:reset             # aplica la línea base y siembra datos de prueba
npm run db:test              # 102 pruebas pgTAP: RLS, identidad, proyección, bandeja y nombres
npm run dev
```

El Studio local queda en http://localhost:54323 y los correos de prueba
en http://localhost:54324.

Entra con un usuario del seed: `alfa@prueba.local` / `prueba1234`.

Para trabajar con volumen real en vez de tres filas de juguete:

```bash
npm run db:fixture   # ~4.900 filas con la forma del histórico de producción
```

…y luego `SELECT crm.backfill('11111111-1111-1111-1111-111111111111');` en el
Studio. Deja 1.241 contactos y 3.980 actividades.

### Los dos entornos

| Archivo | Apunta a | Quién lo carga |
|---|---|---|
| `.env.local` | Supabase local (Docker) | `npm run dev`, automáticamente |
| `.env.produccion` | El proyecto real de Supabase | **Nadie.** Hay que copiarlo a mano |

Para trabajar contra producción —cosa que casi nunca deberías necesitar—:

```bash
cp .env.produccion .env.local   # y reinicia el servidor
```

Que exija un paso manual es deliberado: el desarrollo diario no debería
poder tocar datos de clientes por accidente. Para volver a local, las
llaves salen de `supabase status -o env`.

## Al desplegar a producción

> ⚠️ El esquema `crm` hay que **exponerlo en PostgREST** también en producción:
> Settings → API → Exposed schemas. En local lo hace `supabase/config.toml`.
> Sin eso, `supabase-js` responde `Invalid schema: crm` y la app no ve nada.
>
> **Ojo en local:** cambiar `[api] schemas` en `config.toml` no basta con
> `npm run db:reset` — PostgREST solo relee su configuración al arrancar.
> Hay que hacer `supabase stop && supabase start`.

## Reglas de arquitectura

Están en [`AGENTS.md`](./AGENTS.md). La corta: **el CRM es dueño del esquema
`crm` y nunca escribe en `public`**.
