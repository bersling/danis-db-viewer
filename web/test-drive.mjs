import { chromium } from "playwright";

const SHOT = process.argv[2] || "/tmp/web.png";
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1300, height: 820 } });
const errors = [];
page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
page.on("pageerror", (e) => errors.push(String(e)));

await page.goto("http://localhost:4173/", { waitUntil: "networkidle" });

// Wait for the demo build to finish.
await page.waitForFunction(() => document.body.innerText.includes("ready · demo"), { timeout: 30000 });
console.log("STATUS:", await page.locator(".titlebar .info").innerText());

// The tree should list the demo tables.
const tableCount = await page.locator(".tree .row").count();
console.log("tree rows:", tableCount);

// Double-click the "events" table (the 100k-row one) to open it.
await page.locator(".tree .row", { hasText: "events" }).first().dblclick();
await page.waitForSelector(".grid-row", { timeout: 10000 });
const rowsText = await page.locator(".statusbar").first().innerText();
console.log("events tab status:", rowsText.replace(/\n/g, " "));

// Measure scroll performance: jump to row ~50,000 and confirm it renders.
await page.evaluate(() => {
  const g = document.querySelector(".grid");
  if (g) g.scrollTop = 1_200_000; // deep scroll into the virtualized list
});
await page.waitForTimeout(300);
const domRows = await page.locator(".grid-row").count();
console.log("DOM rows while showing 100k (virtualized):", domRows);

await page.screenshot({ path: SHOT });
console.log("errors:", errors.length ? errors.slice(0, 5) : "none");
await browser.close();
