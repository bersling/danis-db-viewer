import { useEffect, useMemo, useRef, useState, useCallback } from "react";
import { SqliteClient } from "./db/SqliteClient";
import type { DBTable, DBValue, QueryResult } from "./db/types";
import { Explorer } from "./components/Explorer";
import { DataGrid } from "./components/DataGrid";
import { Console } from "./components/Console";

interface TableTab { id: string; kind: "table"; name: string; }
interface ConsoleTab { id: string; kind: "console"; }
type Tab = TableTab | ConsoleTab;

const DEMO_SQL = `
CREATE TABLE artists (id INTEGER PRIMARY KEY, name TEXT NOT NULL, country TEXT, formed_year INTEGER);
CREATE TABLE albums (id INTEGER PRIMARY KEY, artist_id INTEGER NOT NULL REFERENCES artists(id), title TEXT NOT NULL, released DATE, rating REAL);
CREATE INDEX idx_albums_artist ON albums(artist_id);
INSERT INTO artists (name, country, formed_year) VALUES
 ('Radiohead','UK',1985),('Daft Punk','France',1993),('Miles Davis','USA',1944),
 ('Portishead','UK',1991),('Björk','Iceland',1977);
INSERT INTO albums (artist_id, title, released, rating) VALUES
 (1,'OK Computer','1997-05-21',4.9),(1,'Kid A','2000-10-02',4.7),
 (2,'Discovery','2001-03-12',4.8),(3,'Kind of Blue','1959-08-17',5.0),
 (4,'Dummy','1994-08-22',4.6),(5,'Homogenic','1997-09-20',4.4);
-- 100k-row table to demonstrate that the virtualized grid stays at 60fps.
CREATE TABLE events AS
WITH RECURSIVE c(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM c WHERE n < 100000)
SELECT n AS id,
       'user_' || (abs(random()) % 5000) AS user_id,
       CASE abs(random()) % 5 WHEN 0 THEN 'login' WHEN 1 THEN 'click' WHEN 2 THEN 'purchase' WHEN 3 THEN 'logout' ELSE 'view' END AS event_type,
       abs(random()) % 100000 / 100.0 AS amount,
       datetime(1700000000 + n * 37, 'unixepoch') AS created_at
FROM c;
CREATE INDEX idx_events_user ON events(user_id);
`;

export function App() {
  const clientRef = useRef<SqliteClient | null>(null);
  const [tables, setTables] = useState<DBTable[]>([]);
  const [dbName, setDbName] = useState("demo");
  const [selected, setSelected] = useState<string | null>(null);
  const [tabs, setTabs] = useState<Tab[]>([]);
  const [activeTab, setActiveTab] = useState<string | null>(null);
  const [status, setStatus] = useState("initializing…");
  const fileInput = useRef<HTMLInputElement>(null);

  const refreshSchema = useCallback(async () => {
    const c = clientRef.current!;
    setTables(await c.introspect());
  }, []);

  useEffect(() => {
    const c = new SqliteClient();
    clientRef.current = c;
    (async () => {
      const t0 = performance.now();
      await c.openEmpty();
      setStatus("generating 100k-row demo…");
      await c.exec(DEMO_SQL);
      await refreshSchema();
      setStatus(`ready · demo built in ${(performance.now() - t0).toFixed(0)} ms`);
    })();
  }, [refreshSchema]);

  const openTable = useCallback((name: string) => {
    setSelected(name);
    const id = "table:" + name;
    setTabs((t) => (t.some((x) => x.id === id) ? t : [...t, { id, kind: "table", name }]));
    setActiveTab(id);
  }, []);

  const openConsole = useCallback(() => {
    const id = "console:" + Date.now();
    setTabs((t) => [...t, { id, kind: "console" }]);
    setActiveTab(id);
  }, []);

  const closeTab = (id: string) => {
    setTabs((t) => {
      const next = t.filter((x) => x.id !== id);
      if (activeTab === id) setActiveTab(next.length ? next[next.length - 1].id : null);
      return next;
    });
  };

  async function onOpenFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    const bytes = await file.arrayBuffer();
    await clientRef.current!.openBytes(bytes);
    setDbName(file.name);
    setTabs([]);
    setActiveTab(null);
    setSelected(null);
    await refreshSchema();
    setStatus(`opened ${file.name}`);
  }

  const schema = useMemo(() => {
    const s: Record<string, string[]> = {};
    for (const t of tables) s[t.name] = t.columns.map((c) => c.name);
    return s;
  }, [tables]);

  const active = tabs.find((t) => t.id === activeTab) ?? null;

  return (
    <div className="app">
      <div className="titlebar">
        <span className="title">Dani's DB Viewer <span style={{ color: "var(--dim)", fontWeight: 400 }}>· Web / WASM</span></span>
        <button onClick={() => fileInput.current?.click()}>Open .db…</button>
        <button onClick={openConsole}>New Console</button>
        <input ref={fileInput} type="file" accept=".db,.sqlite,.sqlite3" style={{ display: "none" }} onChange={onOpenFile} />
        <span className="spacer" />
        <span className="info" style={{ color: "var(--dim)", fontSize: 11 }}>{status}</span>
      </div>
      <div className="main">
        <Explorer dbName={dbName} tables={tables} selected={selected} onSelect={setSelected} onOpen={openTable} />
        <div className="content">
          {tabs.length === 0 ? (
            <div className="empty">
              <div style={{ fontSize: 40, opacity: 0.4 }}>🗄</div>
              <div>Double-click a table, or open a query console</div>
              <div style={{ fontSize: 12 }}>Everything runs in your browser — SQLite compiled to WebAssembly.</div>
            </div>
          ) : (
            <>
              <div className="tabbar">
                {tabs.map((t) => (
                  <div key={t.id} className={"tab" + (t.id === activeTab ? " active" : "")} onClick={() => setActiveTab(t.id)}>
                    <span>{t.kind === "table" ? "▦ " + t.name : "⌘ console"}</span>
                    <button className="close" onClick={(e) => { e.stopPropagation(); closeTab(t.id); }}>✕</button>
                  </div>
                ))}
              </div>
              {tabs.map((t) => (
                <div key={t.id} style={{ display: t.id === activeTab ? "flex" : "none", flex: 1, flexDirection: "column", minHeight: 0 }}>
                  {t.kind === "table" ? (
                    <TableView client={clientRef.current!} table={tables.find((x) => x.name === (t as TableTab).name)} />
                  ) : (
                    <Console client={clientRef.current!} schema={schema} />
                  )}
                </div>
              ))}
            </>
          )}
          {active === null && tabs.length === 0 ? null : null}
        </div>
      </div>
    </div>
  );
}

function TableView({ client, table }: { client: SqliteClient; table?: DBTable }) {
  const [result, setResult] = useState<QueryResult | null>(null);
  const [sortCol, setSortCol] = useState<number | undefined>();
  const [sortDesc, setSortDesc] = useState(false);
  const [where, setWhere] = useState("");
  const [whereDraft, setWhereDraft] = useState("");

  const load = useCallback(async () => {
    if (!table) return;
    let sql = `SELECT * FROM "${table.name.replace(/"/g, '""')}"`;
    if (where.trim()) sql += ` WHERE ${where}`;
    if (sortCol != null && result) sql += ` ORDER BY "${result.columns[sortCol]}" ${sortDesc ? "DESC" : "ASC"}`;
    sql += " LIMIT 500000";
    setResult(await client.exec(sql));
  }, [table, where, sortCol, sortDesc]); // eslint-disable-line

  useEffect(() => { load(); }, [table?.name, where, sortCol, sortDesc]); // eslint-disable-line

  if (!table) return <div className="empty">Table not found</div>;

  return (
    <>
      <div className="toolbar">
        <span className="info">{table.name}</span>
        <span style={{ color: "var(--dim)", fontFamily: "var(--mono)", fontSize: 11 }}>WHERE</span>
        <input
          value={whereDraft}
          onChange={(e) => setWhereDraft(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") setWhere(whereDraft); }}
          placeholder="filter, e.g. event_type = 'purchase'"
          style={{ flex: 1, background: "var(--bg-editor)", border: "1px solid var(--border)", borderRadius: 6, color: "var(--text)", padding: "3px 8px", fontFamily: "var(--mono)", fontSize: 12, outline: "none" }}
        />
        <button onClick={load}>Reload</button>
      </div>
      {result?.error ? (
        <div className="error-banner">✕ {result.error}</div>
      ) : (
        <DataGrid
          columns={result?.columns ?? table.columns.map((c) => c.name)}
          columnTypes={table.columns.map((c) => c.type)}
          rows={result?.rows ?? []}
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
