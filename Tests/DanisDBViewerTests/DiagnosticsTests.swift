import XCTest
@testable import DanisDBViewer

final class DiagnosticsTests: XCTestCase {
    private func config(host: String = "db.example.com", user: String = "root") -> DataSourceConfig {
        var c = DataSourceConfig.newDefault(kind: .mysql)
        c.host = host
        c.user = user
        return c
    }

    private func explain(_ message: String, host: String = "db.example.com") -> String {
        ConnectionDiagnostics.explain(DriverError.connectionFailed(message), config: config(host: host))
    }

    func testTimeout() {
        let msg = explain("__timeout__")
        XCTAssertTrue(msg.contains("timed out"))
        XCTAssertTrue(msg.contains("VPN"))
    }

    func testTimeoutMentionsRDS() {
        let msg = explain("__timeout__", host: "aila-dev.cluster-x.eu-central-1.rds.amazonaws.com")
        XCTAssertTrue(msg.contains("AWS RDS"))
        XCTAssertTrue(msg.contains("security group"))
    }

    func testRefused() {
        let msg = explain("connect: Connection refused (errno 61)")
        XCTAssertTrue(msg.contains("isn't running") || msg.contains("refused"))
        XCTAssertTrue(msg.contains("port"))
    }

    func testDNS() {
        let msg = explain("nodename nor servname provided, or not known")
        XCTAssertTrue(msg.contains("DNS"))
        XCTAssertTrue(msg.contains("db.example.com"))
    }

    func testAuth() {
        let msg = explain("Access denied for user 'root'@'1.2.3.4' (using password: YES)")
        XCTAssertTrue(msg.contains("Authentication failed"))
        XCTAssertTrue(msg.contains("re-enter"))
    }

    func testUnknownPassesThrough() {
        let msg = explain("some exotic failure")
        XCTAssertEqual(msg, "some exotic failure")
    }

    func testConnectTimeoutFiresQuickly() async {
        let start = Date()
        do {
            _ = try await ConnectionDiagnostics.withConnectTimeout(connect: { () -> Int in
                try await Task.sleep(nanoseconds: 60_000_000_000)
                return 1
            }, close: { _ in })
            XCTFail("should have timed out")
        } catch {
            XCTAssertLessThan(Date().timeIntervalSince(start), ConnectionDiagnostics.connectTimeout + 3)
        }
    }

    /// The losing (late) connection must be closed, not leaked — this is what
    /// prevented the MySQLConnection.deinit trap that crashed the app.
    func testTimeoutClosesLateConnection() async {
        actor Flag { var closed = false; func mark() { closed = true }; func get() -> Bool { closed } }
        let flag = Flag()
        do {
            _ = try await ConnectionDiagnostics.withConnectTimeout(connect: { () -> Int in
                // Resolve AFTER the timeout fires, producing a value that must be closed.
                try? await Task.sleep(nanoseconds: UInt64((ConnectionDiagnostics.connectTimeout + 1) * 1_000_000_000))
                return 42
            }, close: { _ in await flag.mark() })
            XCTFail("should have timed out")
        } catch {
            // give the late connect task time to resolve and be closed
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let closed = await flag.get()
            XCTAssertTrue(closed, "late connection was not closed → would trap in deinit")
        }
    }
}
