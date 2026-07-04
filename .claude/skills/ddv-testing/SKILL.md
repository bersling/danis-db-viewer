---
name: ddv-testing
description: Drive and verify Dani's DB Viewer (native macOS SwiftUI DB app). Use when building, testing, screenshotting, or click-driving this app — covers env-var automation hooks, real synthetic clicks via System Events, window-only screenshots, and the gated Postgres/MySQL integration tests.
---

# Testing Dani's DB Viewer

Two ways to exercise the app; combine them. `swift test` is the strongest signal.

## 1. Automation env-var hooks (code-path level)

These invoke the exact code a real gesture triggers. Set on launch:

| Var | Effect |
|-----|--------|
| `DANIS_DS=<name>` | target this connection (else first) |
| `DANIS_OPEN_TABLE=<name>` | open that table in the grid |
| `DANIS_OPEN_CONSOLE=1` | open a query console |
| `DANIS_SQL=<script>` | seed the console and run it |
| `DANIS_COMPLETE=<partial>` | focus editor, set partial word, force the completion popup |
| `DANIS_STRUCTURE=1` | open table in Structure view |
| `DANIS_WINFRAME=x,y,w,h` | position/size the window (predictable screenshots) |

Example:
```bash
pkill -f DanisDBViewer; sleep 1
DANIS_DS=chinook-mini DANIS_OPEN_TABLE=tracks DANIS_WINFRAME=40,60,1240,820 \
  .build/debug/DanisDBViewer >/dev/null 2>&1 &
sleep 4
```
Hooks live in `Sources/DanisDBViewer/UI/App.swift` (`runAutomationHooks`),
`ConsoleView.swift` (`DANIS_SQL`), `SQLEditor.swift` (`DANIS_COMPLETE`),
`TableEditorView.swift` (`DANIS_STRUCTURE`).

## 2. Window-only screenshots

```bash
WID=$(swift scripts/windowid.swift DanisDBViewer)   # CGWindowID of frontmost window
screencapture -x -l"$WID" out.png
```
`scripts/windowid.swift` prints the layer-0 window id for an app by name. Use the
bundle display name `"Dani's DB Viewer"` for the installed .app, `DanisDBViewer`
for `swift run`/debug builds.

## 3. Real synthetic clicks (Terminal has Accessibility permission)

Clicks are **reliable**; synthetic keystrokes are **flaky** (`-10000 not allowed
assistive access`). Prefer clicks + hooks over keystrokes.

Get element screen positions (points), then click:
```bash
osascript -e 'tell application "System Events" to tell process "DanisDBViewer" to get {position, size} of window 1'
# enumerate rows: iterate `entire contents of window 1`, filter role "AXRow", read `position`
osascript -e 'tell application "System Events" to click at {250, 478}'   # screen points
```
Tree rows have **no accessibility labels** (SwiftUI gap) — identify them by order
(connections are sorted alphabetically) and computed Y (first row ~y=334, 32pt apart).
Coordinate math off a retina+shadow screenshot is unreliable; use AX `position` instead.

To type into the SQL editor, find its rect:
```bash
# iterate entire contents, role "AXTextArea" → position/size; click its center, then keystroke
```
If `keystroke` returns "not allowed assistive access", fall back to `DANIS_SQL` /
`DANIS_COMPLETE`, or ask the user to type (they're at the machine).

## 4. Real tests

```bash
swift test                                        # unit
DANIS_IT_PG=1 DANIS_IT_MYSQL=1 swift test         # + live driver + diagnostics
```
Containers (from README): postgres:16 on 55432, mysql:8.4 on 53306, password `secret`.
Docker Desktop must be started by the user (it crashes if launched while locked).

## Honesty rule

Distinguish "real-test verified" (swift test, real click observed in a screenshot)
from "code-path verified" (hook-triggered). Say which when reporting.
