import SwiftUI
import UniformTypeIdentifiers

/// Which tree node is currently selected (IntelliJ: single-click selects,
/// double-click opens). Uses manual click timing because SwiftUI's stacked
/// count:1 / count:2 tap gestures conflict inside a DisclosureGroup label.
final class TreeSelection: ObservableObject {
    @Published var selectedID: String?
    private var lastClickID: String?
    private var lastClickAt = Date.distantPast

    /// Register a click on `id`; returns true if it's a double-click (open).
    func registerClick(_ id: String) -> Bool {
        let now = Date()
        let isDouble = (id == lastClickID) && now.timeIntervalSince(lastClickAt) < 0.5
        selectedID = id
        lastClickID = id
        lastClickAt = now
        return isDouble
    }
}

/// The Database tool window: data source tree with speed search, toolbar,
/// context menus.
struct ExplorerView: View {
    @EnvironmentObject var connectionStore: ConnectionStore
    @EnvironmentObject var sessions: SessionRegistry
    @EnvironmentObject var tabs: TabManager
    @StateObject private var selection = TreeSelection()

    @State private var searchText = ""
    @State private var editorTarget: DataSourceConfig?
    @State private var showingNewMenu = false
    @State private var confirmDrop: (config: DataSourceConfig, table: DBTableInfo)?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Theme.border)
            searchField
            List {
                ForEach(filteredConnections) { config in
                    DataSourceNode(
                        config: config,
                        searchText: searchText,
                        onEdit: { editorTarget = config },
                        onDropTable: { table in confirmDrop = (config, table) }
                    )
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 22)
            .environmentObject(selection)

            if connectionStore.connections.isEmpty {
                emptyHint
            }
        }
        .background(Theme.toolWindowBackground)
        .sheet(item: $editorTarget) { target in
            DataSourceDialog(config: target)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newDataSource)) { note in
            if let kind = note.object as? DBKind {
                editorTarget = DataSourceConfig.newDefault(kind: kind)
            }
        }
        .confirmationDialog(
            "Drop table \(confirmDrop?.table.name ?? "")?",
            isPresented: Binding(get: { confirmDrop != nil }, set: { if !$0 { confirmDrop = nil } })
        ) {
            Button("Drop", role: .destructive) {
                if let (config, table) = confirmDrop { dropTable(config: config, table: table) }
                confirmDrop = nil
            }
        } message: {
            Text("This permanently deletes the table and its data.")
        }
    }

    private var filteredConnections: [DataSourceConfig] {
        connectionStore.connections
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(DBKind.allCases) { kind in
                    Button(kind.displayName) {
                        editorTarget = DataSourceConfig.newDefault(kind: kind)
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 30, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30, height: 24)
            .help("New Data Source")

            Button {
                Task {
                    for config in connectionStore.connections where sessions.isConnected(config.id) {
                        await sessions.refreshIntrospection(for: config)
                    }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.icon)
            .help("Refresh connected data sources (F5)")
            .keyboardShortcut(.init("r"), modifiers: [.command, .shift])

            Spacer()
            Text("Database")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dimText)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(Theme.dimText)
            TextField("Search objects", text: $searchText)
                .textFieldStyle(.plain)
                .font(Theme.uiFont)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Theme.toolWindowBackground)
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Text("No data sources")
                .foregroundStyle(Theme.dimText)
            Text("Click + to add SQLite, PostgreSQL or MySQL")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dimText)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }

    private func dropTable(config: DataSourceConfig, table: DBTableInfo) {
        Task {
            if let driver = try? await sessions.driver(for: config) {
                let name = driver.qualifiedName(schema: table.schema, table: table.name)
                _ = await driver.execute(script: "DROP \(table.kind == .view ? "VIEW" : "TABLE") \(name)")
                await sessions.refreshIntrospection(for: config)
                tabs.tabs.filter {
                    if case .table(let ds, let s, let t) = $0.content {
                        return ds.id == config.id && s == table.schema && t == table.name
                    }
                    return false
                }.forEach { tabs.close($0) }
            }
        }
    }
}

// MARK: - Data source node

private struct DataSourceNode: View {
    @EnvironmentObject var connectionStore: ConnectionStore
    @EnvironmentObject var sessions: SessionRegistry
    @EnvironmentObject var tabs: TabManager

    let config: DataSourceConfig
    let searchText: String
    let onEdit: () -> Void
    let onDropTable: (DBTableInfo) -> Void

    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if sessions.connecting.contains(config.id) {
                Label { Text("Connecting…").foregroundStyle(Theme.dimText) } icon: {
                    ProgressView().controlSize(.mini)
                }
            } else if let error = sessions.errors[config.id] {
                Label {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                }
            } else if let intro = sessions.introspections[config.id] {
                ForEach(visibleSchemas(intro)) { schema in
                    SchemaNode(config: config, schema: schema, searchText: searchText, onDropTable: onDropTable)
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let color = config.color.swiftUIColor {
                    RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 14)
                }
                Image(systemName: ObjectIcon.dataSource(config.kind))
                    .foregroundStyle(sessions.isConnected(config.id) ? Color.green : Theme.dimText)
                    .font(.system(size: 11))
                Text(config.name).font(Theme.uiFont)
                Text(config.kind.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dimText)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { expanded.toggle() }
            .help("\(config.kind.displayName) data source" + (sessions.isConnected(config.id) ? " (connected)" : "") + " — click to expand")
        }
        .onChange(of: expanded) { _, isOpen in
            if isOpen && sessions.introspections[config.id] == nil {
                Task { await sessions.refreshIntrospection(for: config) }
            }
        }
        .contextMenu {
            Button("New Query Console") { tabs.openConsole(dataSource: config) }
            Divider()
            Button("Refresh") { Task { await sessions.refreshIntrospection(for: config) } }
            Button(sessions.isConnected(config.id) ? "Disconnect" : "Connect") {
                Task {
                    if sessions.isConnected(config.id) {
                        await sessions.disconnect(config.id)
                        expanded = false
                    } else {
                        await sessions.refreshIntrospection(for: config)
                    }
                }
            }
            Divider()
            Button("Properties…") { onEdit() }
            Button("Duplicate") { _ = connectionStore.duplicate(config.id) }
            Menu("Color") {
                ForEach(DataSourceColor.allCases) { c in
                    Button(c.rawValue.capitalized) {
                        var updated = config
                        updated.color = c
                        connectionStore.upsert(updated, password: nil)
                    }
                }
            }
            Divider()
            Button("Copy Name") { copyToPasteboard(config.name) }
            Button("Remove", role: .destructive) {
                tabs.closeAll(for: config.id)
                Task { await sessions.disconnect(config.id) }
                connectionStore.remove(config.id)
            }
        }
    }

    /// Hide schemas with no matches while searching.
    private func visibleSchemas(_ intro: DBIntrospection) -> [DBSchemaInfo] {
        guard !searchText.isEmpty else { return intro.schemas }
        return intro.schemas.compactMap { schema in
            var s = schema
            s.tables = schema.tables.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            return s.tables.isEmpty ? nil : s
        }
    }
}

// MARK: - Schema / table / column nodes

private struct SchemaNode: View {
    @EnvironmentObject var tabs: TabManager

    let config: DataSourceConfig
    let schema: DBSchemaInfo
    let searchText: String
    let onDropTable: (DBTableInfo) -> Void

    @State private var expanded: Bool

    init(config: DataSourceConfig, schema: DBSchemaInfo, searchText: String, onDropTable: @escaping (DBTableInfo) -> Void) {
        self.config = config
        self.schema = schema
        self.searchText = searchText
        self.onDropTable = onDropTable
        _expanded = State(initialValue: schema.isDefault || !searchText.isEmpty)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(schema.tables) { table in
                TableNode(config: config, table: table, onDropTable: onDropTable)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: ObjectIcon.schema)
                    .foregroundStyle(Color(red: 0.55, green: 0.65, blue: 0.85))
                    .font(.system(size: 11))
                Text(schema.name).font(Theme.uiFont)
                Text("\(schema.tables.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dimText)
            }
            .help("Schema “\(schema.name)” — \(schema.tables.count) tables/views")
        }
    }
}

private struct TableNode: View {
    @EnvironmentObject var tabs: TabManager
    @EnvironmentObject var selection: TreeSelection

    let config: DataSourceConfig
    let table: DBTableInfo
    let onDropTable: (DBTableInfo) -> Void

    @State private var expanded = false

    private var nodeID: String { "\(config.id)/\(table.schema).\(table.name)" }
    private var isSelected: Bool { selection.selectedID == nodeID }

    private func open() {
        selection.selectedID = nodeID
        tabs.openTable(dataSource: config, schema: table.schema, table: table.name)
    }

    var body: some View {
        // Custom expandable row (not DisclosureGroup) so the label's tap is ours:
        // chevron expands, label single-click selects, double-click opens.
        VStack(alignment: .leading, spacing: 0) {
            row
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(table.columns) { col in
                        ColumnRow(column: col, foreignKeys: table.foreignKeys)
                    }
                    ForEach(table.indexes) { idx in
                        HStack(spacing: 5) {
                            Image(systemName: ObjectIcon.index)
                                .font(.system(size: 10)).foregroundStyle(Theme.dimText)
                            Text(idx.name).font(Theme.uiFont)
                            Text(idx.isUnique ? "unique (\(idx.columns.joined(separator: ", ")))" : "(\(idx.columns.joined(separator: ", ")))")
                                .font(.system(size: 10)).foregroundStyle(Theme.dimText)
                        }
                    }
                    ForEach(table.foreignKeys) { fk in
                        HStack(spacing: 5) {
                            Image(systemName: ObjectIcon.foreignKey)
                                .font(.system(size: 10)).foregroundStyle(Color(red: 0.55, green: 0.65, blue: 0.85))
                            Text("\(fk.columns.joined(separator: ",")) → \(fk.referencedTable)(\(fk.referencedColumns.joined(separator: ",")))")
                                .font(.system(size: 11))
                        }
                    }
                }
                .padding(.leading, 18)
            }
        }
    }

    private var row: some View {
        HStack(spacing: 5) {
            Button {
                expanded.toggle()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dimText)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Button (not onTapGesture) so clicks fire reliably inside the List.
            // Manual timing: first click selects, second within 0.5s opens.
            Button {
                if selection.registerClick(nodeID) {
                    tabs.openTable(dataSource: config, schema: table.schema, table: table.name)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: table.kind == .view ? ObjectIcon.view : ObjectIcon.table)
                        .foregroundStyle(table.kind == .view ? Color(red: 0.65, green: 0.55, blue: 0.85) : Color(red: 0.75, green: 0.68, blue: 0.40))
                        .font(.system(size: 11))
                    Text(table.name).font(Theme.uiFont)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(table.kind == .view ? "View" : "Table") “\(table.name)” — double-click to open, single-click to select")
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Theme.selection : .clear)
        )
        .contextMenu {
            Button("Open Table") { open() }
            Button("Go to DDL") {
                tabs.openDDL(dataSource: config, schema: table.schema, table: table.name)
            }
            Divider()
            Button("Copy Name") { copyToPasteboard(table.name) }
            Button("Copy Qualified Name") { copyToPasteboard("\(table.schema).\(table.name)") }
            Divider()
            if table.kind != .view {
                Button("Drop Table…", role: .destructive) { onDropTable(table) }
            } else {
                Button("Drop View…", role: .destructive) { onDropTable(table) }
            }
        }
    }
}

private struct ColumnRow: View {
    let column: DBColumnInfo
    let foreignKeys: [DBForeignKeyInfo]

    private var isFK: Bool { foreignKeys.contains { $0.columns.contains(column.name) } }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: column.isPrimaryKey ? ObjectIcon.primaryKey : (isFK ? ObjectIcon.foreignKey : ObjectIcon.column))
                .font(.system(size: 10))
                .foregroundStyle(column.isPrimaryKey ? Color(red: 0.85, green: 0.73, blue: 0.34)
                                 : (isFK ? Color(red: 0.55, green: 0.65, blue: 0.85) : Theme.dimText))
            Text(column.name).font(Theme.uiFont)
            Text(columnDetail)
                .font(.system(size: 10))
                .foregroundStyle(Theme.dimText)
                .lineLimit(1)
        }
        .help(columnHelp)
        .contextMenu {
            Button("Copy Name") { copyToPasteboard(column.name) }
        }
    }

    private var columnHelp: String {
        var parts = ["Column “\(column.name)” · \(column.typeName.lowercased())"]
        if column.isPrimaryKey { parts.append("primary key") }
        if isFK { parts.append("foreign key") }
        parts.append(column.isNullable ? "nullable" : "not null")
        if column.isAutoIncrement { parts.append("auto-increment") }
        return parts.joined(separator: " · ")
    }

    private var columnDetail: String {
        var parts = [column.typeName.lowercased()]
        if !column.isNullable { parts.append("not null") }
        if column.isAutoIncrement { parts.append("auto") }
        return parts.joined(separator: " · ")
    }
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
