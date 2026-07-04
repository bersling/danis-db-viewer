export type DBValue = string | number | Uint8Array | null;

export interface QueryResult {
  columns: string[];
  rows: DBValue[][];
  rowsAffected?: number;
  error?: string;
  durationMs: number;
}

export interface Connection {
  id: string;
  name: string;
  kind: "sqlite" | "postgres" | "mysql";
  host?: string;
  port?: number;
  user?: string;
  database?: string;
  color?: string;
}

export interface SchemaTable {
  schema: string;
  name: string;
  kind: "table" | "view";
  columns: { name: string; type: string; notNull: boolean; primaryKey: boolean }[];
}

export interface SchemaInfo {
  schema: string;
  tables: SchemaTable[];
}
