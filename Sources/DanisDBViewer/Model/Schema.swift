import Foundation

/// Introspected structure of one data source.
struct DBIntrospection: Equatable {
    var schemas: [DBSchemaInfo] = []

    var allTables: [DBTableInfo] { schemas.flatMap(\.tables) }
}

/// A namespace: schema (Postgres), database (MySQL), or "main" (SQLite).
struct DBSchemaInfo: Equatable, Identifiable {
    var name: String
    var isDefault: Bool = false
    var tables: [DBTableInfo] = []

    var id: String { name }
}

enum DBTableKind: String, Equatable {
    case table
    case view
    case systemTable
}

struct DBTableInfo: Equatable, Identifiable, Hashable {
    var schema: String
    var name: String
    var kind: DBTableKind = .table
    var columns: [DBColumnInfo] = []
    var indexes: [DBIndexInfo] = []
    var foreignKeys: [DBForeignKeyInfo] = []

    var id: String { "\(schema).\(name)" }

    var primaryKeyColumns: [String] { columns.filter(\.isPrimaryKey).map(\.name) }

    static func == (l: DBTableInfo, r: DBTableInfo) -> Bool {
        l.schema == r.schema && l.name == r.name && l.kind == r.kind
            && l.columns == r.columns && l.indexes == r.indexes && l.foreignKeys == r.foreignKeys
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(schema)
        hasher.combine(name)
    }
}

struct DBColumnInfo: Equatable, Identifiable, Hashable {
    var name: String
    var typeName: String
    var isNullable: Bool = true
    var isPrimaryKey: Bool = false
    var isAutoIncrement: Bool = false
    var defaultValue: String? = nil
    var ordinal: Int = 0

    var id: String { name }
}

struct DBIndexInfo: Equatable, Identifiable, Hashable {
    var name: String
    var columns: [String]
    var isUnique: Bool = false

    var id: String { name }
}

struct DBForeignKeyInfo: Equatable, Identifiable, Hashable {
    var name: String
    var columns: [String]
    var referencedSchema: String
    var referencedTable: String
    var referencedColumns: [String]

    var id: String { name + columns.joined(separator: ",") }
}

/// One executed statement's outcome.
struct QueryResult: Identifiable {
    let id = UUID()
    var statement: String
    var columns: [String] = []
    var columnTypes: [String] = []
    var rows: [[DBValue]] = []
    var affectedRows: Int? = nil   // set for DML/DDL instead of rows
    var duration: TimeInterval = 0
    var error: String? = nil

    var isResultSet: Bool { error == nil && affectedRows == nil }

    /// Short label for the result tab, like IntelliJ's "Result 1".
    var summary: String {
        if let error { return "Error: \(error)" }
        if let affectedRows { return "\(affectedRows) row\(affectedRows == 1 ? "" : "s") affected" }
        return "\(rows.count) row\(rows.count == 1 ? "" : "s") fetched"
    }
}
