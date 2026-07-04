// Generate the README screenshots (docs/table.png, docs/console.png) against a
// running proxy: DDV_URL=http://localhost:8787 node shots.mjs ../docs
import { chromium } from "playwright";
const BASE = process.env.DDV_URL || "http://localhost:8788";
const OUT = process.argv[2] || "../docs";
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1360, height: 850 }, deviceScaleFactor: 2 });
await page.goto(BASE + "/", { waitUntil: "networkidle" });
await page.locator(".tree .row", { hasText: "chinook-mini" }).first().click();
await page.waitForTimeout(500);
await page.locator(".tree .row", { hasText: "tracks" }).first().dblclick();
await page.waitForSelector(".grid-row");
await page.screenshot({ path: OUT + "/table.png" });

await page.locator(".titlebar button", { hasText: "New Console" }).click();
await page.locator(".cm-content").click();
await page.keyboard.press("Meta+a");
await page.keyboard.press("Backspace");
await page.keyboard.type("SELECT ar.name AS artist, COUNT(*) AS tracks\nFROM tracks t JOIN albums al ON al.id = t.album_id\nJOIN artists ar ON ar.id = al.artist_id\nGROUP BY ar.name ORDER BY tracks DESC;");
await page.locator("button", { hasText: "Run" }).click();
await page.waitForFunction(() => document.body.innerText.includes("artist"), { timeout: 10000 });
await page.waitForTimeout(300);
await page.screenshot({ path: OUT + "/console.png" });
await browser.close();
console.log("shots written to", OUT);
