import XCTest
@testable import DanisDBViewer

/// Live checks for connection-error diagnosis (gated like the other IT tests).
final class LiveDiagnosticsTests: XCTestCase {
    func testWrongPasswordDiagnosis() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DANIS_IT_MYSQL"] == "1")
        var config = DataSourceConfig.newDefault(kind: .mysql)
        config.host = "127.0.0.1"
        config.port = 53306
        config.user = "root"
        config.database = "shop"
        config.transientPassword = "WRONG"
        let driver = MySQLDriver(config: config)
        do {
            try await driver.connect()
            XCTFail("should not connect")
        } catch {
            let msg = error.localizedDescription
            print("WRONG-PASSWORD DIAGNOSIS:\n\(msg)\n")
            XCTAssertTrue(msg.contains("Authentication failed"), msg)
        }
        await driver.close()
    }

    func testBlackholeTimeoutDiagnosis() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DANIS_IT_MYSQL"] == "1")
        var config = DataSourceConfig.newDefault(kind: .mysql)
        config.host = "10.255.255.1"   // non-routable → silent drop
        config.port = 3306
        config.user = "root"
        config.transientPassword = "x"
        let driver = MySQLDriver(config: config)
        let start = Date()
        do {
            try await driver.connect()
            XCTFail("should not connect")
        } catch {
            let msg = error.localizedDescription
            print("TIMEOUT DIAGNOSIS (after \(Int(Date().timeIntervalSince(start)))s):\n\(msg)\n")
            XCTAssertTrue(msg.contains("timed out"), msg)
            XCTAssertTrue(msg.contains("VPN"), msg)
        }
        await driver.close()
    }
}
