import AppKit
import SwiftUI

/// Query console: SQL editor on top, result tabs below — IntelliJ's console.
struct ConsoleView: View {
    @EnvironmentObject var sessions: SessionRegistry
    @EnvironmentObject var history: QueryHistoryStore
    @ObservedObject var tab: EditorTab

    let dataSource: DataSourceConfig

    @State private var sql = ""
    @State private var caret = 0
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var results: [QueryResult] = []
    @State private var selectedResultID: UUID?
    @State private var running = false
    @State private var showHistory = false

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                consoleToolbar
                Divider().overlay(Theme.border)
                SQLEditor(
                    text: $sql,
                    completion: completionContext,
                    onExecute: { runAtCaret() },
                    onCaretChange: { c, sel in
                        caret = c
                        selection = sel
                    }
                )
            }
            .frame(minHeight: 140)

            resultsArea
                .frame(minHeight: 120)
        }
        .background(Theme.editorBackground)
        .onChange(of: sql) { _, newValue in
            tab.isDirty = !newValue.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var completionContext: SQLCompletionContext {
        guard let intro = sessions.introspections[dataSource.id] else { return SQLCompletionContext() }
        var ctx = SQLCompletionContext()
        ctx.tableNames = intro.allTables.map(\.name)
        ctx.columnNames = Array(Set(intro.allTables.flatMap { $0.columns.map(\.name) })).sorted()
        return ctx
    }

    // MARK: - Toolbar

    private var consoleToolbar: some View {
        HStack(spacing: 10) {
            Button {
                runAtCaret()
            } label: {
                Image(systemName: "play.fill").foregroundStyle(.green)
            }
            .buttonStyle(.borderless)
            .disabled(running)
            .help(selection.length > 0 ? "Execute selection (⌘⏎)" : "Execute statement at caret (⌘⏎)")

            Button {
                runAll()
            } label: {
                Image(systemName: "forward.fill").foregroundStyle(.green)
            }
            .buttonStyle(.borderless)
            .disabled(running)
            .help("Execute whole script")

            if running {
                ProgressView().controlSize(.small)
            }

            Divider().frame(height: 16)

            Button {
                showHistory.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .help("Query history")
            .popover(isPresented: $showHistory, arrowEdge: .bottom) {
                HistoryPopover(dataSourceName: dataSource.name) { picked in
                    sql = sql.isEmpty ? picked : sql + "\n" + picked
                    showHistory = false
                }
            }

            Spacer()

            HStack(spacing: 4) {
                if let color = dataSource.color.swiftUIColor {
                    Circle().fill(color).frame(width: 7, height: 7)
                }
                Text("\(dataSource.name) · \(dataSource.kind.displayName)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dimText)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(Theme.toolWindowBackground)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsArea: some View {
        VStack(spacing: 0) {
            if results.isEmpty {
                Text("Results appear here — ⌘⏎ to run")
                    .font(Theme.uiFont)
                    .foregroundStyle(Theme.dimText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if results.count > 1 {
                    resultTabBar
                    Divider().overlay(Theme.border)
                }
                if let result = selectedResult {
                    ResultView(result: result, dataSource: dataSource)
                }
            }
        }
        .background(Theme.editorBackground)
    }

    private var selectedResult: QueryResult? {
        results.first { $0.id == selectedResultID } ?? results.first
    }

    private var resultTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { idx, result in
                    let isSelected = (selectedResult?.id == result.id)
                    HStack(spacing: 5) {
                        if result.error != nil {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9)).foregroundStyle(.red)
                        }
                        Text("Result \(idx + 1)")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(isSelected ? Theme.editorBackground : Theme.toolWindowBackground)
                    .overlay(alignment: .bottom) {
                        if isSelected { Rectangle().fill(Theme.accent).frame(height: 2) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedResultID = result.id }
                }
                Spacer()
            }
        }
        .frame(height: 24)
        .background(Theme.toolWindowBackground)
    }

    // MARK: - Execution

    private func runAtCaret() {
        let script: String
        if selection.length > 0 {
            script = (sql as NSString).substring(with: selection)
        } else if let stmt = SQLSplitter.statement(at: caret, in: sql) {
            script = stmt
        } else {
            return
        }
        run(script: script)
    }

    private func runAll() {
        run(script: sql)
    }

    private func run(script: String) {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !running else { return }
        running = true
        history.add(sql: trimmed, dataSourceName: dataSource.name)
        Task {
            defer { running = false }
            do {
                let driver = try await sessions.driver(for: dataSource)
                results = await driver.execute(script: trimmed)
                selectedResultID = results.first(where: { $0.error != nil })?.id ?? results.first?.id
                // DDL may have changed the schema — refresh the tree.
                if results.contains(where: { $0.affectedRows != nil && $0.error == nil }) {
                    await sessions.refreshIntrospection(for: dataSource)
                }
            } catch {
                results = [QueryResult(statement: trimmed, error: error.localizedDescription)]
                selectedResultID = results.first?.id
            }
        }
    }
}

// MARK: - Single result

/// One statement's outcome: grid for SELECTs, banner for DML/errors.
struct ResultView: View {
    let result: QueryResult
    let dataSource: DataSourceConfig

    var body: some View {
        VStack(spacing: 0) {
            if let error = result.error {
                VStack(alignment: .leading, spacing: 6) {
                    Label(error, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(Theme.monoFont)
                        .textSelection(.enabled)
                    Text(result.statement)
                        .font(Theme.monoFont)
                        .foregroundStyle(Theme.dimText)
                        .textSelection(.enabled)
                        .lineLimit(4)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if !result.isResultSet {
                Label(result.summary, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(Theme.uiFont)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ResultGrid(result: result)
            }
            Divider().overlay(Theme.border)
            HStack {
                Text(result.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dimText)
                Spacer()
                if result.isResultSet {
                    Menu {
                        Button("Copy as CSV") {
                            copyToPasteboard(Exporter.csv(columns: result.columns, rows: result.rows))
                        }
                        Button("Copy as JSON") {
                            copyToPasteboard(Exporter.json(columns: result.columns, rows: result.rows))
                        }
                        Button("Save as CSV…") { save(text: Exporter.csv(columns: result.columns, rows: result.rows), ext: "csv") }
                        Button("Save as JSON…") { save(text: Exporter.json(columns: result.columns, rows: result.rows), ext: "json") }
                    } label: {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 10))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 30)
                }
                Text(String(format: "%.0f ms", result.duration * 1000))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dimText)
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Theme.toolWindowBackground)
        }
    }

    private func save(text: String, ext: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "result.\(ext)"
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// Read-only grid for console results.
private struct ResultGrid: View {
    let result: QueryResult
    @State private var viewedValue: String?

    private let rowHeight: CGFloat = 22
    private let gutterWidth: CGFloat = 44

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("#")
                        .font(.system(size: 10)).foregroundStyle(Theme.dimText)
                        .frame(width: gutterWidth, height: rowHeight)
                        .background(Theme.toolWindowBackground)
                        .border(Theme.gridLine, width: 0.5)
                    ForEach(result.columns.indices, id: \.self) { col in
                        HStack(spacing: 3) {
                            Text(result.columns[col]).font(.system(size: 11, weight: .semibold))
                            Text(col < result.columnTypes.count ? result.columnTypes[col].lowercased() : "")
                                .font(.system(size: 9)).foregroundStyle(Theme.dimText)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6)
                        .frame(width: widths[col], height: rowHeight)
                        .background(Theme.toolWindowBackground)
                        .border(Theme.gridLine, width: 0.5)
                    }
                }
                LazyVStack(spacing: 0) {
                    ForEach(result.rows.indices, id: \.self) { row in
                        HStack(spacing: 0) {
                            Text("\(row + 1)")
                                .font(.system(size: 10)).foregroundStyle(Theme.dimText)
                                .frame(width: gutterWidth, height: rowHeight)
                                .background(Theme.toolWindowBackground)
                                .border(Theme.gridLine, width: 0.5)
                            ForEach(result.columns.indices, id: \.self) { col in
                                let value = result.rows[row][col]
                                (value.isNull
                                    ? Text("<null>").foregroundColor(Theme.nullText).italic()
                                    : Text(value.displayString))
                                    .font(Theme.monoFont)
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .frame(width: widths[col], height: rowHeight, alignment: .leading)
                                    .background(row % 2 == 1 ? Theme.gridStripe : .clear)
                                    .border(Theme.gridLine, width: 0.5)
                                    .contextMenu {
                                        Button("View Value") { viewedValue = value.displayString }
                                        Button("Copy Value") { copyToPasteboard(value.isNull ? "" : value.displayString) }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { viewedValue != nil }, set: { if !$0 { viewedValue = nil } })) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    Text(viewedValue ?? "")
                        .font(Theme.monoFont)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                HStack {
                    Button("Copy") { copyToPasteboard(viewedValue ?? "") }
                    Spacer()
                    Button("Close") { viewedValue = nil }.keyboardShortcut(.cancelAction)
                }
            }
            .padding(14)
            .frame(width: 520, height: 360)
        }
    }

    private var widths: [CGFloat] {
        let charWidth: CGFloat = 7.3
        return result.columns.indices.map { col in
            var maxLen = result.columns[col].count + 6
            for row in result.rows.prefix(60) where col < row.count {
                maxLen = max(maxLen, min(row[col].displayString.count, 60))
            }
            return min(max(CGFloat(maxLen) * charWidth + 16, 70), 460)
        }
    }
}

// MARK: - History

private struct HistoryPopover: View {
    @EnvironmentObject var history: QueryHistoryStore
    let dataSourceName: String
    let onPick: (String) -> Void

    @State private var filter = ""

    var body: some View {
        VStack(spacing: 6) {
            TextField("Filter history", text: $filter)
                .textFieldStyle(.roundedBorder)
            List(filtered) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.sql)
                        .font(Theme.monoFont)
                        .lineLimit(3)
                    Text("\(entry.dataSourceName) · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dimText)
                }
                .contentShape(Rectangle())
                .onTapGesture { onPick(entry.sql) }
            }
            .listStyle(.plain)
            HStack {
                Button("Clear History") { history.clear() }
                    .font(.system(size: 11))
                Spacer()
            }
        }
        .padding(10)
        .frame(width: 420, height: 320)
    }

    private var filtered: [QueryHistoryEntry] {
        let all = history.entries
        guard !filter.isEmpty else { return all }
        return all.filter { $0.sql.localizedCaseInsensitiveContains(filter) }
    }
}
