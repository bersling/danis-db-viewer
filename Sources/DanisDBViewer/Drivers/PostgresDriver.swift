import Foundation
import Logging
import NIOCore
import NIOPosix
import PostgresNIO

/// PostgreSQL driver on PostgresNIO.
final class PostgresDriver: DatabaseDriver {
    let config: DataSourceConfig
    private var connection: PostgresConnection?
    private var group: MultiThreadedEventLoopGroup?
    private let logger = Logger(label: "postgres-driver")

    init(config: DataSourceConfig) {
        self.config = config
    }

    func quoteIdentifier(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    func connect() async throws {
        guard connection == nil else { return }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group
        let cfg = PostgresConnection.Configuration(
            host: config.host,
            port: config.effectivePort,
            username: config.user,
            password: config.resolvedPassword,
            database: config.database.isEmpty ? config.user : config.database,
            tls: .disable
        )
        do {
            let eventLoop = group.next()
            let log = logger
            connection = try await ConnectionDiagnostics.withConnectTimeout(connect: {
                try await PostgresConnection.connect(on: eventLoop, configuration: cfg, id: 1, logger: log)
            }, close: { conn in
                try? await conn.close()
            })
        } catch {
            try? await group.shutdownGracefully()
            self.group = nil
            let described = DriverError.connectionFailed(describe(error))
            throw DriverError.connectionFailed(ConnectionDiagnostics.explain(
                (error as? DriverError) ?? described, config: config))
        }
    }

    func close() async {
        try? await connection?.close()
        connection = nil
        if let group { try? await group.shutdownGracefully() }
        group = nil
    }

    // MARK: - Introspection

    func introspect() async throws -> DBIntrospection {
        let schemaRows = try await rawQuery("""
            SELECT nspname FROM pg_namespace
            WHERE nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
            ORDER BY nspname
            """)
        var schemas: [DBSchemaInfo] = []
        for sRow in schemaRows.rows {
            guard case .text(let schemaName) = sRow[0] else { continue }
            var schema = DBSchemaInfo(name: schemaName, isDefault: schemaName == "public")

            let tableRows = try await rawQuery("""
                SELECT table_name, table_type FROM information_schema.tables
                WHERE table_schema = \(DBValue.text(schemaName).sqlLiteral)
                ORDER BY table_name
                """)
            let columnRows = try await rawQuery("""
                SELECT table_name, column_name, data_type, is_nullable, column_default, ordinal_position
                FROM information_schema.columns
                WHERE table_schema = \(DBValue.text(schemaName).sqlLiteral)
                ORDER BY table_name, ordinal_position
                """)
            let pkRows = try await rawQuery("""
                SELECT tc.table_name, kcu.column_name
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                  ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
                WHERE tc.constraint_type = 'PRIMARY KEY' AND tc.table_schema = \(DBValue.text(schemaName).sqlLiteral)
                """)
            let indexRows = try await rawQuery("""
                SELECT t.relname AS table_name, i.relname AS index_name, a.attname AS column_name, ix.indisunique
                FROM pg_index ix
                JOIN pg_class i ON i.oid = ix.indexrelid
                JOIN pg_class t ON t.oid = ix.indrelid
                JOIN pg_namespace n ON n.oid = t.relnamespace
                JOIN unnest(ix.indkey) WITH ORDINALITY AS k(attnum, ord) ON TRUE
                JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
                WHERE n.nspname = \(DBValue.text(schemaName).sqlLiteral) AND NOT ix.indisprimary
                ORDER BY i.relname, k.ord
                """)
            let fkRows = try await rawQuery("""
                SELECT tc.table_name, tc.constraint_name, kcu.column_name,
                       ccu.table_schema, ccu.table_name AS ref_table, ccu.column_name AS ref_column
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                  ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
                JOIN information_schema.constraint_column_usage ccu
                  ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
                WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = \(DBValue.text(schemaName).sqlLiteral)
                ORDER BY tc.constraint_name, kcu.ordinal_position
                """)

            var pkMap: [String: Set<String>] = [:]
            for row in pkRows.rows {
                if case .text(let t) = row[0], case .text(let c) = row[1] { pkMap[t, default: []].insert(c) }
            }
            var colMap: [String: [DBColumnInfo]] = [:]
            for row in columnRows.rows {
                guard case .text(let t) = row[0], case .text(let name) = row[1] else { continue }
                var col = DBColumnInfo(name: name, typeName: str(row[2]) ?? "")
                col.isNullable = str(row[3]) == "YES"
                col.defaultValue = str(row[4])
                col.ordinal = Int(int(row[5]) ?? 0)
                col.isPrimaryKey = pkMap[t]?.contains(name) ?? false
                col.isAutoIncrement = (col.defaultValue ?? "").contains("nextval") || col.typeName.contains("serial")
                colMap[t, default: []].append(col)
            }
            var idxMap: [String: [String: DBIndexInfo]] = [:]
            for row in indexRows.rows {
                guard case .text(let t) = row[0], case .text(let idx) = row[1], case .text(let c) = row[2] else { continue }
                var info = idxMap[t]?[idx] ?? DBIndexInfo(name: idx, columns: [], isUnique: bool(row[3]) ?? false)
                info.columns.append(c)
                idxMap[t, default: [:]][idx] = info
            }
            var fkMap: [String: [String: DBForeignKeyInfo]] = [:]
            for row in fkRows.rows {
                guard case .text(let t) = row[0], case .text(let name) = row[1], case .text(let c) = row[2] else { continue }
                var fk = fkMap[t]?[name] ?? DBForeignKeyInfo(
                    name: name, columns: [], referencedSchema: str(row[3]) ?? "",
                    referencedTable: str(row[4]) ?? "", referencedColumns: [])
                // constraint_column_usage repeats ref columns; dedupe pairwise
                if !fk.columns.contains(c) {
                    fk.columns.append(c)
                    if let rc = str(row[5]) { fk.referencedColumns.append(rc) }
                }
                fkMap[t, default: [:]][name] = fk
            }

            for row in tableRows.rows {
                guard case .text(let name) = row[0] else { continue }
                let type = str(row[1]) ?? ""
                var table = DBTableInfo(schema: schemaName, name: name, kind: type == "VIEW" ? .view : .table)
                table.columns = colMap[name] ?? []
                table.indexes = (idxMap[name] ?? [:]).values.sorted { $0.name < $1.name }
                table.foreignKeys = (fkMap[name] ?? [:]).values.sorted { $0.name < $1.name }
                schema.tables.append(table)
            }
            schemas.append(schema)
        }
        return DBIntrospection(schemas: schemas)
    }

    // MARK: - Execution

    func execute(script: String) async -> [QueryResult] {
        var results: [QueryResult] = []
        for stmt in SQLSplitter.split(script) {
            let start = Date()
            var result = QueryResult(statement: stmt)
            do {
                let raw = try await rawQuery(stmt)
                if raw.isResultSet {
                    result.columns = raw.columns
                    result.columnTypes = raw.columnTypes
                    result.rows = raw.rows
                } else {
                    result.affectedRows = raw.affected
                }
            } catch {
                result.error = describe(error)
            }
            result.duration = Date().timeIntervalSince(start)
            results.append(result)
        }
        return results
    }

    func fetchTableData(_ request: TableDataRequest) async throws -> TableDataPage {
        var page = TableDataPage()
        let raw = try await rawQuery(buildSelect(request))
        page.columns = raw.columns
        page.columnTypes = raw.columnTypes
        page.rows = raw.rows
        if let countRaw = try? await rawQuery(buildCount(request)),
           let first = countRaw.rows.first, let total = int(first[0]) {
            page.totalRows = Int(total)
        }
        return page
    }

    func apply(changes: [RowChange], schema: String, table: String) async throws {
        let statements = changeStatements(changes, schema: schema, table: table)
        _ = try await rawQuery("BEGIN")
        do {
            for sql in statements { _ = try await rawQuery(sql) }
            _ = try await rawQuery("COMMIT")
        } catch {
            _ = try? await rawQuery("ROLLBACK")
            throw DriverError.queryFailed(describe(error))
        }
    }

    func ddl(schema: String, table: String) async throws -> String {
        // Postgres has no built-in SHOW CREATE TABLE; assemble from catalog.
        let intro = try await introspect()
        guard let t = intro.schemas.first(where: { $0.name == schema })?
            .tables.first(where: { $0.name == table }) else {
            throw DriverError.queryFailed("Table not found: \(schema).\(table)")
        }
        return DDLGenerator.createTable(t, quote: quoteIdentifier)
    }

    // MARK: - Raw

    private struct Raw {
        var columns: [String] = []
        var columnTypes: [String] = []
        var rows: [[DBValue]] = []
        var affected: Int = 0
        var isResultSet: Bool = false
    }

    private func rawQuery(_ sql: String) async throws -> Raw {
        guard let connection else { throw DriverError.connectionFailed("Not connected") }
        var raw = Raw()
        do {
            let stream = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
            var first = true
            for try await row in stream {
                let cells = row.makeRandomAccess()
                if first {
                    first = false
                    raw.isResultSet = true
                    for cell in cells {
                        raw.columns.append(cell.columnName)
                        raw.columnTypes.append(typeName(cell.dataType))
                    }
                }
                raw.rows.append(cells.map { decode($0) })
            }
            if first {
                // No rows: could be an empty SELECT or DML. Ask for the command tag.
                // PostgresNIO surfaces no direct tag on the async API; treat
                // SELECT-ish statements as empty result sets.
                let head = sql.trimmingCharacters(in: .whitespacesAndNewlines).prefix(6).uppercased()
                if ["SELECT", "VALUES", "TABLE ", "SHOW ", "WITH "].contains(where: { head.hasPrefix($0.trimmingCharacters(in: .whitespaces)) }) {
                    raw.isResultSet = true
                }
            }
        } catch {
            throw DriverError.queryFailed(describe(error))
        }
        return raw
    }

    private func typeName(_ dataType: PostgresDataType) -> String {
        String(describing: dataType)
    }

    private func decode(_ cell: PostgresCell) -> DBValue {
        if cell.bytes == nil { return .null }
        switch cell.dataType {
        case .int2, .int4, .int8:
            if let v = try? cell.decode(Int64.self) { return .int(v) }
        case .float4, .float8:
            if let v = try? cell.decode(Double.self) { return .double(v) }
        case .numeric:
            if let v = try? cell.decode(Decimal.self) { return .text("\(v)") }
        case .bool:
            if let v = try? cell.decode(Bool.self) { return .bool(v) }
        case .bytea:
            if let v = try? cell.decode(Data.self) { return .blob(v) }
        case .timestamp, .timestamptz, .date:
            if let v = try? cell.decode(Date.self) {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return .text(f.string(from: v))
            }
        case .uuid:
            if let v = try? cell.decode(UUID.self) { return .text(v.uuidString.lowercased()) }
        default:
            break
        }
        if let s = try? cell.decode(String.self) { return .text(s) }
        if var buf = cell.bytes, let s = buf.readString(length: buf.readableBytes) { return .text(s) }
        return .null
    }

    private func describe(_ error: Error) -> String {
        if let pg = error as? PSQLError {
            if let serverInfo = pg.serverInfo, let message = serverInfo[.message] {
                let detail = serverInfo[.detail].map { " — \($0)" } ?? ""
                return message + detail
            }
            return String(reflecting: pg)
        }
        return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    private func str(_ v: DBValue) -> String? {
        if case .text(let s) = v { return s }
        if case .null = v { return nil }
        return v.displayString
    }

    private func int(_ v: DBValue) -> Int64? {
        if case .int(let i) = v { return i }
        if case .text(let s) = v { return Int64(s) }
        if case .double(let d) = v { return Int64(d) }
        return nil
    }

    private func bool(_ v: DBValue) -> Bool? {
        if case .bool(let b) = v { return b }
        if case .text(let s) = v { return s == "t" || s == "true" }
        return nil
    }
}
