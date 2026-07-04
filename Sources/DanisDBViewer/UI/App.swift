import AppKit
import SwiftUI

@main
struct DanisDBViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var connectionStore = AppServices.shared.connectionStore
    @StateObject private var sessions = AppServices.shared.sessions
    @StateObject private var history = AppServices.shared.history
    @StateObject private var tabs = AppServices.shared.tabs

    var body: some Scene {
        WindowGroup("Dani's DB Viewer") {
            MainView()
                .environmentObject(connectionStore)
                .environmentObject(sessions)
                .environmentObject(history)
                .environmentObject(tabs)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            AppCommands()
        }
    }
}

/// Makes a bare `swift run` executable behave like a real app (menu bar, focus).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
    }
}
