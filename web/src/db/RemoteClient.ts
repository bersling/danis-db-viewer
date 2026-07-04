import type { Connection, SchemaInfo, QueryResult } from "./types";

/// Talks to the local proxy (server/index.mjs), which connects to the real
/// Postgres / MySQL / SQLite databases from your connections.json:
/// list connections, introspect, query.
export class RemoteClient {
  async connections(): Promise<Connection[]> {
    const r = await fetch("/api/connections");
    if (!r.ok) throw new Error("proxy not reachable");
    return r.json();
  }

  async introspect(id: string): Promise<SchemaInfo[]> {
    const r = await fetch("/api/introspect", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id }),
    });
    return r.json();
  }

  async query(id: string, sql: string): Promise<QueryResult> {
    const r = await fetch("/api/query", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id, sql }),
    });
    return r.json();
  }
}
