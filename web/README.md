# Dani's DB Viewer — Web / WASM

A browser-native clone of the [native macOS app](../README.md), built on the
"vibe-coding" hybrid stack: **SQLite compiled to WebAssembly** for the data
engine + **React with a virtualized grid** for the UI. Everything runs
client-side — no backend, no server round-trips.

## Why this stack

- **WASM does the thinking.** SQLite runs in a Web Worker (`src/db/sqliteWorker.ts`),
  off the main thread, so the UI never blocks. Query a 100k-row table in ~400ms.
- **Virtualized JS does the drawing.** The grid (`@tanstack/react-virtual`) only
  keeps the ~50 visible rows in the DOM, so 100k+ rows scroll at 60fps — the fix
  for the DOM-bloat problem that makes older web tools choke on large datasets.
  (Verified: 100,000 rows loaded, only ~53 row nodes in the DOM.)

## Run

```bash
cd web
npm install
npm run dev        # http://localhost:5173
npm run build      # production bundle in dist/
npm run preview    # serve the built bundle on :4173
```

On launch it generates a demo database in-browser (artists / albums + a
100,000-row `events` table). Use **Open .db…** to load any local SQLite file —
it never leaves your machine.

## What works

- Explorer tree: tables/views → columns (PK/type), single-click select,
  double-click open
- Fully virtualized data grid: sortable headers, `WHERE` filter, 100k+ rows
- SQL console: CodeMirror with SQLite highlighting + schema-aware completion,
  ⌘⏎ to run, virtualized results, timing

## Architecture

```
src/
  db/
    types.ts          shared model (DBTable, QueryResult, …)
    sqliteWorker.ts   SQLite-WASM in a Web Worker (the engine)
    SqliteClient.ts   promise-based client + introspection (the driver)
  components/
    Explorer.tsx      schema tree
    DataGrid.tsx      virtualized grid (@tanstack/react-virtual)
    Console.tsx       SQL editor + results
  App.tsx             tabs, table view, demo seeding
```

`SqliteClient` mirrors the native app's `DatabaseDriver` protocol, so a second
engine (PGlite for Postgres-in-WASM, or DuckDB-WASM) can be added behind the
same interface.

## Same databases as the native app (via a local proxy)

A browser tab can't open raw TCP sockets, so it can't reach Postgres/MySQL
directly. A tiny local Node proxy (`server/index.mjs`) bridges that gap — and it
reads the **same** `connections.json` + `secrets.json` the native app uses, so
all your data sources appear with no re-entry. Passwords stay server-side and are
never sent to the browser.

```bash
npm run build       # build the web app
npm run serve       # proxy serves the app + /api on http://localhost:8787
```

The proxy handles all three engines:
- **SQLite** — Node's built-in `node:sqlite` (opens the file directly)
- **PostgreSQL** — `pg`
- **MySQL** — `mysql2`

For local `.db` files with zero backend, the in-browser SQLite-WASM engine
(`src/db/sqliteWorker.ts`) is still included and can be wired to an upload button.

## Verify

```bash
npm run preview &
node test-drive.mjs out.png     # opens the 100k table, asserts DOM stays virtualized
node test-console.mjs out.png   # runs an aggregate in the console
```
