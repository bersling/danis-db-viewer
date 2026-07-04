import { chromium } from "playwright";
const SHOT = process.argv[2] || "/tmp/web-console.png";
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1300, height: 820 } });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
await page.goto("http://localhost:4173/", { waitUntil: "networkidle" });
await page.waitForFunction(() => document.body.innerText.includes("ready · demo"), { timeout: 30000 });

await page.locator(".titlebar button", { hasText: "New Console" }).click();
await page.waitForSelector(".cm-content");
// Replace the query with an aggregate over the 100k rows.
await page.locator(".cm-content").click();
await page.keyboard.press("Meta+A");
await page.keyboard.type("SELECT event_type, COUNT(*) AS n, ROUND(AVG(amount),2) AS avg_amount FROM events GROUP BY event_type ORDER BY n DESC;");
await page.locator(".toolbar button", { hasText: "Run" }).click();
await page.waitForSelector(".results .grid-row", { timeout: 10000 });
const status = await page.locator(".results .statusbar").innerText();
console.log("console result:", status.replace(/\n/g, " "));
await page.screenshot({ path: SHOT });
console.log("errors:", errors.length ? errors.slice(0, 5) : "none");
await browser.close();
