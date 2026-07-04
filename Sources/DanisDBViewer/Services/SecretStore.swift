import Foundation

/// Plaintext password store, keyed by connection UUID, in a 0600 file OUTSIDE
/// the repo (`~/Library/Application Support/DanisDBViewer/secrets.json`).
///
/// Chosen over the macOS Keychain because the Keychain ACL flow re-prompts for
/// authorization whenever the app's code signature changes. This is the same
/// tradeoff as `~/.pgpass` / `~/.my.cnf` / a local `.env`: plaintext on the
/// user's own machine, never in version control. Read fresh each time so
/// external edits (e.g. the injection script) are picked up immediately.
enum SecretStore {
    static var url: URL { AppPaths.supportDir.appendingPathComponent("secrets.json") }

    static func password(for id: UUID) -> String {
        load()[id.uuidString] ?? ""
    }

    static func setPassword(_ password: String, for id: UUID) {
        var dict = load()
        if password.isEmpty { dict[id.uuidString] = nil }
        else { dict[id.uuidString] = password }
        save(dict)
    }

    static func deletePassword(for id: UUID) {
        var dict = load()
        dict[id.uuidString] = nil
        save(dict)
    }

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    private static func save(_ dict: [String: String]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(dict) else { return }
        try? data.write(to: url, options: .atomic)
        // Owner read/write only.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
