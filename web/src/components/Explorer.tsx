import { useState } from "react";
import type { DBTable } from "../db/types";

interface Props {
  dbName: string;
  tables: DBTable[];
  selected: string | null;
  onSelect: (name: string) => void;
  onOpen: (name: string) => void;
}

export function Explorer({ dbName, tables, selected, onSelect, onOpen }: Props) {
  const [search, setSearch] = useState("");
  const [dsOpen, setDsOpen] = useState(true);
  const filtered = search
    ? tables.filter((t) => t.name.toLowerCase().includes(search.toLowerCase()))
    : tables;

  return (
    <div className="sidebar">
      <div className="head">DATABASE</div>
      <div className="search">
        <input placeholder="Search objects" value={search} onChange={(e) => setSearch(e.target.value)} />
      </div>
      <div className="tree">
        <div className="row" onClick={() => setDsOpen((o) => !o)}>
          <span className={"chevron" + (dsOpen ? " open" : "")}>›</span>
          <span className="ico" style={{ color: "var(--green)" }}>🗄</span>
          <span>{dbName}</span>
          <span className="detail">SQLite · WASM</span>
        </div>
        {dsOpen &&
          filtered.map((t) => (
            <TableNode
              key={t.name}
              table={t}
              selected={selected === t.name}
              onSelect={() => onSelect(t.name)}
              onOpen={() => onOpen(t.name)}
            />
          ))}
      </div>
    </div>
  );
}

function TableNode({
  table,
  selected,
  onSelect,
  onOpen,
}: {
  table: DBTable;
  selected: boolean;
  onSelect: () => void;
  onOpen: () => void;
}) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <div
        className={"row" + (selected ? " selected" : "")}
        style={{ paddingLeft: 22 }}
        onClick={onSelect}
        onDoubleClick={onOpen}
        title={`${table.kind === "view" ? "View" : "Table"} “${table.name}” — double-click to open`}
      >
        <span
          className={"chevron" + (open ? " open" : "")}
          onClick={(e) => {
            e.stopPropagation();
            setOpen((o) => !o);
          }}
        >
          ›
        </span>
        <span className="ico" style={{ color: table.kind === "view" ? "var(--view)" : "var(--table)" }}>
          {table.kind === "view" ? "◉" : "▦"}
        </span>
        <span>{table.name}</span>
      </div>
      {open && (
        <>
          {table.columns.map((c) => (
            <div
              key={c.name}
              className="row"
              style={{ paddingLeft: 48 }}
              title={`${c.name} · ${c.type}${c.primaryKey ? " · PK" : ""}${c.notNull ? " · not null" : ""}`}
            >
              <span
                className="ico"
                style={{ color: c.primaryKey ? "var(--pk)" : "var(--dim)", fontSize: 11 }}
              >
                {c.primaryKey ? "🔑" : "•"}
              </span>
              <span>{c.name}</span>
              <span className="detail">
                {c.type.toLowerCase()}
                {c.notNull ? " · not null" : ""}
              </span>
            </div>
          ))}
        </>
      )}
    </>
  );
}
