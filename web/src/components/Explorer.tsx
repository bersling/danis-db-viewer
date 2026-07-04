import { useState } from "react";
import type { Connection, SchemaInfo, SchemaTable } from "../db/types";

interface Props {
  connections: Connection[];
  schemas: Record<string, SchemaInfo[] | "loading" | { error: string } | undefined>;
  selected: string | null;
  onExpandConnection: (id: string) => void;
  onSelectTable: (key: string) => void;
  onOpenTable: (connId: string, schema: string, table: SchemaTable) => void;
}

const KIND_ICON: Record<string, string> = { sqlite: "🗄", postgres: "🐘", mysql: "🐬" };
const COLORS: Record<string, string> = {
  red: "#db5a5a", orange: "#e89a4a", yellow: "#e3c95e", green: "#73b86b",
  blue: "#5a94d9", violet: "#a67bd9", gray: "#8c8c8c",
};

export function Explorer(props: Props) {
  const [search, setSearch] = useState("");
  return (
    <div className="sidebar">
      <div className="head">DATABASE</div>
      <div className="search">
        <input placeholder="Search objects" value={search} onChange={(e) => setSearch(e.target.value)} />
      </div>
      <div className="tree">
        {props.connections.length === 0 && (
          <div style={{ padding: 12, color: "var(--dim)", fontSize: 12 }}>No connections found.</div>
        )}
        {props.connections.map((c) => (
          <ConnectionNode key={c.id} conn={c} search={search} {...props} />
        ))}
      </div>
    </div>
  );
}

function ConnectionNode({ conn, search, schemas, selected, onExpandConnection, onSelectTable, onOpenTable }: Props & { conn: Connection; search: string }) {
  const [open, setOpen] = useState(false);
  const state = schemas[conn.id];

  const isError = !!(state && typeof state === "object" && "error" in state);

  function toggle() {
    const next = !open;
    setOpen(next);
    // Fetch on first open, and re-fetch when reopening after an error (e.g. the
    // VPN was down before and is up now).
    if (next && (state === undefined || isError)) onExpandConnection(conn.id);
  }

  return (
    <>
      <div className="row" onClick={toggle} title={`${conn.kind} · ${conn.host ?? ""}`}>
        {conn.color && conn.color !== "none" && <span className="stripe" style={{ background: COLORS[conn.color] }} />}
        <span className={"chevron" + (open ? " open" : "")}>›</span>
        <span className="ico">{KIND_ICON[conn.kind] ?? "🗄"}</span>
        <span>{conn.name}</span>
        <span className="detail">{conn.kind}</span>
      </div>
      {open && state === "loading" && <div className="row" style={{ paddingLeft: 30, color: "var(--dim)" }}>connecting…</div>}
      {open && isError && (
        <div
          className="row"
          style={{ paddingLeft: 30, color: "#e06c75", height: "auto", whiteSpace: "normal", padding: "4px 8px 4px 30px", cursor: "pointer" }}
          onClick={() => onExpandConnection(conn.id)}
          title="Click to retry"
        >
          ⚠ {(state as { error: string }).error} — click to retry
        </div>
      )}
      {open && Array.isArray(state) &&
        state.map((s) => (
          <SchemaNode key={s.schema} conn={conn} schema={s} search={search}
            selected={selected} onSelectTable={onSelectTable} onOpenTable={onOpenTable}
            defaultOpen={state.length === 1 || s.schema === conn.database} />
        ))}
    </>
  );
}

function SchemaNode({ conn, schema, search, selected, onSelectTable, onOpenTable, defaultOpen }: {
  conn: Connection; schema: SchemaInfo; search: string; selected: string | null; defaultOpen: boolean;
  onSelectTable: (key: string) => void; onOpenTable: (connId: string, schema: string, table: SchemaTable) => void;
}) {
  const [open, setOpen] = useState(defaultOpen);
  const tables = search ? schema.tables.filter((t) => t.name.toLowerCase().includes(search.toLowerCase())) : schema.tables;
  if (search && tables.length === 0) return null;
  return (
    <>
      <div className="row" style={{ paddingLeft: 22 }} onClick={() => setOpen((o) => !o)}>
        <span className={"chevron" + (open ? " open" : "")}>›</span>
        <span className="ico" style={{ color: "var(--fk)" }}>⛁</span>
        <span>{schema.schema}</span>
        <span className="detail">{schema.tables.length}</span>
      </div>
      {open && tables.map((t) => {
        const key = `${conn.id}/${schema.schema}.${t.name}`;
        return (
          <div key={t.name} className={"row" + (selected === key ? " selected" : "")}
            style={{ paddingLeft: 44 }}
            onClick={() => onSelectTable(key)}
            onDoubleClick={() => onOpenTable(conn.id, schema.schema, t)}
            title={`${t.kind === "view" ? "View" : "Table"} “${t.name}” — double-click to open`}>
            <span className="ico" style={{ color: t.kind === "view" ? "var(--view)" : "var(--table)" }}>
              {t.kind === "view" ? "◉" : "▦"}
            </span>
            <span>{t.name}</span>
          </div>
        );
      })}
    </>
  );
}
