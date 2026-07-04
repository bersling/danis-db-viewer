# Dani's DB Viewer — project guide

Browser clone of IntelliJ IDEA's Database tool window, Darcula-styled.
React + virtualized grid in the browser; a local Node proxy (`web/server/index.mjs`)
connects to the real databases (SQLite / PostgreSQL / MySQL).

Repo: https://github.com/bersling/danis-db-viewer (public — **never commit secrets**).

The original native SwiftUI app was removed in favor of this web version; it
lives in git history (up to tag-less commit `2998ca6` and earlier).

## Build / run / test

```bash
cd web
npm install
npm run build            # tsc + vite build → dist/
npm run serve            # proxy + built app on http://localhost:8787
npm run dev              # Vite dev server on :5173 (proxy must be running for /api)
node test-remote.mjs out.png   # headless-Chromium smoke test against :8787
```

- Node ≥ 22.5 required (`node:sqlite`). Deps: pg, mysql2, react,
  @tanstack/react-virtual, @uiw/react-codemirror, playwright (dev).
- Do **not** install packages globally on the host (user rule); project-scoped
  `npm install` inside `web/` is fine. Use Docker for DB test instances.

## Layout

```
web/
  server/index.mjs    local proxy: /api/connections, /api/introspect, /api/query, /api/test;
                      serves dist/; one cached pool per connection id, dropped on error
  src/
    App.tsx           tabs (table/console), TableView (SELECT builder, dialect-aware quoting)
    components/       Explorer.tsx (tree), DataGrid.tsx (virtualized), Console.tsx (CodeMirror)
    db/               RemoteClient.ts (fetch wrapper), types.ts (shared model)
scripts/              import-intellij.py (IntelliJ → connections.json),
                      inject-passwords.sh (GitLab CI vars → secrets.json, never echoed)
SampleData/           chinook-mini.db (sample SQLite)
```

## Persisted state (outside the repo)

`~/Library/Application Support/DanisDBViewer/`:
- `connections.json` — connection configs (host/port/user, no passwords)
- `secrets.json` — `{uuid: password}`, chmod 600

Read server-side by the proxy on every request; passwords never reach the
browser (`/api/connections` strips them). The browser itself persists nothing —
tabs/tree/results are in-memory React state.

DB passwords live as GitLab CI/CD variables in project `taskbase/tb` on
`code.taskbase.com` (e.g. `LAP_DB_PASSWORD_DEV`) — inject with
`scripts/inject-passwords.sh`; never print a password value.

## Testing

Playwright headless Chromium (`web/test-remote.mjs`) against the proxy on :8787 —
see the `ddv-testing` skill. Postgres/MySQL test instances: Docker containers on
ports 55432 / 53306, password `secret`. Docker Desktop crashes if launched while
the screen is locked — ask the user to start it. Avoid reading
`~/Library/Group Containers/group.com.docker/*` (TCC prompt hangs the shell).

## Conventions the user cares about (learned)

- **Single-click** to select/expand; double-click opens a table. Match what
  IntelliJ actually does — that's the tiebreaker for any UI question.
- **No hover highlights / cursor changes** — IntelliJ's flat tool-window look.
- Generous click targets; no dead gaps between tree rows.

## Gotchas

- **Remote DBs need the VPN.** A 25s `ETIMEDOUT` from the proxy usually means
  VPN down, not a bug. On query error the proxy drops the cached pool
  (`dropDriver`) so the next attempt reconnects; the Explorer re-fetches when an
  errored connection is expanded again or its error row is clicked.
- **`node:sqlite` returns column names only when there are rows** — empty
  SELECTs re-derive them via a `LIMIT 0` wrapper (`columnNamesSqlite`).
- Quote identifiers per dialect: backticks for MySQL, double quotes otherwise
  (`quoteId` in App.tsx); SQLite targets are unqualified (no schema prefix).
- Introspection is batched (3 queries per connection for PG/MySQL), not
  per-schema loops — remote DBs over VPN are latency-bound (AilaDev = 11 schemas).
