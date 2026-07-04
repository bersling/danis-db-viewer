import Foundation
import SwiftUI

/// What an editor tab shows.
enum TabContent: Equatable {
    case table(dataSource: DataSourceConfig, schema: String, table: String)
    case console(dataSource: DataSourceConfig, consoleNumber: Int)
    case ddl(dataSource: DataSourceConfig, schema: String, table: String)
}

final class EditorTab: ObservableObject, Identifiable, Equatable {
    let id = UUID()
    let content: TabContent
    @Published var isDirty = false

    init(content: TabContent) {
        self.content = content
    }

    var title: String {
        switch content {
        case .table(_, _, let table): return table
        case .console(let ds, let n): return n <= 1 ? "\(ds.name) console" : "\(ds.name) console [\(n)]"
        case .ddl(_, _, let table): return "\(table) DDL"
        }
    }

    var dataSource: DataSourceConfig {
        switch content {
        case .table(let ds, _, _), .console(let ds, _), .ddl(let ds, _, _): return ds
        }
    }

    static func == (l: EditorTab, r: EditorTab) -> Bool { l.id == r.id }
}

/// Open editor tabs, IntelliJ style.
@MainActor
final class TabManager: ObservableObject {
    @Published var tabs: [EditorTab] = []
    @Published var selectedTabID: UUID?

    var selectedTab: EditorTab? { tabs.first { $0.id == selectedTabID } }

    /// Open a table tab (reuse an existing one for the same table).
    func openTable(dataSource: DataSourceConfig, schema: String, table: String) {
        let content = TabContent.table(dataSource: dataSource, schema: schema, table: table)
        if let existing = tabs.first(where: { $0.content == content }) {
            selectedTabID = existing.id
            return
        }
        append(EditorTab(content: content))
    }

    /// Always opens a fresh console (IntelliJ numbers them).
    func openConsole(dataSource: DataSourceConfig) {
        let existing = tabs.filter {
            if case .console(let ds, _) = $0.content { return ds.id == dataSource.id }
            return false
        }.count
        append(EditorTab(content: .console(dataSource: dataSource, consoleNumber: existing + 1)))
    }

    func openDDL(dataSource: DataSourceConfig, schema: String, table: String) {
        let content = TabContent.ddl(dataSource: dataSource, schema: schema, table: table)
        if let existing = tabs.first(where: { $0.content == content }) {
            selectedTabID = existing.id
            return
        }
        append(EditorTab(content: content))
    }

    func close(_ tab: EditorTab) {
        guard let idx = tabs.firstIndex(of: tab) else { return }
        tabs.remove(at: idx)
        if selectedTabID == tab.id {
            selectedTabID = tabs.indices.contains(idx) ? tabs[idx].id : tabs.last?.id
        }
    }

    func closeSelected() {
        if let tab = selectedTab { close(tab) }
    }

    /// Close all tabs belonging to a removed data source.
    func closeAll(for dataSourceID: UUID) {
        tabs.removeAll { $0.dataSource.id == dataSourceID }
        if let sel = selectedTabID, !tabs.contains(where: { $0.id == sel }) {
            selectedTabID = tabs.last?.id
        }
    }

    private func append(_ tab: EditorTab) {
        tabs.append(tab)
        selectedTabID = tab.id
    }
}
