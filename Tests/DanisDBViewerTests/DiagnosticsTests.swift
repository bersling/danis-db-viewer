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
            _ = try await ConnectionDiagnostics.withConnectTimeout { () -> Int in
                try await Task.sleep(nanoseconds: 60_000_000_000)
                return 1
            }
            XCTFail("should have timed out")
        } catch {
            XCTAssertLessThan(Date().timeIntervalSince(start), ConnectionDiagnostics.connectTimeout + 3)
        }
    }
}
