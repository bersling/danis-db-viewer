import Foundation

/// Which DBMS a data source talks to.
enum DBKind: String, Codable, CaseIterable, Identifiable {
    case sqlite
    case postgres
    case mysql

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sqlite: return "SQLite"
        case .postgres: return "PostgreSQL"
        case .mysql: return "MySQL"
        }
    }

    var defaultPort: Int {
        switch self {
        case .sqlite: return 0
        case .postgres: return 5432
        case .mysql: return 3306
        }
    }
}

/// IntelliJ-style per-data-source color marker.
enum DataSourceColor: String, Codable, CaseIterable, Identifiable {
    case none, red, orange, yellow, green, blue, violet, gray

    var id: String { rawValue }
}

/// A configured data source ("connection") as shown in the explorer tree.
struct DataSourceConfig: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var kind: DBKind = .sqlite

    // Network DBMS
    var host: String = "localhost"
    var port: Int = 0
    var user: String = ""
    var database: String = ""
    // Password lives in the Keychain, keyed by `id`. Never serialized here.
    // Set only for "Test Connection" before the config is saved.
    var transientPassword: String? = nil

    // SQLite
    var filePath: String = ""

    var color: DataSourceColor = .none
    var comment: String = ""

    /// Password to use when connecting.
    var resolvedPassword: String { transientPassword ?? Keychain.password(for: id) }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, host, port, user, database, filePath, color, comment
    }

    var effectivePort: Int { port == 0 ? kind.defaultPort : port }

    /// Short subtitle like IntelliJ shows in the connection list.
    var summary: String {
        switch kind {
        case .sqlite:
            return filePath.isEmpty ? "no file" : (filePath as NSString).abbreviatingWithTildeInPath
        case .postgres, .mysql:
            let db = database.isEmpty ? "" : "/\(database)"
            return "\(user.isEmpty ? "" : "\(user)@")\(host):\(effectivePort)\(db)"
        }
    }

    static func newDefault(kind: DBKind) -> DataSourceConfig {
        var c = DataSourceConfig()
        c.kind = kind
        c.port = kind.defaultPort
        switch kind {
        case .sqlite: c.name = "SQLite"
        case .postgres:
            c.name = "PostgreSQL"
            c.user = "postgres"
            c.database = "postgres"
        case .mysql:
            c.name = "MySQL"
            c.user = "root"
        }
        return c
    }
}
