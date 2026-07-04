import SwiftUI

/// Right side: IntelliJ-style editor tab bar + active tab content.
struct EditorAreaView: View {
    @EnvironmentObject var tabs: TabManager

    var body: some View {
        VStack(spacing: 0) {
            if tabs.tabs.isEmpty {
                emptyState
            } else {
                tabBar
                Divider().overlay(Theme.border)
                ZStack {
                    // Keep every tab's view alive so grids/consoles don't lose
                    // state when switching tabs (IntelliJ behavior).
                    ForEach(tabs.tabs) { tab in
                        TabContentView(tab: tab)
                            .opacity(tab.id == tabs.selectedTabID ? 1 : 0)
                            .allowsHitTesting(tab.id == tabs.selectedTabID)
                    }
                }
            }
        }
        .background(Theme.editorBackground)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 40))
                .foregroundStyle(Theme.dimText.opacity(0.5))
            Text("Open a table from the tree, or a query console\n(right-click a data source → New Query Console)")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.dimText)
                .font(Theme.uiFont)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs.tabs) { tab in
                    TabButton(tab: tab, isSelected: tab.id == tabs.selectedTabID)
                }
            }
        }
        .frame(height: 30)
        .background(Theme.toolWindowBackground)
    }
}

private struct TabButton: View {
    @EnvironmentObject var tabs: TabManager
    @ObservedObject var tab: EditorTab
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        // Whole tab is a Button (reliable); close (×) overlaid on the right.
        Button {
            tabs.selectedTabID = tab.id
        } label: {
            HStack(spacing: 6) {
                if let color = tab.dataSource.color.swiftUIColor {
                    RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 12)
                }
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dimText)
                Text(tab.title)
                    .font(Theme.uiFont)
                    .lineLimit(1)
                if tab.isDirty {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                }
                Color.clear.frame(width: 18, height: 18)   // room for the × button
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Theme.editorBackground : (hovering ? Color.white.opacity(0.04) : .clear))
        .overlay(alignment: .bottom) {
            if isSelected { Rectangle().fill(Theme.accent).frame(height: 2) }
        }
        .overlay(alignment: .trailing) {
            Button {
                tabs.close(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(hovering || isSelected ? Theme.text : .clear)
                    .frame(width: 20, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close tab")
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Close") { tabs.close(tab) }
            Button("Close Others") {
                tabs.tabs.filter { $0 != tab }.forEach { tabs.close($0) }
                tabs.selectedTabID = tab.id
            }
            Button("Close All") { tabs.tabs.forEach { tabs.close($0) } }
        }
    }

    private var icon: String {
        switch tab.content {
        case .table: return ObjectIcon.table
        case .console: return ObjectIcon.console
        case .ddl: return "doc.text"
        }
    }
}

/// Dispatch to the concrete editor for a tab.
private struct TabContentView: View {
    let tab: EditorTab

    var body: some View {
        switch tab.content {
        case .table(let ds, let schema, let table):
            TableEditorView(tab: tab, dataSource: ds, schema: schema, table: table)
        case .console(let ds, _):
            ConsoleView(tab: tab, dataSource: ds)
        case .ddl(let ds, let schema, let table):
            DDLView(dataSource: ds, schema: schema, table: table)
        }
    }
}
