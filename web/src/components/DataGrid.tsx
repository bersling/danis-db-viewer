import { useRef, useMemo } from "react";
import { useVirtualizer } from "@tanstack/react-virtual";
import type { DBValue } from "../db/types";

interface Props {
  columns: string[];
  columnTypes?: string[];
  rows: DBValue[][];
  sortColumn?: number;
  sortDesc?: boolean;
  onSort?: (col: number) => void;
  onCellClick?: (row: number, col: number, value: DBValue) => void;
}

const ROW_H = 24;

/// Fully virtualized grid: only the ~40 visible rows exist in the DOM at any
/// moment, so 100k+ rows scroll at 60fps (the fix for the GitLab-diff problem).
export function DataGrid({ columns, columnTypes, rows, sortColumn, sortDesc, onSort, onCellClick }: Props) {
  const parentRef = useRef<HTMLDivElement>(null);

  const widths = useMemo(() => {
    return columns.map((c, i) => {
      let max = c.length + 4;
      for (let r = 0; r < Math.min(rows.length, 40); r++) {
        const v = rows[r][i];
        max = Math.max(max, v == null ? 6 : Math.min(String(v).length, 60));
      }
      return Math.min(Math.max(max * 7.3 + 16, 72), 460);
    });
  }, [columns, rows]);

  const totalWidth = 56 + widths.reduce((a, b) => a + b, 0);

  const rowVirt = useVirtualizer({
    count: rows.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => ROW_H,
    overscan: 12,
  });

  return (
    <div className="grid" ref={parentRef}>
      <div className="grid-header" style={{ width: totalWidth }}>
        <div className="gh-cell gh-gutter">#</div>
        {columns.map((c, i) => (
          <div
            key={i}
            className="gh-cell"
            style={{ width: widths[i] }}
            onClick={() => onSort?.(i)}
            title="Click to sort"
          >
            <span>{c}</span>
            {columnTypes?.[i] ? <span className="type">{columnTypes[i].toLowerCase()}</span> : null}
            {sortColumn === i ? <span style={{ color: "var(--accent)" }}>{sortDesc ? "▼" : "▲"}</span> : null}
          </div>
        ))}
      </div>

      <div style={{ height: rowVirt.getTotalSize(), width: totalWidth, position: "relative" }}>
        {rowVirt.getVirtualItems().map((vi) => {
          const row = rows[vi.index];
          return (
            <div
              key={vi.key}
              className={"grid-row " + (vi.index % 2 ? "odd" : "")}
              style={{ top: vi.start, height: ROW_H, width: totalWidth }}
            >
              <div className="gc gutter" style={{ height: ROW_H, lineHeight: `${ROW_H - 6}px` }}>
                {vi.index + 1}
              </div>
              {columns.map((_, ci) => {
                const v = row[ci];
                const isNull = v == null;
                return (
                  <div
                    key={ci}
                    className={"gc" + (isNull ? " null" : "")}
                    style={{ width: widths[ci] }}
                    onClick={() => onCellClick?.(vi.index, ci, v)}
                    title={isNull ? "" : String(v)}
                  >
                    {isNull ? "<null>" : String(v)}
                  </div>
                );
              })}
            </div>
          );
        })}
      </div>
    </div>
  );
}
