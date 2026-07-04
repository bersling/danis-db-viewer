import XCTest
@testable import DanisDBViewer

/// Full driver lifecycle against live servers. Enabled with
/// DANIS_IT_PG=1 / DANIS_IT_MYSQL=1 (docker containers from the README).
final class DriverIntegrationTests: XCTestCase {

    // MARK: Postgres

    func testPostgresEndToEnd() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DANIS_IT_PG"] == "1")
        var config = DataSourceConfig.newDefault(kind: .postgres)
        config.host = "127.0.0.1"
        config.port = 55432
        config.user = "postgres"
        config.database = "postgres"
        config.transientPassword = "secret"

        let driver = PostgresDriver(config: config)
        try await driver.connect()
        defer { Task { await driver.close() } }

        _ = await driver.execute(script: """
            DROP TABLE IF EXISTS it_orders; DROP TABLE IF EXISTS it_customers;
            CREATE TABLE it_customers (
                id SERIAL PRIMARY KEY, name TEXT NOT NULL, tier TEXT DEFAULT 'basic', balance NUMERIC(10,2)
            );
            CREATE TABLE it_orders (
                id SERIAL PRIMARY KEY,
                customer_id INT NOT NULL REFERENCES it_customers(id),
                total DOUBLE PRECISION, placed_at TIMESTAMPTZ DEFAULT now(), paid BOOLEAN DEFAULT false
            );
            CREATE INDEX it_orders_customer ON it_orders(customer_id);
            INSERT INTO it_customers (name, tier, balance) VALUES ('Ada', 'gold', 12.50), ('Grace', 'basic', 0.00);
            INSERT INTO it_orders (customer_id, total, paid) VALUES (1, 99.5, true), (1, 12.0, false), (2, 5.25, false);
            """)

        // Introspection
        let intro = try await driver.introspect()
        let publicSchema = try XCTUnwrap(intro.schemas.first { $0.name == "public" })
        let orders = try XCTUnwrap(publicSchema.tables.first { $0.name == "it_orders" })
        XCTAssertEqual(orders.primaryKeyColumns, ["id"])
        XCTAssertEqual(orders.foreignKeys.first?.referencedTable, "it_customers")
        XCTAssertTrue(orders.indexes.contains { $0.name == "it_orders_customer" })
        let idCol = try XCTUnwrap(orders.columns.first { $0.name == "id" })
        XCTAssertTrue(idCol.isAutoIncrement)

        // Query with typed values
        let results = await driver.execute(script: "SELECT id, total, paid, placed_at FROM it_orders ORDER BY id")
        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0].error)
        XCTAssertEqual(results[0].rows.count, 3)
        XCTAssertEqual(results[0].rows[0][0], .int(1))
        XCTAssertEqual(results[0].rows[0][2], .bool(true))

        // Table data page + count
        var req = TableDataRequest(schema: "public", table: "it_orders")
        req.orderBy = [("total", true)]
        req.whereClause = "total > 6"
        let page = try await driver.fetchTableData(req)
        XCTAssertEqual(page.rows.count, 2)
        XCTAssertEqual(page.totalRows, 2)

        // Mutations via staged changes
        try await driver.apply(changes: [
            .insert(columns: ["customer_id", "total", "paid"], values: [.int(2), .double(77.7), .bool(true)]),
            .update(keyColumns: ["id"], keyValues: [.int(1)], setColumns: ["total"], setValues: [.double(100.0)]),
            .delete(keyColumns: ["id"], keyValues: [.int(2)]),
        ], schema: "public", table: "it_orders")
        let after = await driver.execute(script: "SELECT COUNT(*), SUM(total) FROM it_orders")
        XCTAssertEqual(after[0].rows[0][0], .int(3))

        // DDL
        let ddl = try await driver.ddl(schema: "public", table: "it_orders")
        XCTAssertTrue(ddl.contains("CREATE TABLE"))
        XCTAssertTrue(ddl.contains("FOREIGN KEY"))

        // Error surface
        let bad = await driver.execute(script: "SELECT nope FROM does_not_exist")
        XCTAssertNotNil(bad[0].error)
    }

    // MARK: MySQL

    func testMySQLEndToEnd() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DANIS_IT_MYSQL"] == "1")
        var config = DataSourceConfig.newDefault(kind: .mysql)
        config.host = "127.0.0.1"
        config.port = 53306
        config.user = "root"
        config.database = "shop"
        config.transientPassword = "secret"

        let driver = MySQLDriver(config: config)
        try await driver.connect()
        defer { Task { await driver.close() } }

        _ = await driver.execute(script: """
            DROP TABLE IF EXISTS it_items; DROP TABLE IF EXISTS it_products;
            CREATE TABLE it_products (
                id INT AUTO_INCREMENT PRIMARY KEY, sku VARCHAR(32) NOT NULL UNIQUE, price DECIMAL(8,2)
            );
            CREATE TABLE it_items (
                id INT AUTO_INCREMENT PRIMARY KEY,
                product_id INT NOT NULL, qty INT DEFAULT 1,
                CONSTRAINT fk_item_product FOREIGN KEY (product_id) REFERENCES it_products(id)
            );
            INSERT INTO it_products (sku, price) VALUES ('A-1', 9.99), ('B-2', 100.00);
            INSERT INTO it_items (product_id, qty) VALUES (1, 3), (2, 1);
            """)

        let intro = try await driver.introspect()
        let shop = try XCTUnwrap(intro.schemas.first { $0.name == "shop" })
        let items = try XCTUnwrap(shop.tables.first { $0.name == "it_items" })
        XCTAssertEqual(items.primaryKeyColumns, ["id"])
        XCTAssertEqual(items.foreignKeys.first?.referencedTable, "it_products")
        XCTAssertTrue(try XCTUnwrap(items.columns.first { $0.name == "id" }).isAutoIncrement)

        let results = await driver.execute(script: "SELECT id, qty FROM it_items ORDER BY id")
        XCTAssertNil(results[0].error)
        XCTAssertEqual(results[0].rows[0][0], .int(1))
        XCTAssertEqual(results[0].rows[0][1], .int(3))

        var req = TableDataRequest(schema: "shop", table: "it_items")
        req.whereClause = "qty >= 1"
        let page = try await driver.fetchTableData(req)
        XCTAssertEqual(page.totalRows, 2)

        try await driver.apply(changes: [
            .insert(columns: ["product_id", "qty"], values: [.int(1), .int(9)]),
            .update(keyColumns: ["id"], keyValues: [.int(1)], setColumns: ["qty"], setValues: [.int(5)]),
        ], schema: "shop", table: "it_items")
        let after = await driver.execute(script: "SELECT SUM(qty) FROM it_items")
        // 5 + 1 + 9
        XCTAssertEqual(after[0].rows[0][0].displayString.hasPrefix("15"), true)

        let ddl = try await driver.ddl(schema: "shop", table: "it_items")
        XCTAssertTrue(ddl.uppercased().contains("CREATE TABLE"))

        let bad = await driver.execute(script: "SELECT * FROM missing_table_xyz")
        XCTAssertNotNil(bad[0].error)
    }
}
