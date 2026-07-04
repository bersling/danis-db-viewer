# Dani's DB Viewer — project guide

Native **macOS SwiftUI/AppKit** app cloning IntelliJ IDEA's Database tool window.
Multiple data sources (SQLite / PostgreSQL / MySQL), schema explorer, editable
data grid with staged changes, SQL consoles. Darcula-styled.

Repo: https://github.com/bersling/danis-db-viewer (public — **never commit secrets**).

## Build / run / test / package

```bash
swift build                      # debug build
swift run                        # or: .build/debug/DanisDBViewer
swift test                       # unit tests (SQLSplitter, DBValue, grid model, diagnostics)
./scripts/make-app.sh            # release build → dist/…app, installs to /Applications, writes ~/.local/bin/ddv
ddv                              # launch the installed app (ddv <file.sqlite> opens a file)
```

- Toolchain: Swift 6 / Xcode 16+, macOS 14+. SwiftPM, **no .xcodeproj**.
- Deps: PostgresNIO, MySQLNIO (SPM). SQLite uses system `libsqlite3` (`import SQLite3`).
- Do **not** install packages on the host (user rule) — use Docker for DB test instances.

## Layout

```
Sources/DanisDBViewer/
  Model/     DataSourceConfig, DBValue, Schema (introspection + QueryResult)
  Drivers/   DatabaseDriver protocol + SQLite/Postgres/MySQL; ConnectionDiagnostics
  SQL/       SQLSplitter, DDLGenerator, Exporter (CSV/JSON/INSERT)
  Services/  ConnectionStore, SessionRegistry, Keychain, QueryHistoryStore, AppServices
  UI/        MainView, ExplorerView, EditorAreaView, TableEditorView, DataGridView,
             ConsoleView, SQLEditor (NSTextView), DataSourceDialog, DDLView, StructureView, Theme
```

- `AppServices.shared` holds the singletons (view-model `StateObject` inits need
  direct access, since they can't read `@EnvironmentObject`).
- Passwords: macOS Keychain, service `com.danis.dbviewer`, account = connection UUID.
  Never in `connections.json` (which holds host/user only, in
  `~/Library/Application Support/DanisDBViewer/`).

## Persisted state (outside the repo)

`~/Library/Application Support/DanisDBViewer/connections.json` + `history.json`;
passwords in Keychain. Deleting these resets the app.

## Testing the GUI

Terminal has **Accessibility permission** (granted 2026-07-04), so real synthetic
**mouse clicks** via System Events work. Synthetic **keystrokes** are flaky
(`-10000 not allowed assistive access`) — clicks are reliable, keystrokes aren't.

Two complementary approaches — see the `ddv-testing` skill for full detail:
1. **Automation env-var hooks** (invoke the same code paths a gesture would):
   `DANIS_DS=<name>`, `DANIS_OPEN_TABLE=<name>`, `DANIS_OPEN_CONSOLE=1`,
   `DANIS_SQL=<script>`, `DANIS_COMPLETE=<partial>`, `DANIS_STRUCTURE=1`,
   `DANIS_WINFRAME=x,y,w,h`.
2. **Real clicks + screenshots**: get row/element screen positions via System
   Events `entire contents`/`position`, `click at {x,y}`, then
   `screencapture -l $(swift scripts/windowid.swift DanisDBViewer)`.

`swift test` is the strongest signal. Postgres/MySQL integration + live-diagnostics
tests are gated on `DANIS_IT_PG=1` / `DANIS_IT_MYSQL=1` with Docker containers
(ports 55432 / 53306, password `secret`) — see README.

## Conventions the user cares about (learned)

- **Single-click** to open/navigate; click-to-select + second-click-or-Enter to
  edit cells. Double-click only as an optional fast path, never required.
- **No hover highlights / cursor changes** — match IntelliJ's flat tool-window look.
- Every icon button needs a real hit target (≥26×24pt) — use `IconButtonStyle`
  (`.buttonStyle(.icon)`), not bare `.borderless` on a glyph.
- When the user questions a UI pattern, **check what IntelliJ actually does** — that's
  the tiebreaker.

## Gotchas

- Two-axis `ScrollView` centers undersized content — pin grids with
  `.frame(minWidth: geo.width, minHeight: geo.height, alignment: .topLeading)`
  and `LazyVStack(alignment: .leading)`.
- Docker Desktop crashes if launched while the screen is locked — ask the user to
  start it; don't grind on relaunching. Avoid reading
  `~/Library/Group Containers/group.com.docker/*` (TCC prompt hangs the shell).
- SwiftUI tree rows currently expose no accessibility labels (only roles) — an
  a11y gap; click tree rows by computed position, not by name.
- Control-click on a tree row currently toggles expand instead of only showing the
  context menu (the `.onTapGesture` eats it) — known bug to fix.

## Utilities

- `scripts/import-intellij.py <.idea dir>` — import IntelliJ data sources (host/port/
  user; no passwords) into connections.json, keyed by IntelliJ UUID.
- `scripts/inject-passwords.sh <map.tsv>` — stream GitLab CI/CD variable values
  straight into the Keychain without printing them. DB passwords live as GitLab
  CI/CD variables in project `taskbase/tb` on `code.taskbase.com`
  (e.g. `LAP_DB_PASSWORD_DEV`).
- `scripts/make-icon.swift <out.icns>` — regenerate the app icon.
