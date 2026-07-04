import XCTest
@testable import DanisDBViewer

/// Regression: an empty MySQL table must still show its columns. MySQLNIO only
/// exposes column metadata via the first row, so TableGridModel falls back to
/// introspected columns. Gated on DANIS_IT_MYSQL=1 (docker container).
@MainActor
final class EmptyTableTests: XCTestCase {
    func testEmptyMySQLTableShowsColumns() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DANIS_IT_MYSQL"] == "1")
        var config = DataSourceConfig.newDefault(kind: .mysql)
        config.host = "127.0.0.1"
        config.port = 53306
        config.user = "root"
        config.database = "shop"
        config.transientPassword = "secret"

        // Seed an empty table.
        let setup = MySQLDriver(config: config)
        try await setup.connect()
        _ = await setup.execute(script: """
            DROP TABLE IF EXISTS it_empty;
            CREATE TABLE it_empty (id INT PRIMARY KEY, label VARCHAR(50), amount DECIMAL(8,2));
            """)
        await setup.close()

        let sessions = SessionRegistry()
        let model = TableGridModel(dataSource: config, schema: "shop", table: "it_empty", sessions: sessions)
        await model.load()

        XCTAssertNil(model.error)
        XCTAssertEqual(model.rows.count, 0, "table should be empty")
        // The fix: columns come from introspection even with zero rows.
        XCTAssertEqual(model.columns, ["id", "label", "amount"],
                       "empty table should still show its columns")

        // Clean up the table, then close the live connection so the NIO
        // connection doesn't deinit unclosed (which traps).
        if let d = try? await sessions.driver(for: config) {
            _ = await d.execute(script: "DROP TABLE IF EXISTS it_empty")
        }
        await sessions.disconnect(config.id)
    }
}
