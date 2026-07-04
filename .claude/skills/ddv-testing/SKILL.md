---
name: ddv-testing
description: Drive and verify Dani's DB Viewer (React web app + local Node proxy). Use when building, testing, or screenshotting this app — covers the build/serve loop, headless-Chromium (Playwright) verification, and the Dockerized Postgres/MySQL test instances.
---

# Testing Dani's DB Viewer

## Build + serve

```bash
cd web
npm run build                      # tsc -b && vite build → catches type errors
node server/index.mjs &            # proxy + static app on http://localhost:8787
```

`npm run build` is the strongest cheap signal (full type-check). The proxy reads
`~/Library/Application Support/DanisDBViewer/{connections.json,secrets.json}`
live on every request — no restart needed after editing connections.

## Headless verification (Playwright, already in devDependencies)

```bash
node test-remote.mjs /tmp/shot.png   # expands chinook-mini, opens a table, screenshots
```

Pattern for ad-hoc checks — drive by CSS class, capture pageerrors:

```js
import { chromium } from "playwright";
const page = await (await chromium.launch()).newPage({ viewport: { width: 1300, height: 820 } });
page.on("pageerror", e => console.log("PAGEERROR", e));
await page.goto("http://localhost:8787/", { waitUntil: "networkidle" });
await page.locator(".tree .row", { hasText: "chinook-mini" }).first().click();  // expand
await page.locator(".tree .row", { hasText: "tracks" }).first().dblclick();     // open table
await page.waitForSelector(".grid-row");
await page.screenshot({ path: "/tmp/shot.png" });
```

Useful selectors: `.tree .row`, `.tab`, `.grid-row`, `.statusbar`, `.titlebar .info`,
`.error-banner`, `.cm-content` (console editor).

Virtualization assertion: a 100k-row table must keep only ~50 `.grid-row` nodes
in the DOM.

## API-level checks (skip the browser)

```bash
curl -s localhost:8787/api/connections | python3 -m json.tool
curl -s -X POST localhost:8787/api/test -d '{"id":"<uuid>"}'
curl -s -X POST localhost:8787/api/query -d '{"id":"<uuid>","sql":"SELECT 1"}'
```

## DB test instances

Docker: `postgres:16` on **55432**, `mysql:8.4` on **53306**, password `secret`.
Docker Desktop must be started by the user (it crashes if launched while the
screen is locked). Remote (Taskbase) DBs need the VPN — a 25s ETIMEDOUT means
VPN down, not a bug; expanding the errored connection again retries.

## Honesty rule

Distinguish "real-test verified" (Playwright run, screenshot inspected, curl
output) from "it compiles" (`npm run build`). Say which when reporting.
