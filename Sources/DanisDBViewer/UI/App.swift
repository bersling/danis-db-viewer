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
        // Show .help() tooltips almost immediately (default is ~1–2s).
        UserDefaults.standard.set(100, forKey: "NSInitialToolTipDelay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            applyWindowFrameOverride()
            Task { await runAutomationHooks() }
        }
    }
}

/// DANIS_WINFRAME="x,y,w,h" — position the window (screenshot testing).
private func applyWindowFrameOverride() {
    guard let spec = ProcessInfo.processInfo.environment["DANIS_WINFRAME"] else { return }
    let parts = spec.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 4, let window = NSApp.windows.first else { return }
    window.setFrame(NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]), display: true)
}

/// Test/demo automation, driven by environment variables:
///   DANIS_OPEN_TABLE=name  — connect first data source and open that table
///   DANIS_OPEN_CONSOLE=1   — open a query console for the first data source
/// These exercise the exact same code paths as tree/menu interaction.
@MainActor
private func runAutomationHooks() async {
    let env = ProcessInfo.processInfo.environment
    guard env["DANIS_OPEN_TABLE"] != nil || env["DANIS_OPEN_CONSOLE"] != nil else { return }
    let services = AppServices.shared
    // Pick by name (DANIS_DS) or fall back to the first connection.
    let config: DataSourceConfig
    if let name = env["DANIS_DS"],
       let match = services.connectionStore.connections.first(where: { $0.name == name }) {
        config = match
    } else if let first = services.connectionStore.connections.first {
        config = first
    } else { return }

    let intro = await services.sessions.refreshIntrospection(for: config)
    if let tableName = env["DANIS_OPEN_TABLE"],
       let table = intro?.allTables.first(where: { $0.name == tableName }) {
        services.tabs.openTable(dataSource: config, schema: table.schema, table: table.name)
    }
    if env["DANIS_OPEN_CONSOLE"] != nil {
        services.tabs.openConsole(dataSource: config)
    }
}

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Menu("New Data Source") {
                ForEach(DBKind.allCases) { kind in
                    Button(kind.displayName) {
                        NotificationCenter.default.post(name: .newDataSource, object: kind)
                    }
                }
            }
        }
        CommandMenu("Database") {
            Button("Close Tab") {
                AppServices.shared.tabs.closeSelected()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            Button("Refresh All") {
                Task {
                    let services = AppServices.shared
                    for config in services.connectionStore.connections
                    where services.sessions.isConnected(config.id) {
                        await services.sessions.refreshIntrospection(for: config)
                    }
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
        }
    }
}

extension Notification.Name {
    static let newDataSource = Notification.Name("danis.newDataSource")
}
