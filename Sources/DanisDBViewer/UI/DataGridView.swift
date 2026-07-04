import AppKit
import SwiftUI

/// The IntelliJ-style data grid: row-number gutter, clickable sort headers,
/// grid lines, stripes, staged-change coloring, inline editing.
struct DataGridView: View {
    @ObservedObject var model: TableGridModel
    @Binding var selectedRows: Set<Int>
    @Binding var viewedValue: String?

    @State private var editingCell: CellCoord?
    @State private var selectedCell: CellCoord?
    @State private var editDraft = ""
    @FocusState private var editFocused: Bool

    private let rowHeight: CGFloat = 22
    private let gutterWidth: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    rowsView
                }
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
            }
        }
        .background(Theme.editorBackground)
        .focusable(editingCell == nil)
        .focusEffectDisabled()
        .onKeyPress(.return) {
            guard editingCell == nil, let cell = selectedCell else { return .ignored }
            startEdit(cell, value: cellValue(row: cell.row, col: cell.col))
            return .handled
        }
    }

    private var widths: [CGFloat] { columnWidths() }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            Text("#")
                .font(.system(size: 10))
                .foregroundStyle(Theme.dimText)
                .frame(width: gutterWidth, height: rowHeight)
                .background(Theme.toolWindowBackground)
                .border(Theme.gridLine, width: 0.5)
            ForEach(model.columns.indices, id: \.self) { col in
                HeaderCell(model: model, col: col, width: widths[col], rowHeight: rowHeight,
                           typeLabel: typeLabel(col), isPrimaryKey: isPrimaryKey(col))
            }
        }
    }

    private struct HeaderCell: View {
        @ObservedObject var model: TableGridModel
        let col: Int
        let width: CGFloat
        let rowHeight: CGFloat
        let typeLabel: String
        let isPrimaryKey: Bool
        @State private var hovering = false

        var body: some View {
            Button {
                model.cycleSort(column: col)
            } label: {
                HStack(spacing: 3) {
                    if isPrimaryKey {
                        Image(systemName: "key.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color(red: 0.85, green: 0.73, blue: 0.34))
                    }
                    Text(model.columns[col])
                        .font(.system(size: 11, weight: .semibold))
                    Text(typeLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dimText)
                    if model.sortColumn == col {
                        Image(systemName: model.sortDescending ? "chevron.down" : "chevron.up")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .frame(width: width, height: rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(hovering ? Theme.selection.opacity(0.4) : Theme.toolWindowBackground)
            .border(Theme.gridLine, width: 0.5)
            .onHover { isHovering in
                hovering = isHovering
                if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .help("Click to sort")
        }
    }

    // MARK: - Rows

    private var rowsView: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<(model.rows.count + model.insertedRows.count), id: \.self) { row in
                rowView(row)
            }
        }
    }

    private func rowView(_ row: Int) -> some View {
        let isInserted = row >= model.rows.count
        let isDeleted = model.deletedRows.contains(row)
        let isSelected = selectedRows.contains(row)

        return HStack(spacing: 0) {
            Text(isInserted ? "+" : "\(model.offset + row + 1)")
                .font(.system(size: 10))
                .foregroundStyle(isInserted ? .green : Theme.dimText)
                .frame(width: gutterWidth, height: rowHeight)
                .background(isSelected ? Theme.selection : Theme.toolWindowBackground)
                .border(Theme.gridLine, width: 0.5)
                .contentShape(Rectangle())
                .onTapGesture { select(row: row) }

            ForEach(model.columns.indices, id: \.self) { col in
                cellView(row: row, col: col, isInserted: isInserted, isDeleted: isDeleted, isSelected: isSelected)
            }
        }
    }

    @ViewBuilder
    private func cellView(row: Int, col: Int, isInserted: Bool, isDeleted: Bool, isSelected: Bool) -> some View {
        let coord = CellCoord(row: row, col: col)
        let value = cellValue(row: row, col: col)
        let isEdited = !isInserted && model.editedCells[coord] != nil

        Group {
            if editingCell == coord {
                TextField("", text: $editDraft)
                    .textFieldStyle(.plain)
                    .font(Theme.monoFont)
                    .focused($editFocused)
                    .onSubmit { commitEdit() }
                    .onExitCommand { editingCell = nil }
                    .padding(.horizontal, 4)
            } else {
                (value.isNull
                    ? Text("<null>").foregroundColor(Theme.nullText).italic()
                    : Text(value.displayString))
                    .font(Theme.monoFont)
                    .lineLimit(1)
                    .strikethrough(isDeleted)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: widths[col], height: rowHeight, alignment: .leading)
        .background(cellBackground(isInserted: isInserted, isDeleted: isDeleted, isEdited: isEdited, isSelected: isSelected, row: row))
        .border(selectedCell == coord && editingCell == nil ? Theme.accent : Theme.gridLine,
                width: selectedCell == coord && editingCell == nil ? 1.5 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture {
            // Click selects; a second click on the selected cell edits.
            if editingCell == coord { return }
            if selectedCell == coord {
                startEdit(coord, value: value)
            } else {
                commitEditIfNeeded()
                selectedCell = coord
                select(row: row)
            }
        }
        .contextMenu {
            Button("Edit Cell") { startEdit(coord, value: value) }
            Button("Set NULL") { setCell(coord, to: .null) }
            Divider()
            Button("View Value") { viewedValue = value.displayString }
            Button("Copy Value") { copyToPasteboard(value.isNull ? "" : value.displayString) }
            Divider()
            Button("Delete Row\(selectedRows.count > 1 ? "s" : "")", role: .destructive) {
                let targets = selectedRows.isEmpty ? [row] : Array(selectedRows)
                model.markDeleted(Set(targets))
                selectedRows = []
            }
        }
    }

    private func cellBackground(isInserted: Bool, isDeleted: Bool, isEdited: Bool, isSelected: Bool, row: Int) -> Color {
        if isDeleted { return Theme.cellDeleted }
        if isInserted { return Theme.cellInserted }
        if isEdited { return Theme.cellModified }
        if isSelected { return Theme.selection.opacity(0.6) }
        return row % 2 == 1 ? Theme.gridStripe : .clear
    }

    // MARK: - Interactions

    private func select(row: Int) {
        if NSEvent.modifierFlags.contains(.command) {
            if selectedRows.contains(row) { selectedRows.remove(row) } else { selectedRows.insert(row) }
        } else if NSEvent.modifierFlags.contains(.shift), let anchor = selectedRows.min() {
            selectedRows = Set(min(anchor, row)...max(anchor, row))
        } else {
            selectedRows = [row]
        }
    }

    private func startEdit(_ coord: CellCoord, value: DBValue) {
        editDraft = value.editString
        editingCell = coord
        DispatchQueue.main.async { editFocused = true }
    }

    /// Clicking another cell while editing commits the in-progress edit.
    private func commitEditIfNeeded() {
        if editingCell != nil { commitEdit() }
    }

    private func commitEdit() {
        guard let coord = editingCell else { return }
        let type = coord.col < model.columnTypes.count ? model.columnTypes[coord.col] : ""
        setCell(coord, to: DBValue.parse(editDraft, forDeclaredType: type))
        editingCell = nil
    }

    private func setCell(_ coord: CellCoord, to value: DBValue) {
        if coord.row >= model.rows.count {
            let insertIdx = coord.row - model.rows.count
            if insertIdx < model.insertedRows.count && coord.col < model.insertedRows[insertIdx].count {
                model.insertedRows[insertIdx][coord.col] = value
            }
        } else {
            model.setCell(row: coord.row, col: coord.col, to: value)
        }
    }

    private func cellValue(row: Int, col: Int) -> DBValue {
        if row >= model.rows.count {
            let insertIdx = row - model.rows.count
            guard insertIdx < model.insertedRows.count, col < model.insertedRows[insertIdx].count else { return .null }
            return model.insertedRows[insertIdx][col]
        }
        return model.displayValue(row: row, col: col)
    }

    // MARK: - Column sizing

    private func columnWidths() -> [CGFloat] {
        let charWidth: CGFloat = 7.3
        return model.columns.indices.map { col in
            var maxLen = model.columns[col].count + typeLabel(col).count + 4
            for row in model.rows.prefix(60) where col < row.count {
                maxLen = max(maxLen, min(row[col].displayString.count, 60))
            }
            return min(max(CGFloat(maxLen) * charWidth + 16, 70), 460)
        }
    }

    private func typeLabel(_ col: Int) -> String {
        col < model.columnTypes.count ? model.columnTypes[col].lowercased() : ""
    }

    private func isPrimaryKey(_ col: Int) -> Bool {
        guard let info = model.tableInfo else { return false }
        return info.primaryKeyColumns.contains(model.columns[col])
    }
}
