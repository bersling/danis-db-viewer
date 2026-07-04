import Foundation

/// Turns opaque connection errors into actionable messages with likely causes.
enum ConnectionDiagnostics {
    static let connectTimeout: TimeInterval = 10

    /// Race an async connect against a deadline so a silently dropped SYN
    /// (firewall, VPN) fails fast instead of hanging.
    static func withConnectTimeout<T: Sendable>(_ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(connectTimeout * 1_000_000_000))
                throw DriverError.connectionFailed("__timeout__")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    /// Human diagnosis: what happened + likely causes for this data source.
    static func explain(_ error: Error, config: DataSourceConfig) -> String {
        let raw = rawMessage(error)
        let target = "\(config.host):\(config.effectivePort)"
        let lower = raw.lowercased()

        if raw == "__timeout__" || lower.contains("timed out") || lower.contains("timeout") {
            var causes = [
                "the host silently drops packets — with cloud DBs (AWS RDS, Aiven) this usually means your IP is not allow-listed in the security group / firewall",
                "VPN not connected (internal hosts are often only reachable through it)",
                "an SSH tunnel is required and not running",
                "wrong host or port",
            ]
            if config.host.contains("rds.amazonaws.com") {
                causes.insert("this is an AWS RDS endpoint — check the VPC security group allows your IP, or connect via VPN/bastion", at: 0)
            }
            if config.host.contains("aivencloud.com") {
                causes.insert("this is an Aiven endpoint — check the service's allowed IP list", at: 0)
            }
            return "Connection to \(target) timed out after \(Int(connectTimeout))s — no response from the server.\n\nLikely causes:\n"
                + causes.map { "• \($0)" }.joined(separator: "\n")
        }
        if lower.contains("connection refused") || lower.contains("econnrefused") {
            return "Connection refused — \(target) is reachable but nothing accepts connections on that port.\n\nLikely causes:\n"
                + "• the database server isn't running\n"
                + "• wrong port (this one answers, but not with a DB)\n"
                + "• a local tunnel/container that isn't started"
        }
        if lower.contains("nodename nor servname") || lower.contains("could not resolve")
            || lower.contains("name or service not known") || lower.contains("dns")
            || lower.contains("failed to resolve") || lower.contains("getaddrinfo") {
            return "DNS lookup failed for “\(config.host)”.\n\nLikely causes:\n"
                + "• typo in the hostname\n"
                + "• the name only resolves inside a VPN / internal DNS\n"
                + "• no network connection"
        }
        if lower.contains("password") || lower.contains("authentication") || lower.contains("access denied")
            || lower.contains("28p01") || lower.contains("1045") {
            return "Authentication failed for user “\(config.user)”: \(raw)\n\nLikely causes:\n"
                + "• wrong or missing password (edit the data source and re-enter it)\n"
                + "• wrong username\n"
                + "• the user isn't allowed to connect from your IP/host"
        }
        if lower.contains("tls") || lower.contains("ssl") {
            return "TLS/SSL problem talking to \(target): \(raw)\n\nLikely causes:\n"
                + "• the server requires TLS (this app currently connects without TLS)\n"
                + "• a proxy interfering with the handshake"
        }
        if lower.contains("network is unreachable") || lower.contains("host is down") {
            return "Network unreachable trying \(target) — check your internet connection or VPN."
        }
        if lower.contains("does not exist") && lower.contains("database") {
            return "\(raw)\n\nThe server is reachable and credentials work — the database name “\(config.database)” is wrong."
        }
        return raw
    }

    private static func rawMessage(_ error: Error) -> String {
        if let d = error as? DriverError, case .connectionFailed(let m) = d { return m }
        return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
