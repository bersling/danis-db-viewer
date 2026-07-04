// Local proxy for Dani's DB Viewer. A browser can't open raw TCP, so this
// tiny Node server sits on localhost and proxies queries to Postgres / MySQL /
// SQLite. Connections come from connections.json + secrets.json in
// ~/Library/Application Support/DanisDBViewer/. Passwords stay server-side —
// they are never sent to the browser.
import http from "node:http";
import { readFileSync, existsSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";
import pg from "pg";
import mysql from "mysql2/promise";

const DIR = path.join(os.homedir(), "Library/Application Support/DanisDBViewer");
const DIST = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "dist");
const PORT = Number(process.env.DDV_PORT || 8787);

const loadJSON = (f, fallback) => {
  try { return JSON.parse(readFileSync(path.join(DIR, f), "utf8")); } catch { return fallback; }
};
const connections = () => loadJSON("connections.json", []);
const secrets = () => loadJSON("secrets.json", {});
const configFor = (id) => connections().find((c) => c.id === id);

// One live connection/pool per data-source id.
const live = new Map();
async function driver(id) {
  if (live.has(id)) return live.get(id);
  const cfg = configFor(id);
  if (!cfg) throw new Error("Unknown connection: " + id);
  const password = secrets()[id] || "";
  const port = cfg.port || (cfg.kind === "postgres" ? 5432 : cfg.kind === "mysql" ? 3306 : 0);
  let d;
  if (cfg.kind === "sqlite") {
    const p = cfg.filePath.replace(/^~/, os.homedir());
    const db = new DatabaseSync(p, { readOnly: false });
    d = { kind: "sqlite", db };
  } else if (cfg.kind === "postgres") {
    const pool = new pg.Pool({
      host: cfg.host, port, user: cfg.user, password,
      database: cfg.database || cfg.user, max: 4,
      connectionTimeoutMillis: 25000, ssl: false,
    });
    d = { kind: "postgres", pool };
  } else if (cfg.kind === "mysql") {
    const pool = mysql.createPool({
      host: cfg.host, port, user: cfg.user, password,
      database: cfg.database || undefined, connectionLimit: 4,
      connectTimeout: 25000,
    });
    d = { kind: "mysql", pool };
  } else throw new Error("Unsupported kind: " + cfg.kind);
  live.set(id, d);
  return d;
}

async function runQuery(id, sql) {
  const started = performance.now();
  const d = await driver(id);
  try {
    if (d.kind === "sqlite") {
      const stmt = d.db.prepare(sql);
      if (stmt.reader ?? true) {
        // Try reading columns; if not a SELECT this throws → fall back to run.
        try {
          const rows = stmt.all();
          const columns = rows.length ? Object.keys(rows[0]) : columnNamesSqlite(d.db, sql);
          return {
            columns,
            rows: rows.map((r) => columns.map((c) => r[c])),
            durationMs: performance.now() - started,
          };
        } catch {
          const info = d.db.prepare(sql).run();
          return { columns: [], rows: [], rowsAffected: Number(info.changes), durationMs: performance.now() - started };
        }
      }
    } else if (d.kind === "postgres") {
      const res = await d.pool.query({ text: sql, rowMode: "array" });
      const columns = (res.fields || []).map((f) => f.name);
      if (res.command && ["INSERT", "UPDATE", "DELETE"].includes(res.command) && columns.length === 0) {
        return { columns: [], rows: [], rowsAffected: res.rowCount, durationMs: performance.now() - started };
      }
      return { columns, rows: res.rows, durationMs: performance.now() - started };
    } else if (d.kind === "mysql") {
      const [rows, fields] = await d.pool.query({ sql, rowsAsArray: true });
      if (Array.isArray(fields) && fields.length) {
        return { columns: fields.map((f) => f.name), rows, durationMs: performance.now() - started };
      }
      return { columns: [], rows: [], rowsAffected: rows.affectedRows ?? 0, durationMs: performance.now() - started };
    }
  } catch (e) {
    // Drop the cached pool/handle on error so the next attempt reconnects
    // cleanly (e.g. after a VPN drop/reconnect) instead of reusing a dead one.
    dropDriver(id);
    return { columns: [], rows: [], error: String(e.message || e), durationMs: performance.now() - started };
  }
  return { columns: [], rows: [], durationMs: performance.now() - started };
}

function dropDriver(id) {
  const d = live.get(id);
  if (!d) return;
  live.delete(id);
  try {
    if (d.kind === "sqlite") d.db.close();
    else d.pool.end?.();
  } catch { /* ignore */ }
}

// node:sqlite gives column names via statement only when there are rows; for an
// empty SELECT, re-derive from a LIMIT 0 wrapper.
function columnNamesSqlite(db, sql) {
  try {
    const r = db.prepare(`SELECT * FROM (${sql.replace(/;\s*$/, "")}) LIMIT 0`).all();
    return r.length ? Object.keys(r[0]) : [];
  } catch { return []; }
}

async function introspect(id) {
  const cfg = configFor(id);
  if (cfg.kind === "sqlite") {
    const t = await runQuery(id, "SELECT name, type FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY type, name");
    const tables = [];
    for (const [name, type] of t.rows) {
      const cols = await runQuery(id, `PRAGMA table_info("${name.replace(/"/g, '""')}")`);
      tables.push({
        schema: "main", name, kind: type === "view" ? "view" : "table",
        columns: cols.rows.map((r) => ({ name: r[1], type: r[2] || "", notNull: r[3] === 1, primaryKey: r[5] > 0 })),
      });
    }
    return [{ schema: "main", tables }];
  }
  if (cfg.kind === "postgres") {
    const schemas = await runQuery(id, "SELECT nspname FROM pg_namespace WHERE nspname NOT IN ('pg_catalog','information_schema','pg_toast') ORDER BY nspname");
    const cols = await runQuery(id, "SELECT table_schema, table_name, column_name, data_type, is_nullable FROM information_schema.columns WHERE table_schema NOT IN ('pg_catalog','information_schema') ORDER BY table_schema, table_name, ordinal_position");
    const tbls = await runQuery(id, "SELECT table_schema, table_name, table_type FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema') ORDER BY table_name");
    return groupSchemas(schemas.rows.map((r) => r[0]), tbls.rows, cols.rows);
  }
  if (cfg.kind === "mysql") {
    const schemas = await runQuery(id, "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('mysql','information_schema','performance_schema','sys') ORDER BY schema_name");
    const cols = await runQuery(id, "SELECT table_schema, table_name, column_name, column_type, is_nullable FROM information_schema.columns WHERE table_schema NOT IN ('mysql','information_schema','performance_schema','sys') ORDER BY table_schema, table_name, ordinal_position");
    const tbls = await runQuery(id, "SELECT table_schema, table_name, table_type FROM information_schema.tables WHERE table_schema NOT IN ('mysql','information_schema','performance_schema','sys') ORDER BY table_name");
    return groupSchemas(schemas.rows.map((r) => r[0]), tbls.rows, cols.rows);
  }
  return [];
}

function groupSchemas(schemaNames, tableRows, colRows) {
  const colsByTable = new Map();
  for (const [s, t, name, type, nullable] of colRows) {
    const k = s + "\t" + t;
    if (!colsByTable.has(k)) colsByTable.set(k, []);
    colsByTable.get(k).push({ name, type: type || "", notNull: String(nullable).toUpperCase() === "NO", primaryKey: false });
  }
  const tablesBySchema = new Map();
  for (const [s, name, type] of tableRows) {
    if (!tablesBySchema.has(s)) tablesBySchema.set(s, []);
    tablesBySchema.get(s).push({ schema: s, name, kind: /view/i.test(type) ? "view" : "table", columns: colsByTable.get(s + "\t" + name) || [] });
  }
  return schemaNames.map((s) => ({ schema: s, tables: tablesBySchema.get(s) || [] }));
}

// --- HTTP ---
const MIME = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".wasm": "application/wasm", ".json": "application/json", ".svg": "image/svg+xml" };

function sendJSON(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "Content-Type", "Access-Control-Allow-Methods": "GET,POST,OPTIONS" });
  res.end(body);
}
function readBody(req) {
  return new Promise((resolve) => { let b = ""; req.on("data", (c) => (b += c)); req.on("end", () => resolve(b ? JSON.parse(b) : {})); });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://x");
  if (req.method === "OPTIONS") return sendJSON(res, 204, {});
  try {
    if (url.pathname === "/api/connections") {
      // Never include passwords.
      return sendJSON(res, 200, connections().map(({ id, name, kind, host, port, user, database, color }) => ({ id, name, kind, host, port, user, database, color })));
    }
    if (url.pathname === "/api/introspect" && req.method === "POST") {
      const { id } = await readBody(req);
      return sendJSON(res, 200, await introspect(id));
    }
    if (url.pathname === "/api/query" && req.method === "POST") {
      const { id, sql } = await readBody(req);
      return sendJSON(res, 200, await runQuery(id, sql));
    }
    if (url.pathname === "/api/test" && req.method === "POST") {
      const { id } = await readBody(req);
      const r = await runQuery(id, "SELECT 1");
      return sendJSON(res, 200, { ok: !r.error, error: r.error });
    }
  } catch (e) {
    return sendJSON(res, 500, { error: String(e.message || e) });
  }
  // static (built app)
  serveStatic(url.pathname, res);
});

function serveStatic(pathname, res) {
  let p = path.join(DIST, pathname === "/" ? "index.html" : pathname);
  if (!existsSync(p)) p = path.join(DIST, "index.html");
  try {
    const data = readFileSync(p);
    res.writeHead(200, { "Content-Type": MIME[path.extname(p)] || "application/octet-stream" });
    res.end(data);
  } catch {
    res.writeHead(404); res.end("not found");
  }
}

server.listen(PORT, () => console.log(`Dani's DB Viewer proxy on http://localhost:${PORT}`));
