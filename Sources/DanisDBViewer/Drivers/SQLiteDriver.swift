import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite driver on the system libsqlite3. All DB access is serialized on an
/// internal queue; the async methods hop onto it.
final class SQLiteDriver: DatabaseDriver {
    let config: DataSourceConfig
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "sqlite-driver")

    init(config: DataSourceConfig) {
        self.config = config
    }

    func connect() async throws {
        try await run {
            guard self.db == nil else { return }
            var handle: OpaquePointer?
            let path = (self.config.filePath as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else {
                throw DriverError.connectionFailed("File does not exist: \(path)")
            }
            if sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE, nil) != SQLITE_OK {
                let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open"
                sqlite3_close_v2(handle)
                throw DriverError.connectionFailed(msg)
            }
            self.db = handle
            sqlite3_busy_timeout(handle, 3000)
            _ = try? self.rawQuery("PRAGMA foreign_keys = ON")
        }
    }

    func close() async {
        try? await run {
            if let db = self.db { sqlite3_close_v2(db) }
            self.db = nil
        }
    }

    func quoteIdentifier(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Introspection

    func introspect() async throws -> DBIntrospection {
        try await run {
            var schema = DBSchemaInfo(name: "main", isDefault: true)
            let tableRows = try self.rawQuery("""
                SELECT name, type FROM sqlite_master
                WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%'
                ORDER BY type, name
                """)
            for row in tableRows.rows {
                guard case .text(let name) = row[0], case .text(let type) = row[1] else { continue }
                var table = DBTableInfo(schema: "main", name: name, kind: type == "view" ? .view : .table)
                table.columns = try self.columns(of: name)
                if type == "table" {
                    table.indexes = try self.indexes(of: name)
                    table.foreignKeys = try self.foreignKeys(of: name)
                }
                schema.tables.append(table)
            }
            return DBIntrospection(schemas: [schema])
        }
    }

    private func columns(of table: String) throws -> [DBColumnInfo] {
        let res = try rawQuery("PRAGMA table_info(\(quoteIdentifier(table)))")
        // cid, name, type, notnull, dflt_value, pk
        var cols: [DBColumnInfo] = []
        for row in res.rows {
            guard case .text(let name) = row[1] else { continue }
            var col = DBColumnInfo(name: name, typeName: textOf(row[2]) ?? "")
            col.isNullable = intOf(row[3]) == 0
            col.defaultValue = textOf(row[4])
            col.isPrimaryKey = (intOf(row[5]) ?? 0) > 0
            col.ordinal = Int(intOf(row[0]) ?? 0)
            // INTEGER PRIMARY KEY is an alias for rowid → auto-increment behavior
            col.isAutoIncrement = col.isPrimaryKey && col.typeName.uppercased() == "INTEGER"
            cols.append(col)
        }
        return cols
    }

    private func indexes(of table: String) throws -> [DBIndexInfo] {
        let list = try rawQuery("PRAGMA index_list(\(quoteIdentifier(table)))")
        var result: [DBIndexInfo] = []
        for row in list.rows {
            guard case .text(let name) = row[1] else { continue }
            let unique = intOf(row[2]) == 1
            let info = try rawQuery("PRAGMA index_info(\(quoteIdentifier(name)))")
            let cols = info.rows.compactMap { textOf($0[2]) }
            result.append(DBIndexInfo(name: name, columns: cols, isUnique: unique))
        }
        return result
    }

    private func foreignKeys(of table: String) throws -> [DBForeignKeyInfo] {
        let res = try rawQuery("PRAGMA foreign_key_list(\(quoteIdentifier(table)))")
        // id, seq, table, from, to, on_update, on_delete, match
        var grouped: [Int64: DBForeignKeyInfo] = [:]
        for row in res.rows {
            guard let fkId = intOf(row[0]) else { continue }
            let refTable = textOf(row[2]) ?? ""
            let from = textOf(row[3]) ?? ""
            let to = textOf(row[4]) ?? from
            var fk = grouped[fkId] ?? DBForeignKeyInfo(
                name: "fk_\(table)_\(fkId)", columns: [], referencedSchema: "main",
                referencedTable: refTable, referencedColumns: [])
            fk.columns.append(from)
            fk.referencedColumns.append(to)
            grouped[fkId] = fk
        }
        return grouped.keys.sorted().compactMap { grouped[$0] }
    }

    // MARK: - Execution

    func execute(script: String) async -> [QueryResult] {
        let statements = SQLSplitter.split(script)
        var results: [QueryResult] = []
        for stmt in statements {
            let start = Date()
            var result = QueryResult(statement: stmt)
            do {
                let res = try await run { try self.rawQuery(stmt) }
                if res.isSelect {
                    result.columns = res.columns
                    result.columnTypes = res.columnTypes
                    result.rows = res.rows
                } else {
                    result.affectedRows = res.affected
                }
            } catch {
                result.error = error.localizedDescription
            }
            result.duration = Date().timeIntervalSince(start)
            results.append(result)
        }
        return results
    }

    func fetchTableData(_ request: TableDataRequest) async throws -> TableDataPage {
        try await run {
            var page = TableDataPage()
            let res = try self.rawQuery(self.buildSelect(request))
            page.columns = res.columns
            page.columnTypes = res.columnTypes
            page.rows = res.rows
            if let countRes = try? self.rawQuery(self.buildCount(request)),
               let first = countRes.rows.first, let total = self.intOf(first[0]) {
                page.totalRows = Int(total)
            }
            return page
        }
    }

    func apply(changes: [RowChange], schema: String, table: String) async throws {
        let statements = changeStatements(changes, schema: "", table: table)
        try await run {
            _ = try self.rawQuery("BEGIN")
            do {
                for sql in statements { _ = try self.rawQuery(sql) }
                _ = try self.rawQuery("COMMIT")
            } catch {
                _ = try? self.rawQuery("ROLLBACK")
                throw error
            }
        }
    }

    func ddl(schema: String, table: String) async throws -> String {
        try await run {
            let res = try self.rawQuery(
                "SELECT sql FROM sqlite_master WHERE name = \(DBValue.text(table).sqlLiteral) AND sql IS NOT NULL")
            var parts = res.rows.compactMap { self.textOf($0[0]) }
            let idx = try self.rawQuery(
                "SELECT sql FROM sqlite_master WHERE tbl_name = \(DBValue.text(table).sqlLiteral) AND type = 'index' AND sql IS NOT NULL")
            parts += idx.rows.compactMap { self.textOf($0[0]) }
            return parts.map { $0 + ";" }.joined(separator: "\n\n")
        }
    }

    // MARK: - Raw access (queue-confined)

    private struct RawResult {
        var columns: [String] = []
        var columnTypes: [String] = []
        var rows: [[DBValue]] = []
        var affected: Int = 0
        var isSelect: Bool = false
    }

    private func rawQuery(_ sql: String) throws -> RawResult {
        guard let db else { throw DriverError.connectionFailed("Not connected") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DriverError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var result = RawResult()
        let colCount = sqlite3_column_count(stmt)
        result.isSelect = colCount > 0
        for i in 0..<colCount {
            result.columns.append(String(cString: sqlite3_column_name(stmt, i)))
            result.columnTypes.append(sqlite3_column_decltype(stmt, i).map { String(cString: $0) } ?? "")
        }

        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                var row: [DBValue] = []
                for i in 0..<colCount {
                    switch sqlite3_column_type(stmt, i) {
                    case SQLITE_NULL: row.append(.null)
                    case SQLITE_INTEGER: row.append(.int(sqlite3_column_int64(stmt, i)))
                    case SQLITE_FLOAT: row.append(.double(sqlite3_column_double(stmt, i)))
                    case SQLITE_BLOB:
                        let bytes = sqlite3_column_blob(stmt, i)
                        let count = Int(sqlite3_column_bytes(stmt, i))
                        row.append(.blob(bytes.map { Data(bytes: $0, count: count) } ?? Data()))
                    default:
                        row.append(.text(String(cString: sqlite3_column_text(stmt, i))))
                    }
                }
                result.rows.append(row)
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw DriverError.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
        if !result.isSelect { result.affected = Int(sqlite3_changes(db)) }
        return result
    }

    private func run<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                do { cont.resume(returning: try body()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    private func textOf(_ v: DBValue) -> String? {
        switch v {
        case .text(let s): return s
        case .int(let i): return String(i)
        case .null: return nil
        default: return v.displayString
        }
    }

    private func intOf(_ v: DBValue) -> Int64? {
        switch v {
        case .int(let i): return i
        case .text(let s): return Int64(s)
        default: return nil
        }
    }
}
