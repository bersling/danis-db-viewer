import { useState } from "react";
import CodeMirror from "@uiw/react-codemirror";
import { sql, SQLite, PostgreSQL, MySQL } from "@codemirror/lang-sql";
import { EditorView } from "@codemirror/view";
import type { QueryResult } from "../db/types";
import { DataGrid } from "./DataGrid";

type QueryFn = (sql: string) => Promise<QueryResult>;

const darcula = EditorView.theme(
  {
    "&": { backgroundColor: "#1e1f22", color: "#dcdcdd", fontSize: "13px", height: "100%" },
    ".cm-gutters": { backgroundColor: "#1e1f22", color: "#606366", border: "none" },
    ".cm-activeLine": { backgroundColor: "rgba(255,255,255,0.03)" },
    ".cm-activeLineGutter": { backgroundColor: "transparent" },
    "&.cm-focused": { outline: "none" },
    ".cm-content": { fontFamily: "ui-monospace, Menlo, monospace" },
  },
  { dark: true }
);

export function Console({
  queryFn,
  schema,
  dialect = "sqlite",
}: {
  queryFn: QueryFn;
  schema: Record<string, string[]>;
  dialect?: "sqlite" | "postgres" | "mysql";
}) {
  const [text, setText] = useState("SELECT 1;");
  const [result, setResult] = useState<QueryResult | null>(null);
  const [running, setRunning] = useState(false);
  const sqlDialect = dialect === "postgres" ? PostgreSQL : dialect === "mysql" ? MySQL : SQLite;

  async function run() {
    if (running) return;
    setRunning(true);
    const r = await queryFn(text);
    setResult(r);
    setRunning(false);
  }

  return (
    <div className="console">
      <div className="toolbar">
        <button onClick={run} disabled={running} title="Run (⌘⏎)" style={{ color: "var(--green)" }}>
          ▶ Run
        </button>
        {running && <span className="info">running…</span>}
        <span className="spacer" />
        <span className="info">⌘⏎ to run</span>
      </div>
      <div className="editor-pane">
        <CodeMirror
          value={text}
          height="100%"
          theme={darcula}
          extensions={[
            sql({ dialect: sqlDialect, schema }),
            EditorView.lineWrapping,
            keymapRun(run),
          ]}
          onChange={setText}
          basicSetup={{ lineNumbers: true, highlightActiveLine: true }}
        />
      </div>
      <div className="results">
        {!result ? (
          <div className="empty">Results appear here — ⌘⏎ to run</div>
        ) : result.error ? (
          <div className="error-banner">✕ {result.error}</div>
        ) : result.columns.length === 0 ? (
          <div className="ok-banner">✓ {result.rowsAffected ?? 0} row(s) affected · {result.durationMs.toFixed(0)} ms</div>
        ) : (
          <>
            <DataGrid columns={result.columns} rows={result.rows} />
            <div className="statusbar">
              <span>{result.rows.length} rows</span>
              <span className="spacer" style={{ flex: 1 }} />
              <span>{result.durationMs.toFixed(0)} ms</span>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

import { keymap } from "@codemirror/view";
function keymapRun(run: () => void) {
  return keymap.of([
    {
      key: "Mod-Enter",
      run: () => {
        run();
        return true;
      },
    },
  ]);
}
