import Foundation

/// Request for one page of table data (the grid).
struct TableDataRequest {
    var schema: String
    var table: String
    var limit: Int = 100
    var offset: Int = 0
    var orderBy: [(column: String, descending: Bool)] = []
    var whereClause: String = ""   // raw user filter, appended after WHERE
}

struct TableDataPage {
    var columns: [String] = []
    var columnTypes: [String] = []
    var rows: [[DBValue]] = []
    var totalRows: Int? = nil
    var error: String? = nil
}

/// Staged grid mutations, IntelliJ "Submit" style.
enum RowChange {
    /// keyColumns/keyValues identify the row (PK if available, else all original values).
    case update(keyColumns: [String], keyValues: [DBValue], setColumns: [String], setValues: [DBValue])
    case insert(columns: [String], values: [DBValue])
    case delete(keyColumns: [String], keyValues: [DBValue])
}

enum DriverError: LocalizedError {
    case connectionFailed(String)
    case queryFailed(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let m): return m
        case .queryFailed(let m): return m
        case .unsupported(let m): return m
        }
    }
}

/// One live connection to a data source. Implementations: SQLite, Postgres, MySQL.
protocol DatabaseDriver: AnyObject {
    var config: DataSourceConfig { get }

    func connect() async throws
    func close() async

    /// Full structural introspection (schemas → tables → columns/indexes/FKs).
    func introspect() async throws -> DBIntrospection

    /// Execute a script; one QueryResult per statement. Never throws for SQL
    /// errors — those are reported per-statement via `QueryResult.error`.
    func execute(script: String) async -> [QueryResult]

    /// One page of a table, with total count.
    func fetchTableData(_ request: TableDataRequest) async throws -> TableDataPage

    /// Apply staged grid changes in a single transaction.
    func apply(changes: [RowChange], schema: String, table: String) async throws

    /// Generated DDL for a table/view.
    func ddl(schema: String, table: String) async throws -> String

    /// Quote an identifier for this DBMS.
    func quoteIdentifier(_ name: String) -> String
}

extension DatabaseDriver {
    /// Shared SELECT builder for the data grid.
    func buildSelect(_ r: TableDataRequest) -> String {
        var sql = "SELECT * FROM \(qualifiedName(schema: r.schema, table: r.table))"
        let filter = r.whereClause.trimmingCharacters(in: .whitespacesAndNewlines)
        if !filter.isEmpty { sql += " WHERE \(filter)" }
        if !r.orderBy.isEmpty {
            sql += " ORDER BY " + r.orderBy
                .map { "\(quoteIdentifier($0.column)) \($0.descending ? "DESC" : "ASC")" }
                .joined(separator: ", ")
        }
        sql += " LIMIT \(r.limit) OFFSET \(r.offset)"
        return sql
    }

    func buildCount(_ r: TableDataRequest) -> String {
        var sql = "SELECT COUNT(*) FROM \(qualifiedName(schema: r.schema, table: r.table))"
        let filter = r.whereClause.trimmingCharacters(in: .whitespacesAndNewlines)
        if !filter.isEmpty { sql += " WHERE \(filter)" }
        return sql
    }

    func qualifiedName(schema: String, table: String) -> String {
        schema.isEmpty ? quoteIdentifier(table) : "\(quoteIdentifier(schema)).\(quoteIdentifier(table))"
    }

    /// Render staged changes as SQL statements (shared by all drivers).
    func changeStatements(_ changes: [RowChange], schema: String, table: String) -> [String] {
        let target = qualifiedName(schema: schema, table: table)
        return changes.map { change in
            switch change {
            case .insert(let columns, let values):
                let cols = columns.map(quoteIdentifier).joined(separator: ", ")
                let vals = values.map(\.sqlLiteral).joined(separator: ", ")
                return "INSERT INTO \(target) (\(cols)) VALUES (\(vals))"
            case .update(let keyColumns, let keyValues, let setColumns, let setValues):
                let sets = zip(setColumns, setValues)
                    .map { "\(quoteIdentifier($0)) = \($1.sqlLiteral)" }
                    .joined(separator: ", ")
                return "UPDATE \(target) SET \(sets) WHERE \(whereEquals(keyColumns, keyValues))"
            case .delete(let keyColumns, let keyValues):
                return "DELETE FROM \(target) WHERE \(whereEquals(keyColumns, keyValues))"
            }
        }
    }

    private func whereEquals(_ columns: [String], _ values: [DBValue]) -> String {
        zip(columns, values).map { col, val in
            val.isNull ? "\(quoteIdentifier(col)) IS NULL" : "\(quoteIdentifier(col)) = \(val.sqlLiteral)"
        }.joined(separator: " AND ")
    }
}
