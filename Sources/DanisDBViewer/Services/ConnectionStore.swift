import Foundation
import SwiftUI

/// App support directory for persisted state.
enum AppPaths {
    static var supportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DanisDBViewer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// Persisted list of configured data sources.
@MainActor
final class ConnectionStore: ObservableObject {
    @Published private(set) var connections: [DataSourceConfig] = []

    private var fileURL: URL { AppPaths.supportDir.appendingPathComponent("connections.json") }

    init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([DataSourceConfig].self, from: data) else { return }
        connections = list
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(connections) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func upsert(_ config: DataSourceConfig, password: String?) {
        if let idx = connections.firstIndex(where: { $0.id == config.id }) {
            connections[idx] = config
        } else {
            connections.append(config)
        }
        if let password {
            Keychain.setPassword(password, for: config.id)
        }
        save()
    }

    func remove(_ id: UUID) {
        connections.removeAll { $0.id == id }
        Keychain.deletePassword(for: id)
        save()
    }

    func duplicate(_ id: UUID) -> DataSourceConfig? {
        guard let original = connections.first(where: { $0.id == id }) else { return nil }
        var copy = original
        copy.id = UUID()
        copy.name = original.name + " [copy]"
        connections.append(copy)
        Keychain.setPassword(Keychain.password(for: id), for: copy.id)
        save()
        return copy
    }
}

extension DataSourceColor {
    var swiftUIColor: Color? {
        switch self {
        case .none: return nil
        case .red: return Color(red: 0.86, green: 0.35, blue: 0.35)
        case .orange: return Color(red: 0.91, green: 0.60, blue: 0.29)
        case .yellow: return Color(red: 0.89, green: 0.79, blue: 0.37)
        case .green: return Color(red: 0.45, green: 0.72, blue: 0.42)
        case .blue: return Color(red: 0.35, green: 0.58, blue: 0.85)
        case .violet: return Color(red: 0.65, green: 0.48, blue: 0.85)
        case .gray: return Color(white: 0.55)
        }
    }
}
