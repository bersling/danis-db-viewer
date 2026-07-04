import SwiftUI

/// Root layout: explorer tree left, editor tabs right — the IntelliJ Database
/// tool window arrangement.
struct MainView: View {
    @EnvironmentObject var connectionStore: ConnectionStore
    @EnvironmentObject var tabs: TabManager

    var body: some View {
        NavigationSplitView {
            ExplorerView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 480)
        } detail: {
            EditorAreaView()
        }
        .background(Theme.editorBackground)
    }
}
