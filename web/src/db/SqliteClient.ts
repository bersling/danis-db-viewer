import type { DBTable, DBColumn, DBIndex, DBForeignKey, QueryResult, DBValue } from "./types";

/// Promise-based client for the SQLite Web Worker. Mirrors the native app's
/// DatabaseDriver: introspect / execute / table data / export.
export class SqliteClient {
  private worker: Worker;
  private seq = 0;
  private pending = new Map<number, { resolve: (v: any) => void; reject: (e: any) => void }>();

  constructor() {
    this.worker = new Worker(new URL("./sqliteWorker.ts", import.meta.url), { type: "module" });
    this.worker.onmessage = (e) => {
      const { id, ok, error } = e.data;
      const p = this.pending.get(id);
      if (!p) return;
      this.pending.delete(id);
      if (ok) p.resolve(e.data);
      else p.reject(new Error(error));
    };
  }

  private send(msg: any, transfer?: Transferable[]): Promise<any> {
    const id = ++this.seq;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.worker.postMessage({ ...msg, id }, transfer ?? []);
    });
  }

  openBytes(bytes: ArrayBuffer) {
    return this.send({ type: "openBytes", bytes }, [bytes]);
  }
  openEmpty() {
    return this.send({ type: "openEmpty" });
  }

  async exec(sql: string, bind?: unknown[]): Promise<QueryResult> {
    try {
      const r = await this.send({ type: "exec", sql, bind });
      return { columns: r.columns, rows: r.rows as DBValue[][], rowsAffected: r.rowsAffected, durationMs: r.durationMs };
    } catch (e: any) {
      return { columns: [], rows: [], error: String(e.message ?? e), durationMs: 0 };
    }
  }

  async export(): Promise<Uint8Array> {
    const r = await this.send({ type: "export" });
    return r.bytes as Uint8Array;
  }

  /// Full structural introspection via PRAGMA + sqlite_master.
  async introspect(): Promise<DBTable[]> {
    const master = await this.exec(
      "SELECT name, type FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY type, name"
    );
    const tables: DBTable[] = [];
    for (const [name, type] of master.rows as [string, string][]) {
      const columns = await this.columnsOf(name);
      const indexes = type === "table" ? await this.indexesOf(name) : [];
      const foreignKeys = type === "table" ? await this.foreignKeysOf(name) : [];
      tables.push({ name, kind: type === "view" ? "view" : "table", columns, indexes, foreignKeys });
    }
    return tables;
  }

  private async columnsOf(table: string): Promise<DBColumn[]> {
    const r = await this.exec(`PRAGMA table_info("${table.replace(/"/g, '""')}")`);
    // cid, name, type, notnull, dflt_value, pk
    return r.rows.map((row) => {
      const typeName = String(row[2] ?? "");
      const pk = Number(row[5] ?? 0) > 0;
      return {
        name: String(row[1]),
        type: typeName,
        notNull: Number(row[3] ?? 0) === 1,
        primaryKey: pk,
        autoIncrement: pk && typeName.toUpperCase() === "INTEGER",
      };
    });
  }

  private async indexesOf(table: string): Promise<DBIndex[]> {
    const list = await this.exec(`PRAGMA index_list("${table.replace(/"/g, '""')}")`);
    const out: DBIndex[] = [];
    for (const row of list.rows) {
      const idxName = String(row[1]);
      const unique = Number(row[2] ?? 0) === 1;
      const info = await this.exec(`PRAGMA index_info("${idxName.replace(/"/g, '""')}")`);
      out.push({ name: idxName, unique, columns: info.rows.map((r) => String(r[2])) });
    }
    return out;
  }

  private async foreignKeysOf(table: string): Promise<DBForeignKey[]> {
    const r = await this.exec(`PRAGMA foreign_key_list("${table.replace(/"/g, '""')}")`);
    // id, seq, table, from, to, ...
    const grouped = new Map<number, DBForeignKey>();
    for (const row of r.rows) {
      const fkId = Number(row[0]);
      const g = grouped.get(fkId) ?? { columns: [], refTable: String(row[2]), refColumns: [] };
      g.columns.push(String(row[3]));
      g.refColumns.push(String(row[4] ?? row[3]));
      grouped.set(fkId, g);
    }
    return [...grouped.values()];
  }

  async ddl(table: string): Promise<string> {
    const r = await this.exec(
      `SELECT sql FROM sqlite_master WHERE tbl_name = ? AND sql IS NOT NULL ORDER BY (type='table') DESC`,
      [table]
    );
    return r.rows.map((row) => String(row[0]) + ";").join("\n\n");
  }
}
