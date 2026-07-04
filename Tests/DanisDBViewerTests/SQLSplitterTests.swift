import XCTest
@testable import DanisDBViewer

final class SQLSplitterTests: XCTestCase {
    func testSplitBasic() {
        let parts = SQLSplitter.split("SELECT 1; SELECT 2;")
        XCTAssertEqual(parts, ["SELECT 1", "SELECT 2"])
    }

    func testSemicolonInString() {
        let parts = SQLSplitter.split("SELECT 'a;b'; SELECT 2")
        XCTAssertEqual(parts, ["SELECT 'a;b'", "SELECT 2"])
    }

    func testEscapedQuote() {
        let parts = SQLSplitter.split("SELECT 'it''s; fine'; SELECT 2")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0], "SELECT 'it''s; fine'")
    }

    func testComments() {
        let parts = SQLSplitter.split("SELECT 1 -- trailing; comment\n; SELECT 2 /* block; comment */")
        XCTAssertEqual(parts.count, 2)
    }

    func testDollarQuoted() {
        let parts = SQLSplitter.split("CREATE FUNCTION f() RETURNS int AS $$ SELECT 1; $$ LANGUAGE sql; SELECT 2")
        XCTAssertEqual(parts.count, 2)
    }

    func testStatementAtCaret() {
        let script = "SELECT 1;\nSELECT 2;\nSELECT 3"
        XCTAssertEqual(SQLSplitter.statement(at: 2, in: script), "SELECT 1")
        XCTAssertEqual(SQLSplitter.statement(at: 12, in: script), "SELECT 2")
        XCTAssertEqual(SQLSplitter.statement(at: script.count, in: script), "SELECT 3")
    }

    func testValueParsing() {
        XCTAssertEqual(DBValue.parse("42", forDeclaredType: "INTEGER"), .int(42))
        XCTAssertEqual(DBValue.parse("4.5", forDeclaredType: "REAL"), .double(4.5))
        XCTAssertEqual(DBValue.parse("true", forDeclaredType: "boolean"), .bool(true))
        XCTAssertEqual(DBValue.parse("hello", forDeclaredType: "TEXT"), .text("hello"))
    }

    func testCSVEscaping() {
        let csv = Exporter.csv(columns: ["a", "b"], rows: [[.text("x,y"), .text("q\"z")]])
        XCTAssertTrue(csv.contains("\"x,y\""))
        XCTAssertTrue(csv.contains("\"q\"\"z\""))
    }
}
