/// SQLite compiled to WebAssembly, running in a Web Worker — the "thinking"
/// layer. The UI thread stays free so the virtualized grid scrolls at 60fps
/// even while queries run. Communicates via a tiny request/response protocol.
import sqlite3InitModule from "@sqlite.org/sqlite-wasm";

type Req =
  | { id: number; type: "openBytes"; bytes: ArrayBuffer }
  | { id: number; type: "openEmpty" }
  | { id: number; type: "exec"; sql: string; bind?: unknown[] }
  | { id: number; type: "export" };

let sqlite3: any = null;
let db: any = null;

async function ensureInit() {
  if (!sqlite3) {
    sqlite3 = await sqlite3InitModule({
      print: () => {},
      printErr: () => {},
    });
  }
}

function openFromBytes(bytes: ArrayBuffer) {
  db?.close();
  db = new sqlite3.oo1.DB();
  const arr = new Uint8Array(bytes);
  const p = sqlite3.wasm.allocFromTypedArray(arr);
  const rc = sqlite3.capi.sqlite3_deserialize(
    db.pointer,
    "main",
    p,
    arr.byteLength,
    arr.byteLength,
    sqlite3.capi.SQLITE_DESERIALIZE_FREEONCLOSE |
      sqlite3.capi.SQLITE_DESERIALIZE_RESIZEABLE
  );
  if (rc) throw new Error("sqlite3_deserialize failed: " + rc);
}

function exec(sql: string, bind?: unknown[]) {
  const columns: string[] = [];
  const rows: unknown[][] = [];
  db.exec({
    sql,
    bind,
    rowMode: "array",
    columnNames: columns,
    resultRows: rows,
  });
  const rowsAffected = db.changes(false);
  return { columns, rows, rowsAffected };
}

self.onmessage = async (e: MessageEvent<Req>) => {
  const req = e.data;
  const started = performance.now();
  try {
    await ensureInit();
    switch (req.type) {
      case "openBytes":
        openFromBytes(req.bytes);
        (self as any).postMessage({ id: req.id, ok: true });
        break;
      case "openEmpty":
        db?.close();
        db = new sqlite3.oo1.DB();
        (self as any).postMessage({ id: req.id, ok: true });
        break;
      case "exec": {
        const r = exec(req.sql, req.bind);
        (self as any).postMessage({
          id: req.id,
          ok: true,
          ...r,
          durationMs: performance.now() - started,
        });
        break;
      }
      case "export": {
        const bytes = sqlite3.capi.sqlite3_js_db_export(db.pointer);
        (self as any).postMessage({ id: req.id, ok: true, bytes }, [bytes.buffer]);
        break;
      }
    }
  } catch (err: any) {
    (self as any).postMessage({
      id: req.id,
      ok: false,
      error: String(err?.message ?? err),
      durationMs: performance.now() - started,
    });
  }
};
