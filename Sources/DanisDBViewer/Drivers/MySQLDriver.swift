import Foundation
import Logging
import MySQLNIO
import NIOCore
import NIOPosix

/// MySQL / MariaDB driver on MySQLNIO.
final class MySQLDriver: DatabaseDriver {
    let config: DataSourceConfig
    private var connection: MySQLConnection?
    private var group: MultiThreadedEventLoopGroup?
    private let logger = Logger(label: "mysql-driver")

    init(config: DataSourceConfig) {
        self.config = config
    }

    func quoteIdentifier(_ name: String) -> String {
        "`" + name.replacingOccurrences(of: "`", with: "``") + "`"
    }

    func connect() async throws {
        guard connection == nil else { return }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group
        do {
            let cfg = config
            let log = logger
            let eventLoop = group.next()
            connection = try await ConnectionDiagnostics.withConnectTimeout(connect: {
                let address = try SocketAddress.makeAddressResolvingHost(cfg.host, port: cfg.effectivePort)
                return try await MySQLConnection.connect(
                    to: address,
                    username: cfg.user,
                    database: cfg.database,
                    password: cfg.resolvedPassword,
                    tlsConfiguration: nil,
                    logger: log,
                    on: eventLoop
                ).get()
            }, close: { conn in
                try? await conn.close().get()
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
        try? await connection?.close().get()
        connection = nil
        if let group { try? await group.shutdownGracefully() }
        group = nil
    }

    // MARK: - Introspection

    func introspect() async throws -> DBIntrospection {
        // Batch: 5 queries total across all non-system schemas (keyed by
        // schema+table), instead of 4 per schema. On a remote DB over VPN the
        // round-trip savings are the difference between seconds and a minute.
        // If a specific database is configured, scope to it (much faster on
        // big RDS instances with many databases).
        let scope: String
        if !config.database.isEmpty {
            scope = "= \(DBValue.text(config.database).sqlLiteral)"
        } else {
            scope = "NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')"
        }
        func key(_ s: String, _ t: String) -> String { s + "\t" + t }

        let dbRows = try await rawQuery(
            "SELECT schema_name FROM information_schema.schemata WHERE schema_name \(scope) ORDER BY schema_name")
        let tableRows = try await rawQuery("""
            SELECT table_schema, table_name, table_type FROM information_schema.tables
            WHERE table_schema \(scope) ORDER BY table_schema, table_name
            """)
        let columnRows = try await rawQuery("""
            SELECT table_schema, table_name, column_name, column_type, is_nullable, column_default,
                   ordinal_position, column_key, extra
            FROM information_schema.columns
            WHERE table_schema \(scope) ORDER BY table_schema, table_name, ordinal_position
            """)
        let indexRows = try await rawQuery("""
            SELECT table_schema, table_name, index_name, column_name, non_unique
            FROM information_schema.statistics
            WHERE table_schema \(scope) AND index_name != 'PRIMARY'
            ORDER BY table_schema, table_name, index_name, seq_in_index
            """)
        let fkRows = try await rawQuery("""
            SELECT table_schema, table_name, constraint_name, column_name,
                   referenced_table_schema, referenced_table_name, referenced_column_name
            FROM information_schema.key_column_usage
            WHERE table_schema \(scope) AND referenced_table_name IS NOT NULL
            ORDER BY table_schema, constraint_name, ordinal_position
            """)

        var colMap: [String: [DBColumnInfo]] = [:]
        for row in columnRows.rows {
            guard case .text(let s) = row[0], case .text(let t) = row[1], case .text(let name) = row[2] else { continue }
            var col = DBColumnInfo(name: name, typeName: str(row[3]) ?? "")
            col.isNullable = str(row[4])?.uppercased() == "YES"
            col.defaultValue = str(row[5])
            col.ordinal = Int(int(row[6]) ?? 0)
            col.isPrimaryKey = str(row[7]) == "PRI"
            col.isAutoIncrement = (str(row[8]) ?? "").contains("auto_increment")
            colMap[key(s, t), default: []].append(col)
        }
        var idxMap: [String: [String: DBIndexInfo]] = [:]
        for row in indexRows.rows {
            guard case .text(let s) = row[0], case .text(let t) = row[1],
                  case .text(let idx) = row[2], case .text(let c) = row[3] else { continue }
            let k = key(s, t)
            var info = idxMap[k]?[idx] ?? DBIndexInfo(name: idx, columns: [], isUnique: int(row[4]) == 0)
            info.columns.append(c)
            idxMap[k, default: [:]][idx] = info
        }
        var fkMap: [String: [String: DBForeignKeyInfo]] = [:]
        for row in fkRows.rows {
            guard case .text(let s) = row[0], case .text(let t) = row[1],
                  case .text(let name) = row[2], case .text(let c) = row[3] else { continue }
            let k = key(s, t)
            var fk = fkMap[k]?[name] ?? DBForeignKeyInfo(
                name: name, columns: [], referencedSchema: str(row[4]) ?? "",
                referencedTable: str(row[5]) ?? "", referencedColumns: [])
            fk.columns.append(c)
            if let rc = str(row[6]) { fk.referencedColumns.append(rc) }
            fkMap[k, default: [:]][name] = fk
        }

        var tablesBySchema: [String: [DBTableInfo]] = [:]
        for row in tableRows.rows {
            guard case .text(let s) = row[0], case .text(let name) = row[1] else { continue }
            let type = str(row[2]) ?? ""
            let k = key(s, name)
            var table = DBTableInfo(schema: s, name: name, kind: type.contains("VIEW") ? .view : .table)
            table.columns = colMap[k] ?? []
            table.indexes = (idxMap[k] ?? [:]).values.sorted { $0.name < $1.name }
            table.foreignKeys = (fkMap[k] ?? [:]).values.sorted { $0.name < $1.name }
            tablesBySchema[s, default: []].append(table)
        }

        var schemas: [DBSchemaInfo] = []
        for dbRow in dbRows.rows {
            guard case .text(let dbName) = dbRow[0] else { continue }
            var schema = DBSchemaInfo(name: dbName, isDefault: dbName == config.database)
            schema.tables = tablesBySchema[dbName] ?? []
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
        let raw = try await rawQuery("SHOW CREATE TABLE \(qualifiedName(schema: schema, table: table))")
        if let first = raw.rows.first, first.count >= 2, case .text(let sql) = first[1] {
            return sql + ";"
        }
        throw DriverError.queryFailed("No DDL returned")
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
        var metadata: MySQLQueryMetadata?
        let rows: [MySQLRow]
        do {
            rows = try await connection.simpleQuery(sql).get()
            _ = metadata // simpleQuery has no metadata callback; affected below
        } catch {
            throw DriverError.queryFailed(describe(error))
        }
        if let first = rows.first {
            raw.isResultSet = true
            for def in first.columnDefinitions {
                raw.columns.append(def.name)
                raw.columnTypes.append(String(describing: def.columnType))
            }
            for row in rows {
                raw.rows.append(row.columnDefinitions.map { def in
                    decode(row.column(def.name, table: def.table) ?? .null)
                })
            }
        } else {
            let head = sql.trimmingCharacters(in: .whitespacesAndNewlines).prefix(6).uppercased()
            if head.hasPrefix("SELECT") || head.hasPrefix("SHOW") || head.hasPrefix("WITH") {
                raw.isResultSet = true
            }
        }
        return raw
    }

    private func decode(_ data: MySQLData) -> DBValue {
        if data.buffer == nil { return .null }
        switch data.type {
        case .tiny, .short, .long, .int24, .longlong:
            if let v = data.int { return .int(Int64(v)) }
        case .float, .double:
            if let v = data.double { return .double(v) }
        case .decimal, .newdecimal:
            if let s = data.string { return .text(s) }
        case .timestamp, .datetime, .date, .time, .year:
            if let s = data.string { return .text(s) }
            if let d = data.date {
                let f = ISO8601DateFormatter()
                return .text(f.string(from: d))
            }
        case .blob, .tinyBlob, .mediumBlob, .longBlob:
            // Text columns also report as blob; prefer string when it decodes.
            if let s = data.string { return .text(s) }
            if var buf = data.buffer, let d = buf.readData(length: buf.readableBytes) { return .blob(d) }
        case .bit:
            if let v = data.int { return .int(Int64(v)) }
        default:
            break
        }
        if let s = data.string { return .text(s) }
        if var buf = data.buffer, let d = buf.readData(length: buf.readableBytes) { return .blob(d) }
        return .null
    }

    private func describe(_ error: Error) -> String {
        if let my = error as? MySQLError {
            return String(describing: my)
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
}
