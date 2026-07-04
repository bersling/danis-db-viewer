# Dani's DB Viewer

A browser clone of IntelliJ IDEA's **Database** tool window, Darcula-styled.
React + a virtualized data grid in the browser, with a tiny local Node proxy
that connects to the real databases. Multiple data sources (SQLite /
PostgreSQL / MySQL), lazy schema explorer, 100k-row grids at 60fps, SQL
consoles with schema-aware completion.

![table editor](docs/table.png)

![sql console](docs/console.png)

## How it works

A browser tab can't open raw TCP sockets, so a small local proxy
(`web/server/index.mjs`) bridges the gap:

```
browser (React, virtualized grid)  ──HTTP──  localhost proxy  ──TCP──  Postgres / MySQL
                                                    └──────── node:sqlite ── .db files
```

- **SQLite** — Node's built-in `node:sqlite` (opens the file directly)
- **PostgreSQL** — [`pg`](https://www.npmjs.com/package/pg)
- **MySQL / MariaDB** — [`mysql2`](https://www.npmjs.com/package/mysql2)

The grid (`@tanstack/react-virtual`) keeps only the ~50 visible rows in the
DOM, so 100k+ row result sets scroll smoothly.

## Run

```bash
cd web
npm install
npm run build       # build the app into dist/
npm run serve       # proxy serves the app + /api on http://localhost:8787
```

For development with hot reload, run the proxy and Vite side by side:

```bash
npm run serve       # proxy on :8787
npm run dev         # UI on :5173, /api proxied to :8787
```

## Connections & passwords

Connection definitions live in
`~/Library/Application Support/DanisDBViewer/connections.json`; passwords in
`secrets.json` next to it (`{"<connection-uuid>": "<password>"}`, `chmod 600`).
Both are read server-side by the proxy — **passwords are never sent to the
browser**, and neither file is ever committed (this is a public repo).

- `scripts/import-intellij.py <path-to-.idea>` — import IntelliJ data sources
  (host/port/user; no passwords) into `connections.json`.
- `scripts/inject-passwords.sh <map.tsv>` — write passwords into `secrets.json`
  without echoing them anywhere.

A sample SQLite database is included at `SampleData/chinook-mini.db` — point a
`sqlite` connection's `filePath` at it to try the app with zero setup.

## Features

- **Explorer tree**: connections → schemas → tables/views, lazily introspected
  on expand; per-source color stripes; search filter; failed connections show
  the error inline and retry on click.
- **Table view**: virtualized grid, header-click sorting (asc → desc → none),
  raw `WHERE` filter, row count + query timing in the status bar.
- **SQL console**: CodeMirror with dialect-aware highlighting
  (SQLite/PostgreSQL/MySQL) and schema-aware completion, ⌘⏎ to run,
  virtualized results.

## Verify

```bash
cd web
npm run build && npm run serve &
node test-remote.mjs out.png    # headless Chromium: expands a connection, opens a table, screenshots
```
