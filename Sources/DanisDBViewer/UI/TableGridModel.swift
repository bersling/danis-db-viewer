import Foundation
import SwiftUI

/// Cell coordinate in the grid.
struct CellCoord: Hashable {
    var row: Int
    var col: Int
}

/// State + logic for one table editor tab: paging, sorting, filtering, and the
/// IntelliJ pending-changes model (staged edits submitted in one transaction).
@MainActor
final class TableGridModel: ObservableObject {
    let dataSource: DataSourceConfig
    let schema: String
    let table: String

    // Loaded page
    @Published var columns: [String] = []
    @Published var columnTypes: [String] = []
    @Published var rows: [[DBValue]] = []
    @Published var totalRows: Int?
    @Published var error: String?
    @Published var loading = false
    @Published var lastLoadDuration: TimeInterval = 0

    // Page / sort / filter
    @Published var pageSize = 100
    @Published var offset = 0
    @Published var sortColumn: Int? = nil
    @Published var sortDescending = false
    @Published var whereClause = ""

    // Pending changes
    @Published var editedCells: [CellCoord: DBValue] = [:]
    @Published var insertedRows: [[DBValue]] = []
    @Published var deletedRows: Set<Int> = []

    // Table structure (for PK-based row identity)
    @Published var tableInfo: DBTableInfo?

    var hasPendingChanges: Bool {
        !editedCells.isEmpty || !insertedRows.isEmpty || !deletedRows.isEmpty
    }

    private let sessions: SessionRegistry
    var onDirtyChange: ((Bool) -> Void)?

    init(dataSource: DataSourceConfig, schema: String, table: String, sessions: SessionRegistry) {
        self.dataSource = dataSource
        self.schema = schema
        self.table = table
        self.sessions = sessions
    }

    // MARK: - Loading

    func load() async {
        loading = true
        error = nil
        let start = Date()
        do {
            let driver = try await sessions.driver(for: dataSource)
            if tableInfo == nil {
                let intro: DBIntrospection
                if let cached = sessions.introspections[dataSource.id] {
                    intro = cached
                } else {
                    intro = try await driver.introspect()
                }
                tableInfo = intro.schemas.first { $0.name == schema }?
                    .tables.first { $0.name == table }
            }
            var request = TableDataRequest(schema: schemaForQuery, table: table)
            request.limit = pageSize
            request.offset = offset
            request.whereClause = whereClause
            if let sortColumn, sortColumn < columns.count {
                request.orderBy = [(columns[sortColumn], sortDescending)]
            }
            let page = try await driver.fetchTableData(request)
            columns = page.columns
            columnTypes = page.columnTypes
            rows = page.rows
            totalRows = page.totalRows
            // Empty MySQL result sets carry no column metadata (MySQLNIO exposes
            // columns only via the first row). Fall back to introspected columns
            // so an empty table still shows its structure.
            if columns.isEmpty, let info = tableInfo, !info.columns.isEmpty {
                columns = info.columns.map(\.name)
                columnTypes = info.columns.map(\.typeName)
            }
            discardChanges()
        } catch {
            self.error = error.localizedDescription
        }
        lastLoadDuration = Date().timeIntervalSince(start)
        loading = false
    }

    /// SQLite uses no schema qualifier.
    private var schemaForQuery: String {
        dataSource.kind == .sqlite ? "" : schema
    }

    func reload() {
        Task { await load() }
    }

    // MARK: - Paging

    var pageDescription: String {
        guard !rows.isEmpty else { return "0 rows" }
        let last = offset + rows.count
        if let total = totalRows {
            return "\(offset + 1)-\(last) of \(total)"
        }
        return "\(offset + 1)-\(last)"
    }

    var canPageForward: Bool {
        if let total = totalRows { return offset + pageSize < total }
        return rows.count == pageSize
    }

    func firstPage() { offset = 0; reload() }
    func prevPage() { offset = max(0, offset - pageSize); reload() }
    func nextPage() { if canPageForward { offset += pageSize; reload() } }
    func lastPage() {
        guard let total = totalRows, total > 0 else { return }
        offset = ((total - 1) / pageSize) * pageSize
        reload()
    }

    // MARK: - Sorting (header click cycles asc → desc → none)

    func cycleSort(column: Int) {
        if sortColumn == column {
            if sortDescending {
                sortColumn = nil
                sortDescending = false
            } else {
                sortDescending = true
            }
        } else {
            sortColumn = column
            sortDescending = false
        }
        offset = 0
        reload()
    }

    // MARK: - Editing

    func displayValue(row: Int, col: Int) -> DBValue {
        editedCells[CellCoord(row: row, col: col)] ?? rows[row][col]
    }

    func setCell(row: Int, col: Int, to value: DBValue) {
        let coord = CellCoord(row: row, col: col)
        if rows[row][col] == value {
            editedCells[coord] = nil
        } else {
            editedCells[coord] = value
        }
        notifyDirty()
    }

    func addRow() {
        let count = columns.isEmpty ? (tableInfo?.columns.count ?? 0) : columns.count
        insertedRows.append(Array(repeating: DBValue.null, count: count))
        notifyDirty()
    }

    func markDeleted(_ rowIndexes: Set<Int>) {
        for idx in rowIndexes {
            if idx >= rows.count {
                // Staged insert row → just remove it.
                let insertIdx = idx - rows.count
                if insertIdx < insertedRows.count { insertedRows.remove(at: insertIdx) }
            } else {
                deletedRows.insert(idx)
            }
        }
        notifyDirty()
    }

    func discardChanges() {
        editedCells = [:]
        insertedRows = []
        deletedRows = []
        notifyDirty()
    }

    // MARK: - Submit (IntelliJ ⌘⏎)

    func submit() async {
        guard hasPendingChanges else { return }
        error = nil
        var changes: [RowChange] = []

        let keyColumns = rowIdentityColumns()

        // Updates, grouped per row
        var updatesByRow: [Int: [(Int, DBValue)]] = [:]
        for (coord, value) in editedCells where !deletedRows.contains(coord.row) {
            updatesByRow[coord.row, default: []].append((coord.col, value))
        }
        for (row, colValues) in updatesByRow.sorted(by: { $0.key < $1.key }) {
            let (keyCols, keyVals) = identity(forRow: row, keyColumns: keyColumns)
            changes.append(.update(
                keyColumns: keyCols,
                keyValues: keyVals,
                setColumns: colValues.map { columns[$0.0] },
                setValues: colValues.map { $0.1 }
            ))
        }
        // Deletes
        for row in deletedRows.sorted() {
            let (keyCols, keyVals) = identity(forRow: row, keyColumns: keyColumns)
            changes.append(.delete(keyColumns: keyCols, keyValues: keyVals))
        }
        // Inserts (skip auto-increment columns left NULL)
        for insertRow in insertedRows {
            var cols: [String] = []
            var vals: [DBValue] = []
            for (i, value) in insertRow.enumerated() where i < columns.count {
                let colInfo = tableInfo?.columns.first { $0.name == columns[i] }
                if value.isNull && (colInfo?.isAutoIncrement ?? false) { continue }
                if value.isNull && colInfo?.defaultValue != nil { continue }
                cols.append(columns[i])
                vals.append(value)
            }
            changes.append(.insert(columns: cols, values: vals))
        }

        do {
            let driver = try await sessions.driver(for: dataSource)
            try await driver.apply(changes: changes, schema: schemaForQuery, table: table)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// PK columns if present, else all columns (IntelliJ falls back the same way).
    private func rowIdentityColumns() -> [Int] {
        guard let info = tableInfo else { return Array(columns.indices) }
        let pkNames = Set(info.primaryKeyColumns)
        let pkIndexes = columns.indices.filter { pkNames.contains(columns[$0]) }
        return pkIndexes.isEmpty ? Array(columns.indices) : pkIndexes
    }

    private func identity(forRow row: Int, keyColumns: [Int]) -> ([String], [DBValue]) {
        (keyColumns.map { columns[$0] }, keyColumns.map { rows[row][$0] })
    }

    private func notifyDirty() {
        onDirtyChange?(hasPendingChanges)
    }

    // MARK: - Export

    func exportText(format: ExportFormat, allRows: Bool) async -> String {
        var exportRows = rows
        if allRows {
            do {
                let driver = try await sessions.driver(for: dataSource)
                var request = TableDataRequest(schema: schemaForQuery, table: table)
                request.limit = 1_000_000
                request.whereClause = whereClause
                if let sortColumn, sortColumn < columns.count {
                    request.orderBy = [(columns[sortColumn], sortDescending)]
                }
                exportRows = try await driver.fetchTableData(request).rows
            } catch {
                self.error = error.localizedDescription
            }
        }
        switch format {
        case .csv: return Exporter.csv(columns: columns, rows: exportRows)
        case .json: return Exporter.json(columns: columns, rows: exportRows)
        case .sqlInserts:
            let quote: (String) -> String = { [dataSource] name in
                SessionRegistry.makeDriver(for: dataSource).quoteIdentifier(name)
            }
            return Exporter.sqlInserts(table: table, columns: columns, rows: exportRows, quote: quote)
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case json = "JSON"
    case sqlInserts = "SQL INSERTs"
    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        case .sqlInserts: return "sql"
        }
    }
}
