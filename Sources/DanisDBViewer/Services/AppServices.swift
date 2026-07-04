import Foundation

/// Process-wide service instances. The SwiftUI environment carries these too,
/// but view-model initializers (StateObject) need direct access.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let connectionStore = ConnectionStore()
    let sessions = SessionRegistry()
    let history = QueryHistoryStore()
    let tabs = TabManager()

    private init() {}
}
