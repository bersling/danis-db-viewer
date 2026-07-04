import Foundation

/// Live driver instances + cached introspection per data source.
@MainActor
final class SessionRegistry: ObservableObject {
    @Published private(set) var introspections: [UUID: DBIntrospection] = [:]
    @Published private(set) var connecting: Set<UUID> = []
    @Published private(set) var errors: [UUID: String] = [:]

    private var drivers: [UUID: DatabaseDriver] = [:]

    nonisolated static func makeDriver(for config: DataSourceConfig) -> DatabaseDriver {
        switch config.kind {
        case .sqlite: return SQLiteDriver(config: config)
        case .postgres: return PostgresDriver(config: config)
        case .mysql: return MySQLDriver(config: config)
        }
    }

    func isConnected(_ id: UUID) -> Bool { drivers[id] != nil }

    /// Existing driver or connect a new one.
    func driver(for config: DataSourceConfig) async throws -> DatabaseDriver {
        if let d = drivers[config.id] { return d }
        let d = Self.makeDriver(for: config)
        connecting.insert(config.id)
        defer { connecting.remove(config.id) }
        do {
            try await d.connect()
            drivers[config.id] = d
            errors[config.id] = nil
            return d
        } catch {
            errors[config.id] = error.localizedDescription
            throw error
        }
    }

    /// Connect (if needed) and refresh the schema tree.
    @discardableResult
    func refreshIntrospection(for config: DataSourceConfig) async -> DBIntrospection? {
        do {
            let d = try await driver(for: config)
            let intro = try await d.introspect()
            introspections[config.id] = intro
            errors[config.id] = nil
            return intro
        } catch {
            errors[config.id] = error.localizedDescription
            return nil
        }
    }

    func disconnect(_ id: UUID) async {
        if let d = drivers.removeValue(forKey: id) {
            await d.close()
        }
        introspections[id] = nil
    }

    /// One-off connectivity test with a throwaway driver. Returns nil on success.
    nonisolated static func test(config: DataSourceConfig, password: String) async -> String? {
        var cfg = config
        cfg.transientPassword = password
        let driver = makeDriver(for: cfg)
        do {
            try await driver.connect()
            await driver.close()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
