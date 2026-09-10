# Cumbres CRM

## Esto NO es el Next.js que conoces

Esta versión trae cambios que rompen: APIs, convenciones y estructura de
archivos pueden diferir de lo que tengas aprendido. **Lee la guía
correspondiente en `node_modules/next/dist/docs/` antes de escribir código.**
Atiende los avisos de deprecación.

Ya nos mordió una vez: `middleware.ts` está deprecado en Next 16 y se
renombró a `proxy.ts`, con la función exportada como `proxy`.

## La regla de arquitectura que no se rompe

El CRM comparte el proyecto de Supabase con `CumbresStateInventory`, pero:

- **El CRM es dueño del esquema `crm`. Nunca escribe en `public`.**
- Lo que necesita de `public` (inmuebles, citas, usuarios) lo lee por
  **vistas de solo lectura** definidas en `crm`, no por consultas directas.
  Así el otro repo puede cambiar sus tablas y lo que se rompe es una vista,
  en un solo sitio, y no cuarenta consultas repartidas.
- Los datos entran al CRM **proyectados por triggers** desde `public`. Todo
  trigger de proyección va envuelto en `EXCEPTION WHEN OTHERS` y deja el
  evento en `crm.eventos`: si el CRM falla, **no puede tumbar la transacción
  del agente comercial**, que atiende clientes reales por WhatsApp.
- Migraciones nuevas: `supabase db diff --schema crm`. Si una migración del
  CRM toca `public`, es un error de revisión.

## Convenciones

- Código y comentarios en español, como el repo de la plataforma.
- Validación con zod en toda entrada de servidor, aunque el cliente valide.
- Dinero en `numeric`, nunca `float`. Fechas en `timestamptz`.
- Teléfonos normalizados a E.164 (`+57...`): es la llave natural del contacto.

<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

## Flujo de base de datos

La base local de Docker es una réplica de la **forma** de producción (21
tablas, 46 políticas, el rol `bi_reader` con sus límites), no de sus datos.

| Comando | Qué hace | ¿Toca producción? |
|---|---|---|
| `npm run db:reset` | Rehace la base LOCAL: línea base + `seed.sql` | No |
| `npm run db:test` | Corre las pruebas pgTAP de `supabase/tests/` | No |
| `npm run db:diff` | Genera una migración con lo que cambiaste, **acotado a `crm`** | No |
| `npm run db:list` | Compara historial local y remoto | Solo lee |
| `npm run db:pull` | Regenera la línea base desde producción | Solo lee* |

`db:diff` está fijado a `--schema crm` a propósito: es lo que impide
generar una migración que toque `public`. Para nombrarla: `npm run db:diff
-- -f nombre_de_la_migracion`.

**`supabase db push` no tiene atajo, deliberadamente.** Es el comando que
aplica migraciones a producción y no debe salir por memoria muscular.
Escríbelo completo, mirando lo que vas a aplicar. Y jamás
`supabase db reset --linked`: eso borra producción.

\* `db pull` marca además la migración como aplicada en el historial
remoto. No cambia datos ni esquema.

### Cosas que hay que saber de la línea base

- `supabase/migrations/20260910205611_remote_schema.sql` está **generado**.
  No se edita a mano salvo la excepción documentada dentro del propio
  archivo (un `GRANT ... WITH ADMIN OPTION` que no puede aplicarse en local).
- `supabase/seed.sql` **solo corre en local**. Siembra dos inmobiliarias
  ajenas —Alfa y Beta— porque el aislamiento entre inquilinos no se puede
  probar con un solo inquilino. Usuarios: `alfa@prueba.local` y
  `beta@prueba.local`, contraseña `prueba1234`.
- Las políticas están declaradas `TO public`, así que **también se evalúan
  para el rol `anon`**. Lo único que deja fuera a un anónimo es que
  `auth.uid()` sea nulo. Tenlo presente al escribir políticas nuevas.
