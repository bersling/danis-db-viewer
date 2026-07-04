import SwiftUI

/// Read-only generated DDL for a table (IntelliJ "Go to DDL").
struct DDLView: View {
    @EnvironmentObject var sessions: SessionRegistry

    let dataSource: DataSourceConfig
    let schema: String
    let table: String

    @State private var ddl: String = ""
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        Group {
            if let error {
                Text(error).foregroundStyle(.red).padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(ddl)
                        .font(Theme.monoFont)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .background(Theme.editorBackground)
        .toolbar {
            ToolbarItem {
                Button {
                    copyToPasteboard(ddl)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy DDL")
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            do {
                let driver = try await sessions.driver(for: dataSource)
                ddl = try await driver.ddl(schema: schema, table: table)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
