import AppKit
import SwiftUI

/// A table opened for data editing: filter row, paginated grid with staged
/// edits, paging toolbar, status bar. IntelliJ's table editor.
struct TableEditorView: View {
    @EnvironmentObject var sessions: SessionRegistry
    @ObservedObject var tab: EditorTab

    @StateObject private var model: TableGridModel
    @State private var selectedRows: Set<Int> = []
    @State private var whereDraft = ""
    @State private var transposed = false
    @State private var viewedValue: String?
    @State private var showStructure = ProcessInfo.processInfo.environment["DANIS_STRUCTURE"] == "1"

    init(tab: EditorTab, dataSource: DataSourceConfig, schema: String, table: String) {
        self.tab = tab
        // StateObject init with external deps: standard pattern.
        _model = StateObject(wrappedValue: TableGridModel(
            dataSource: dataSource, schema: schema, table: table,
            sessions: AppServices.shared.sessions))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Theme.border)
            filterBar
            Divider().overlay(Theme.border)

            if let error = model.error {
                errorBanner(error)
            }

            if model.loading && model.rows.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if showStructure, let info = model.tableInfo {
                StructureView(info: info)
            } else if transposed {
                TransposedView(model: model, selectedRows: $selectedRows)
            } else {
                DataGridView(model: model, selectedRows: $selectedRows, viewedValue: $viewedValue)
            }

            Divider().overlay(Theme.border)
            statusBar
        }
        .background(Theme.editorBackground)
        .task {
            if model.rows.isEmpty && model.error == nil {
                await model.load()
            }
        }
        .onAppear {
            model.onDirtyChange = { tab.isDirty = $0 }
        }
        .sheet(isPresented: Binding(get: { viewedValue != nil }, set: { if !$0 { viewedValue = nil } })) {
            ValueViewer(value: viewedValue ?? "")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            // Submit / revert (pending changes)
            Button {
                Task { await model.submit() }
            } label: {
                Image(systemName: "arrow.up.circle")
                    .foregroundStyle(model.hasPendingChanges ? Color.green : Theme.dimText)
            }
            .buttonStyle(.borderless)
            .disabled(!model.hasPendingChanges)
            .help("Submit pending changes (⌘⏎)")
            .keyboardShortcut(.return, modifiers: .command)

            Button {
                model.discardChanges()
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .foregroundStyle(model.hasPendingChanges ? Theme.text : Theme.dimText)
            }
            .buttonStyle(.borderless)
            .disabled(!model.hasPendingChanges)
            .help("Revert pending changes")

            Divider().frame(height: 16)

            Button {
                model.addRow()
            } label: { Image(systemName: "plus") }
            .buttonStyle(.borderless)
            .help("Add row (⌘N)")

            Button {
                model.markDeleted(selectedRows)
                selectedRows = []
            } label: { Image(systemName: "minus") }
            .buttonStyle(.borderless)
            .disabled(selectedRows.isEmpty)
            .help("Delete selected rows (⌘⌫)")

            Divider().frame(height: 16)

            Button {
                model.reload()
            } label: { Image(systemName: "arrow.clockwise") }
            .buttonStyle(.borderless)
            .help("Reload page (F5)")
            .keyboardShortcut("r", modifiers: .command)

            Button {
                transposed.toggle()
            } label: {
                Image(systemName: "arrow.left.arrow.right.square")
                    .foregroundStyle(transposed ? Theme.accent : Theme.text)
            }
            .buttonStyle(.borderless)
            .help("Transpose (record view)")

            exportMenu

            Divider().frame(height: 16)

            Picker("", selection: $showStructure) {
                Text("Data").tag(false)
                Text("Structure").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .controlSize(.small)

            Spacer()

            pagingControls
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(Theme.toolWindowBackground)
    }

    private var exportMenu: some View {
        Menu {
            ForEach(ExportFormat.allCases) { format in
                Menu(format.rawValue) {
                    Button("Current Page") { export(format: format, allRows: false) }
                    Button("All Rows") { export(format: format, allRows: true) }
                }
            }
            Divider()
            Button("Copy Page as CSV") {
                copyToPasteboard(Exporter.csv(columns: model.columns, rows: model.rows))
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 34)
        .help("Export data")
    }

    private var pagingControls: some View {
        HStack(spacing: 6) {
            Menu("\(model.pageSize)") {
                ForEach([10, 50, 100, 500, 1000], id: \.self) { size in
                    Button("\(size) rows") {
                        model.pageSize = size
                        model.offset = 0
                        model.reload()
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .frame(width: 52)
            .help("Page size")

            Button { model.firstPage() } label: { Image(systemName: "chevron.left.2") }
                .buttonStyle(.borderless).disabled(model.offset == 0)
            Button { model.prevPage() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless).disabled(model.offset == 0)
            Text(model.pageDescription)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dimText)
                .frame(minWidth: 80)
            Button { model.nextPage() } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless).disabled(!model.canPageForward)
            Button { model.lastPage() } label: { Image(systemName: "chevron.right.2") }
                .buttonStyle(.borderless).disabled(!model.canPageForward || model.totalRows == nil)
        }
    }

    // MARK: - Filter bar (IntelliJ's WHERE field)

    private var filterBar: some View {
        HStack(spacing: 6) {
            Text("WHERE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.dimText)
            TextField("filter condition, e.g. name LIKE '%a%'", text: $whereDraft)
                .textFieldStyle(.plain)
                .font(Theme.monoFont)
                .onSubmit {
                    model.whereClause = whereDraft
                    model.offset = 0
                    model.reload()
                }
            if !model.whereClause.isEmpty {
                Button {
                    whereDraft = ""
                    model.whereClause = ""
                    model.offset = 0
                    model.reload()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Theme.editorBackground)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(error).font(.system(size: 11)).foregroundStyle(.red)
                .textSelection(.enabled)
                .lineLimit(3)
            Spacer()
            Button { model.error = nil } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                .buttonStyle(.borderless)
        }
        .padding(6)
        .background(Color.red.opacity(0.1))
    }

    private var statusBar: some View {
        HStack {
            Text("\(model.dataSource.name) · \(model.schema.isEmpty ? "" : model.schema + ".")\(model.table)")
                .font(.system(size: 10))
                .foregroundStyle(Theme.dimText)
            Spacer()
            if model.hasPendingChanges {
                let count = Set(model.editedCells.keys.map(\.row)).count
                    + model.insertedRows.count + model.deletedRows.count
                Text("\(count) pending change\(count == 1 ? "" : "s") — submit ⌘⏎")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            Text(String(format: "%.0f ms", model.lastLoadDuration * 1000))
                .font(.system(size: 10))
                .foregroundStyle(Theme.dimText)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Theme.toolWindowBackground)
    }

    private func export(format: ExportFormat, allRows: Bool) {
        Task {
            let text = await model.exportText(format: format, allRows: allRows)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(model.table).\(format.fileExtension)"
            if panel.runModal() == .OK, let url = panel.url {
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

/// Simple modal viewer for a long cell value.
private struct ValueViewer: View {
    @Environment(\.dismiss) private var dismiss
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(value)
                    .font(Theme.monoFont)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            HStack {
                Button("Copy") { copyToPasteboard(value) }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 520, height: 360)
    }
}

/// Record view of the selected row (IntelliJ transpose).
private struct TransposedView: View {
    @ObservedObject var model: TableGridModel
    @Binding var selectedRows: Set<Int>

    var body: some View {
        let rowIdx = selectedRows.sorted().first ?? 0
        ScrollView {
            if model.rows.indices.contains(rowIdx) {
                VStack(spacing: 0) {
                    ForEach(model.columns.indices, id: \.self) { col in
                        HStack(alignment: .top, spacing: 0) {
                            Text(model.columns[col])
                                .font(Theme.monoFont)
                                .foregroundStyle(Color(red: 0.55, green: 0.65, blue: 0.85))
                                .frame(width: 200, alignment: .leading)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                            cellText(model.displayValue(row: rowIdx, col: col))
                                .font(Theme.monoFont)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                        .background(col % 2 == 1 ? Theme.gridStripe : .clear)
                    }
                }
            } else {
                Text("Select a row to inspect")
                    .foregroundStyle(Theme.dimText)
                    .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func cellText(_ value: DBValue) -> Text {
        value.isNull
            ? Text("<null>").foregroundColor(Theme.nullText).italic()
            : Text(value.displayString)
    }
}
