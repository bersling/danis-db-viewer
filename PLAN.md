# Dani's DB Viewer — IntelliJ Database Tool Clone

A **native macOS app** (SwiftUI + AppKit) cloning IntelliJ IDEA's Database tool
window, styled after Darcula.

## Feature inventory (what IntelliJ's database tool does)

### 1. Data sources (connections)
- [x] Add data sources for multiple DBMS: SQLite, PostgreSQL, MySQL/MariaDB
- [x] Connection config: host, port, user, password, database, or file path (SQLite)
- [x] Test Connection button with success/failure feedback
- [x] Edit, duplicate, remove data sources
- [x] Per-data-source color coding (shown in tree + editor tabs)
- [x] Multiple simultaneous connections
- [x] Connections persisted across restarts (JSON store)
- [ ] SSH tunnel / SSL options (out of scope for v1)

### 2. Database explorer (tree)
- [x] Tree: data source → schemas/databases → tables / views → columns, indexes, keys
- [x] Column nodes show type, PK / FK / NOT NULL markers
- [x] Index and foreign-key child nodes
- [x] Lazy introspection + explicit Refresh action
- [x] Speed search / filter box over the tree
- [x] Context menu: open table, open console, copy name, drop table, refresh, DDL
- [x] Node icons per object type, data source color stripe

### 3. Table data editor (grid)
- [x] Open any table/view in a paginated grid (default 100 rows/page)
- [x] Page size selector, first/prev/next/last paging, total row count
- [x] Sort by column (click header: asc → desc → none), multi-page aware
- [x] Filter row via WHERE clause input (like IntelliJ's filter field)
- [x] Inline cell editing (double-click), typed NULL support
- [x] Add row / delete selected rows
- [x] Pending changes model: edits are staged (colored), then Submit or Revert
- [x] View value of a cell (long text) in a value pane
- [x] Transpose view for wide rows
- [x] Export: CSV, JSON, SQL INSERTs (page or full result)

### 4. SQL console
- [x] Open per-data-source query consoles (multiple tabs)
- [x] CodeMirror editor: SQL syntax highlighting, schema-aware autocomplete
      (table + column names), keyword completion
- [x] Execute: run whole script, run selection, run statement at caret (Cmd/Ctrl+Enter)
- [x] Multiple statements → multiple result tabs
- [x] Result grids reuse the data grid (sortable, exportable)
- [x] Affected-row counts for DML, error messages inline, execution time
- [x] Query history (persisted, searchable, click to re-insert)
- [ ] Explain plan visualization (out of scope for v1)

### 5. Object details / DDL
- [x] "Go to DDL" — generated CREATE statement for tables/views
- [x] Columns / Indexes / Foreign keys detail tabs when a table is open
- [x] Drop table with confirmation

### 6. UX chrome
- [x] IntelliJ-like layout: tool-window tree left, editor tabs right, status bar
- [x] Darcula color scheme, compact density
- [x] Tab management: open/close/middle-click close, dirty markers on unsent edits
- [x] Keyboard: Cmd/Ctrl+Enter execute, Cmd/Ctrl+F4 close tab, F5 refresh

## Architecture

Native macOS app, SwiftPM executable target (`swift run` / packaged .app).

- **UI**: SwiftUI (NavigationSplitView, Table with dynamic columns) + AppKit
  where SwiftUI falls short (NSTextView-based SQL editor with highlighting +
  completion). Darcula-inspired dark theme.
- **Drivers** (protocol `DatabaseDriver`, async/await):
  - SQLite — system `libsqlite3` (`import SQLite3`, ships with macOS)
  - PostgreSQL — `PostgresNIO` (SPM)
  - MySQL/MariaDB — `MySQLNIO` (SPM)
- **Persistence**: connections + query history as JSON under
  `~/Library/Application Support/DanisDBViewer/`; passwords in the macOS Keychain.
- **Core layers**: Model (configs, schema, values, result sets) · SQL utilities
  (statement splitting, identifier quoting, WHERE/ORDER building, DDL generation,
  CSV/JSON/INSERT export) · Services (connection store, live-session registry,
  history) · UI (explorer tree, editor tabs, data grid, console).

## Build phases
1. Scaffold, plan, git
2. Package.swift + minimal app boots; model types
3. SQLite driver: introspect / query / table-data / mutations / DDL
4. UI shell: explorer tree, data source dialog, editor tabs, Darcula styling
5. Data grid: paging/sorting/filter/editing/pending changes
6. SQL console: highlighting editor, run statement/selection, multi-result, history
7. Postgres + MySQL drivers (verified against Docker containers)
8. Export, DDL view, transpose, polish, sample DB, .app packaging, README
