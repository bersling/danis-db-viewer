import XCTest
@testable import DanisDBViewer

/// Exercises the table editor's staged-changes pipeline against a real
/// SQLite database (a throwaway copy of the sample DB).
@MainActor
final class GridModelTests: XCTestCase {
    private var dbPath: String!

    override func setUp() async throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SampleData/chinook-mini.db")
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("grid-test-\(UUID().uuidString).db")
        try FileManager.default.copyItem(at: source, to: copy)
        dbPath = copy.path
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    private func makeModel() -> (TableGridModel, SessionRegistry) {
        var config = DataSourceConfig.newDefault(kind: .sqlite)
        config.filePath = dbPath
        let sessions = SessionRegistry()
        let model = TableGridModel(dataSource: config, schema: "main", table: "artists", sessions: sessions)
        return (model, sessions)
    }

    func testLoadSortFilterPage() async throws {
        let (model, _) = makeModel()
        await model.load()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.columns, ["id", "name", "country", "formed_year"])
        XCTAssertEqual(model.totalRows, 5)
        XCTAssertEqual(model.tableInfo?.primaryKeyColumns, ["id"])

        // Sort by name desc
        model.sortColumn = 1
        model.sortDescending = true
        await model.load()
        XCTAssertEqual(model.rows.first?[1], .text("Radiohead"))

        // WHERE filter
        model.whereClause = "country = 'UK'"
        await model.load()
        XCTAssertEqual(model.totalRows, 2)

        // Paging
        model.whereClause = ""
        model.pageSize = 2
        model.offset = 2
        await model.load()
        XCTAssertEqual(model.rows.count, 2)
        XCTAssertTrue(model.canPageForward)
    }

    func testStagedChangesSubmit() async throws {
        let (model, _) = makeModel()
        await model.load()

        // Stage an update + an insert in one batch.
        let radioheadRow = try XCTUnwrap(model.rows.firstIndex { $0[1] == .text("Radiohead") })
        model.setCell(row: radioheadRow, col: 2, to: .text("England"))

        model.addRow()
        XCTAssertEqual(model.insertedRows.count, 1)
        model.insertedRows[0][1] = .text("Nirvana")
        model.insertedRows[0][2] = .text("USA")
        model.insertedRows[0][3] = .int(1987)

        XCTAssertTrue(model.hasPendingChanges)
        await model.submit()
        XCTAssertNil(model.error)
        XCTAssertFalse(model.hasPendingChanges)

        // Verify persisted state after reload.
        XCTAssertEqual(model.totalRows, 6)
        let names = model.rows.map { $0[1] }
        XCTAssertTrue(names.contains(.text("Nirvana")))
        let radiohead = try XCTUnwrap(model.rows.first { $0[1] == .text("Radiohead") })
        XCTAssertEqual(radiohead[2], .text("England"))
        // Auto-increment id was assigned to the insert.
        let nirvana = try XCTUnwrap(model.rows.first { $0[1] == .text("Nirvana") })
        XCTAssertEqual(nirvana[0], .int(6))

        // Second batch: delete the (unreferenced) new row.
        let nirvanaRow = try XCTUnwrap(model.rows.firstIndex { $0[1] == .text("Nirvana") })
        model.markDeleted([nirvanaRow])
        await model.submit()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.totalRows, 5)
        XCTAssertFalse(model.rows.map { $0[1] }.contains(.text("Nirvana")))
    }

    func testSubmitRollsBackOnError() async throws {
        let (model, _) = makeModel()
        await model.load()

        // Two staged inserts; the second violates UNIQUE(name) → whole batch must roll back.
        model.addRow()
        model.insertedRows[0][1] = .text("Unique Band")
        model.addRow()
        model.insertedRows[1][1] = .text("Radiohead")

        await model.submit()
        XCTAssertNotNil(model.error)

        // Reload: neither row exists.
        model.discardChanges()
        await model.load()
        XCTAssertEqual(model.totalRows, 5)
        XCTAssertFalse(model.rows.map { $0[1] }.contains(.text("Unique Band")))
    }

    func testDDLAndExport() async throws {
        let (model, sessions) = makeModel()
        await model.load()
        let driver = try await sessions.driver(for: model.dataSource)
        let ddl = try await driver.ddl(schema: "main", table: "artists")
        XCTAssertTrue(ddl.contains("CREATE TABLE artists"))
        XCTAssertTrue(ddl.contains("idx_artists_name"))

        let csv = await model.exportText(format: .csv, allRows: false)
        XCTAssertTrue(csv.hasPrefix("id,name,country,formed_year"))
        let json = await model.exportText(format: .json, allRows: false)
        XCTAssertTrue(json.contains("\"name\" : \"Radiohead\""))
        let inserts = await model.exportText(format: .sqlInserts, allRows: false)
        XCTAssertTrue(inserts.contains("INSERT INTO \"artists\""))
    }
}
