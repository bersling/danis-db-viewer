import SwiftUI
import UniformTypeIdentifiers

/// Which tree node is currently selected (IntelliJ: single-click selects,
/// double-click opens). Manual click timing distinguishes the two.
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

private enum Tree {
    static let rowHeight: CGFloat = 24
    static let indent: CGFloat = 14
}

/// One tree row: full-width, fixed-height, entirely clickable (no dead gaps).
/// Built on ScrollView/VStack rather than List so we control every pixel —
/// List swallowed custom taps and imposed its own row spacing.
private struct TreeRow<Trailing: View, Menu: View>: View {
    var level: Int
    var expandable: Bool = false
    var expanded: Bool = false
    var icon: String
    var iconColor: Color
    var label: String
    var labelColor: Color = Theme.text
    var stripe: Color? = nil
    var selected: Bool = false
    var help: String = ""
    var onToggle: () -> Void = {}
    var onTap: () -> Void = {}
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var menu: () -> Menu

    var body: some View {
        // The whole row is a Button (Buttons fire reliably; onTapGesture is
        // flaky inside scrolling containers). The chevron is a separate Button
        // overlaid on top of its glyph so it toggles instead of selecting.
        Button(action: onTap) {
            HStack(spacing: 5) {
                Color.clear.frame(width: CGFloat(level) * Tree.indent, height: 1)
                Group {
                    if expandable {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.dimText)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .frame(width: 12)
                if let stripe {
                    RoundedRectangle(cornerRadius: 1.5).fill(stripe).frame(width: 3, height: 14)
                }
                Image(systemName: icon).foregroundStyle(iconColor).font(.system(size: 11))
                Text(label).font(Theme.uiFont).foregroundStyle(labelColor)
                trailing()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: Tree.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? Theme.selection : Color.clear)
        .overlay(alignment: .leading) {
            if expandable {
                Button(action: onToggle) {
                    Color.clear.frame(width: 22, height: Tree.rowHeight).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, CGFloat(level) * Tree.indent)
            }
        }
        .help(help)
        .contextMenu { menu() }
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
    @State private var confirmDrop: (config: DataSourceConfig, table: DBTableInfo)?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Theme.border)
            searchField
            Divider().overlay(Theme.border)
            if connectionStore.connections.isEmpty {
                emptyHint
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredConnections) { config in
                            DataSourceNode(
                                config: config,
                                searchText: searchText,
                                onEdit: { editorTarget = config },
                                onDropTable: { table in confirmDrop = (config, table) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .environmentObject(selection)
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
            Spacer()
            Text("No data sources")
                .foregroundStyle(Theme.dimText)
            Text("Click + to add SQLite, PostgreSQL or MySQL")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dimText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @EnvironmentObject var selection: TreeSelection

    let config: DataSourceConfig
    let searchText: String
    let onEdit: () -> Void
    let onDropTable: (DBTableInfo) -> Void

    @State private var expanded = false
    private var nodeID: String { "ds/\(config.id)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TreeRow(
                level: 0, expandable: true, expanded: expanded,
                icon: ObjectIcon.dataSource(config.kind),
                iconColor: sessions.isConnected(config.id) ? .green : Theme.dimText,
                label: config.name,
                stripe: config.color.swiftUIColor,
                selected: selection.selectedID == nodeID,
                help: "\(config.kind.displayName) data source" + (sessions.isConnected(config.id) ? " (connected)" : "") + " — click to expand",
                onToggle: toggle,
                onTap: { selection.selectedID = nodeID; toggle() },
                trailing: {
                    Text(config.kind.displayName).font(.system(size: 10)).foregroundStyle(Theme.dimText)
                },
                menu: { menu }
            )
            if expanded { children }
        }
    }

    @ViewBuilder private var children: some View {
        if sessions.connecting.contains(config.id) {
            HStack(spacing: 6) {
                Color.clear.frame(width: Tree.indent, height: 1)
                ProgressView().controlSize(.mini)
                Text("Connecting…").foregroundStyle(Theme.dimText).font(Theme.uiFont)
            }
            .frame(height: Tree.rowHeight)
            .padding(.horizontal, 6)
        } else if let error = sessions.errors[config.id] {
            HStack(alignment: .top, spacing: 6) {
                Color.clear.frame(width: Tree.indent, height: 1)
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.red).font(.system(size: 11))
                Text(error)
                    .foregroundStyle(.red).font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
        } else if let intro = sessions.introspections[config.id] {
            ForEach(visibleSchemas(intro)) { schema in
                SchemaNode(config: config, schema: schema, searchText: searchText, onDropTable: onDropTable)
            }
        }
    }

    private func toggle() {
        expanded.toggle()
        if expanded && sessions.introspections[config.id] == nil {
            Task { await sessions.refreshIntrospection(for: config) }
        }
    }

    @ViewBuilder private var menu: some View {
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

// MARK: - Schema node

private struct SchemaNode: View {
    @EnvironmentObject var selection: TreeSelection

    let config: DataSourceConfig
    let schema: DBSchemaInfo
    let searchText: String
    let onDropTable: (DBTableInfo) -> Void

    @State private var expanded: Bool
    private var nodeID: String { "schema/\(config.id)/\(schema.name)" }

    init(config: DataSourceConfig, schema: DBSchemaInfo, searchText: String, onDropTable: @escaping (DBTableInfo) -> Void) {
        self.config = config
        self.schema = schema
        self.searchText = searchText
        self.onDropTable = onDropTable
        _expanded = State(initialValue: schema.isDefault || !searchText.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TreeRow(
                level: 1, expandable: true, expanded: expanded,
                icon: ObjectIcon.schema,
                iconColor: Color(red: 0.55, green: 0.65, blue: 0.85),
                label: schema.name,
                selected: selection.selectedID == nodeID,
                help: "Schema “\(schema.name)” — \(schema.tables.count) tables/views",
                onToggle: { expanded.toggle() },
                onTap: { selection.selectedID = nodeID; expanded.toggle() },
                trailing: {
                    Text("\(schema.tables.count)").font(.system(size: 10)).foregroundStyle(Theme.dimText)
                },
                menu: { EmptyView() }
            )
            if expanded {
                ForEach(schema.tables) { table in
                    TableNode(config: config, table: table, onDropTable: onDropTable)
                }
            }
        }
    }
}

// MARK: - Table node

private struct TableNode: View {
    @EnvironmentObject var tabs: TabManager
    @EnvironmentObject var selection: TreeSelection

    let config: DataSourceConfig
    let table: DBTableInfo
    let onDropTable: (DBTableInfo) -> Void

    @State private var expanded = false
    private var nodeID: String { "\(config.id)/\(table.schema).\(table.name)" }

    private func open() {
        selection.selectedID = nodeID
        tabs.openTable(dataSource: config, schema: table.schema, table: table.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TreeRow(
                level: 2, expandable: true, expanded: expanded,
                icon: table.kind == .view ? ObjectIcon.view : ObjectIcon.table,
                iconColor: table.kind == .view ? Color(red: 0.65, green: 0.55, blue: 0.85) : Color(red: 0.75, green: 0.68, blue: 0.40),
                label: table.name,
                selected: selection.selectedID == nodeID,
                help: "\(table.kind == .view ? "View" : "Table") “\(table.name)” — double-click to open, single-click to select",
                onToggle: { expanded.toggle() },
                onTap: {
                    if selection.registerClick(nodeID) {
                        tabs.openTable(dataSource: config, schema: table.schema, table: table.name)
                    }
                },
                trailing: { EmptyView() },
                menu: { menu }
            )
            if expanded { details }
        }
    }

    @ViewBuilder private var details: some View {
        ForEach(table.columns) { col in
            ColumnRow(column: col, foreignKeys: table.foreignKeys)
        }
        ForEach(table.indexes) { idx in
            TreeRow(
                level: 3, icon: ObjectIcon.index, iconColor: Theme.dimText,
                label: idx.name,
                help: "Index on \(idx.columns.joined(separator: ", "))\(idx.isUnique ? " (unique)" : "")",
                trailing: {
                    Text(idx.isUnique ? "unique (\(idx.columns.joined(separator: ", ")))" : "(\(idx.columns.joined(separator: ", ")))")
                        .font(.system(size: 10)).foregroundStyle(Theme.dimText).lineLimit(1)
                },
                menu: { EmptyView() }
            )
        }
        ForEach(table.foreignKeys) { fk in
            TreeRow(
                level: 3, icon: ObjectIcon.foreignKey, iconColor: Color(red: 0.55, green: 0.65, blue: 0.85),
                label: fk.columns.joined(separator: ","),
                help: "Foreign key → \(fk.referencedTable)(\(fk.referencedColumns.joined(separator: ", ")))",
                trailing: {
                    Text("→ \(fk.referencedTable)(\(fk.referencedColumns.joined(separator: ",")))")
                        .font(.system(size: 10)).foregroundStyle(Theme.dimText).lineLimit(1)
                },
                menu: { EmptyView() }
            )
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Open Table") { open() }
        Button("Go to DDL") { tabs.openDDL(dataSource: config, schema: table.schema, table: table.name) }
        Divider()
        Button("Copy Name") { copyToPasteboard(table.name) }
        Button("Copy Qualified Name") { copyToPasteboard("\(table.schema).\(table.name)") }
        Divider()
        Button(table.kind == .view ? "Drop View…" : "Drop Table…", role: .destructive) { onDropTable(table) }
    }
}

// MARK: - Column row

private struct ColumnRow: View {
    let column: DBColumnInfo
    let foreignKeys: [DBForeignKeyInfo]

    private var isFK: Bool { foreignKeys.contains { $0.columns.contains(column.name) } }

    var body: some View {
        TreeRow(
            level: 3,
            icon: column.isPrimaryKey ? ObjectIcon.primaryKey : (isFK ? ObjectIcon.foreignKey : ObjectIcon.column),
            iconColor: column.isPrimaryKey ? Color(red: 0.85, green: 0.73, blue: 0.34)
                       : (isFK ? Color(red: 0.55, green: 0.65, blue: 0.85) : Theme.dimText),
            label: column.name,
            help: columnHelp,
            trailing: {
                Text(columnDetail).font(.system(size: 10)).foregroundStyle(Theme.dimText).lineLimit(1)
            },
            menu: { Button("Copy Name") { copyToPasteboard(column.name) } }
        )
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
