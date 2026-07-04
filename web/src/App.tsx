import { useEffect, useMemo, useRef, useState, useCallback } from "react";
import { RemoteClient } from "./db/RemoteClient";
import type { Connection, SchemaInfo, SchemaTable, QueryResult, DBValue } from "./db/types";
import { Explorer } from "./components/Explorer";
import { DataGrid } from "./components/DataGrid";
import { Console } from "./components/Console";

interface TableTab { id: string; kind: "table"; connId: string; schema: string; table: SchemaTable; connKind: Connection["kind"]; }
interface ConsoleTab { id: string; kind: "console"; connId: string; connKind: Connection["kind"]; connName: string; }
type Tab = TableTab | ConsoleTab;

type SchemaState = SchemaInfo[] | "loading" | { error: string } | undefined;

export function App() {
  const client = useRef(new RemoteClient());
  const [connections, setConnections] = useState<Connection[]>([]);
  const [schemas, setSchemas] = useState<Record<string, SchemaState>>({});
  const [selected, setSelected] = useState<string | null>(null);
  const [tabs, setTabs] = useState<Tab[]>([]);
  const [activeTab, setActiveTab] = useState<string | null>(null);
  const [status, setStatus] = useState("connecting to proxy…");

  useEffect(() => {
    client.current.connections()
      .then((c) => { setConnections(c); setStatus(`${c.length} connections`); })
      .catch(() => setStatus("proxy not running — start it with: node server/index.mjs"));
  }, []);

  const expandConnection = useCallback((id: string) => {
    setSchemas((s) => ({ ...s, [id]: "loading" }));
    client.current.introspect(id)
      .then((info) => setSchemas((s) => ({ ...s, [id]: info })))
      .catch((e) => setSchemas((s) => ({ ...s, [id]: { error: String(e.message || e) } })));
  }, []);

  const openTable = useCallback((connId: string, schema: string, table: SchemaTable) => {
    const conn = connections.find((c) => c.id === connId)!;
    const id = `t:${connId}/${schema}.${table.name}`;
    setSelected(`${connId}/${schema}.${table.name}`);
    setTabs((t) => (t.some((x) => x.id === id) ? t : [...t, { id, kind: "table", connId, schema, table, connKind: conn.kind }]));
    setActiveTab(id);
  }, [connections]);

  const openConsole = useCallback(() => {
    const connId = selected?.split("/")[0] ?? connections[0]?.id;
    if (!connId) return;
    const conn = connections.find((c) => c.id === connId)!;
    const id = `c:${connId}:${Date.now()}`;
    setTabs((t) => [...t, { id, kind: "console", connId, connKind: conn.kind, connName: conn.name }]);
    setActiveTab(id);
  }, [selected, connections]);

  const closeTab = (id: string) =>
    setTabs((t) => {
      const next = t.filter((x) => x.id !== id);
      if (activeTab === id) setActiveTab(next.length ? next[next.length - 1].id : null);
      return next;
    });

  return (
    <div className="app">
      <div className="titlebar">
        <span className="title">Dani's DB Viewer <span style={{ color: "var(--dim)", fontWeight: 400 }}>· Web / WASM</span></span>
        <button onClick={openConsole} disabled={!connections.length}>New Console</button>
        <span className="spacer" />
        <span className="info" style={{ color: "var(--dim)", fontSize: 11 }}>{status}</span>
      </div>
      <div className="main">
        <Explorer
          connections={connections}
          schemas={schemas}
          selected={selected}
          onExpandConnection={expandConnection}
          onSelectTable={setSelected}
          onOpenTable={openTable}
        />
        <div className="content">
          {tabs.length === 0 ? (
            <div className="empty">
              <div style={{ fontSize: 40, opacity: 0.4 }}>🗄</div>
              <div>Double-click a table, or open a query console</div>
              <div style={{ fontSize: 12 }}>Same SQLite / PostgreSQL / MySQL connections as the native app, via a local proxy.</div>
            </div>
          ) : (
            <>
              <div className="tabbar">
                {tabs.map((t) => (
                  <div key={t.id} className={"tab" + (t.id === activeTab ? " active" : "")} onClick={() => setActiveTab(t.id)}>
                    <span>{t.kind === "table" ? "▦ " + t.table.name : "⌘ " + t.connName}</span>
                    <button className="close" onClick={(e) => { e.stopPropagation(); closeTab(t.id); }}>✕</button>
                  </div>
                ))}
              </div>
              {tabs.map((t) => (
                <div key={t.id} style={{ display: t.id === activeTab ? "flex" : "none", flex: 1, flexDirection: "column", minHeight: 0 }}>
                  {t.kind === "table" ? (
                    <TableView client={client.current} tab={t} />
                  ) : (
                    <Console
                      queryFn={(sql) => client.current.query(t.connId, sql)}
                      schema={schemaMap(schemas[t.connId])}
                      dialect={t.connKind}
                    />
                  )}
                </div>
              ))}
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function schemaMap(state: SchemaState): Record<string, string[]> {
  const m: Record<string, string[]> = {};
  if (Array.isArray(state)) for (const s of state) for (const t of s.tables) m[t.name] = t.columns.map((c) => c.name);
  return m;
}

function quoteId(kind: Connection["kind"], name: string) {
  if (kind === "mysql") return "`" + name.replace(/`/g, "``") + "`";
  return '"' + name.replace(/"/g, '""') + '"';
}

function TableView({ client, tab }: { client: RemoteClient; tab: TableTab }) {
  const [result, setResult] = useState<QueryResult | null>(null);
  const [sortCol, setSortCol] = useState<number | undefined>();
  const [sortDesc, setSortDesc] = useState(false);
  const [where, setWhere] = useState("");
  const [whereDraft, setWhereDraft] = useState("");

  const target = useMemo(() => {
    const q = (n: string) => quoteId(tab.connKind, n);
    return tab.connKind === "sqlite" ? q(tab.table.name) : `${q(tab.schema)}.${q(tab.table.name)}`;
  }, [tab]);

  const load = useCallback(async () => {
    let sql = `SELECT * FROM ${target}`;
    if (where.trim()) sql += ` WHERE ${where}`;
    if (sortCol != null && result) sql += ` ORDER BY ${quoteId(tab.connKind, result.columns[sortCol])} ${sortDesc ? "DESC" : "ASC"}`;
    sql += " LIMIT 100000";
    setResult(await client.query(tab.connId, sql));
  }, [target, where, sortCol, sortDesc]); // eslint-disable-line

  useEffect(() => { load(); }, [target, where, sortCol, sortDesc]); // eslint-disable-line

  return (
    <>
      <div className="toolbar">
        <span className="info">{tab.schema}.{tab.table.name}</span>
        <span style={{ color: "var(--dim)", fontFamily: "var(--mono)", fontSize: 11 }}>WHERE</span>
        <input
          value={whereDraft}
          onChange={(e) => setWhereDraft(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") setWhere(whereDraft); }}
          placeholder="filter condition"
          style={{ flex: 1, background: "var(--bg-editor)", border: "1px solid var(--border)", borderRadius: 6, color: "var(--text)", padding: "3px 8px", fontFamily: "var(--mono)", fontSize: 12, outline: "none" }}
        />
        <button onClick={load}>Reload</button>
      </div>
      {result?.error ? (
        <div className="error-banner">✕ {result.error}</div>
      ) : (
        <DataGrid
          columns={result?.columns ?? tab.table.columns.map((c) => c.name)}
          columnTypes={tab.table.columns.map((c) => c.type)}
          rows={(result?.rows as DBValue[][]) ?? []}
          sortColumn={sortCol}
          sortDesc={sortDesc}
          onSort={(c) => { if (sortCol === c) { if (sortDesc) { setSortCol(undefined); setSortDesc(false); } else setSortDesc(true); } else { setSortCol(c); setSortDesc(false); } }}
        />
      )}
      <div className="statusbar">
        <span>{result?.rows.length ?? 0} rows{where ? " (filtered)" : ""}</span>
        <span style={{ flex: 1 }} />
        <span>{result ? result.durationMs.toFixed(0) + " ms" : ""}</span>
      </div>
    </>
  );
}
