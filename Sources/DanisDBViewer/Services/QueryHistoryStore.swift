import Foundation

struct QueryHistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var dataSourceName: String
    var sql: String
    var date: Date
}

/// Persisted, capped query history (IntelliJ's console history).
@MainActor
final class QueryHistoryStore: ObservableObject {
    @Published private(set) var entries: [QueryHistoryEntry] = []
    private let maxEntries = 500

    private var fileURL: URL { AppPaths.supportDir.appendingPathComponent("history.json") }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([QueryHistoryEntry].self, from: data) {
            entries = list
        }
    }

    func add(sql: String, dataSourceName: String) {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Collapse consecutive duplicates like IntelliJ does.
        if entries.first?.sql == trimmed { return }
        entries.insert(QueryHistoryEntry(dataSourceName: dataSourceName, sql: trimmed, date: Date()), at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
