import SwiftUI
import UniformTypeIdentifiers

/// Add/edit data source sheet — IntelliJ's "Data Sources and Drivers" dialog,
/// reduced to one connection's General tab.
struct DataSourceDialog: View {
    @EnvironmentObject var connectionStore: ConnectionStore
    @EnvironmentObject var sessions: SessionRegistry
    @Environment(\.dismiss) private var dismiss

    @State var config: DataSourceConfig
    @State private var password: String = ""
    @State private var passwordLoaded = false
    @State private var testing = false
    @State private var testResult: (success: Bool, message: String)?

    private var isNew: Bool { !connectionStore.connections.contains { $0.id == config.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(isNew ? "New" : "Edit") Data Source — \(config.kind.displayName)")
                .font(.system(size: 13, weight: .semibold))
                .padding(16)

            Divider()

            Form {
                TextField("Name:", text: $config.name)

                if config.kind == .sqlite {
                    HStack {
                        TextField("File:", text: $config.filePath)
                            .font(Theme.monoFont)
                        Button("…") { pickFile() }
                    }
                } else {
                    TextField("Host:", text: $config.host)
                    TextField("Port:", value: $config.port, format: .number.grouping(.never))
                    TextField("User:", text: $config.user)
                    SecureField("Password:", text: $password)
                    TextField("Database:", text: $config.database)
                }

                Picker("Color:", selection: $config.color) {
                    ForEach(DataSourceColor.allCases) { c in
                        Text(c.rawValue.capitalized).tag(c)
                    }
                }
                TextField("Comment:", text: $config.comment)
            }
            .formStyle(.columns)
            .textFieldStyle(.roundedBorder)
            .padding(16)

            if let result = testResult {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.success ? .green : .red)
                    ScrollView {
                        Text(result.success ? "Connection successful" : result.message)
                            .font(.system(size: 11))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: result.success ? 20 : 150)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Divider()

            HStack {
                Button {
                    testConnection()
                } label: {
                    if testing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Test Connection")
                    }
                }
                .disabled(testing)

                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(config.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 480)
        .onAppear {
            if !passwordLoaded {
                password = SecretStore.password(for: config.id)
                passwordLoaded = true
            }
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite"), UTType(filenameExtension: "db"),
                                     UTType(filenameExtension: "sqlite3"), UTType.data].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url {
            config.filePath = url.path
            if config.name.isEmpty || config.name == "SQLite" {
                config.name = url.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func testConnection() {
        testing = true
        testResult = nil
        let cfg = config
        let pwd = password
        Task {
            let error = await SessionRegistry.test(config: cfg, password: pwd)
            testing = false
            testResult = (error == nil, error ?? "")
        }
    }

    private func save() {
        connectionStore.upsert(config, password: password)
        // Force reconnect with new settings on next use.
        Task { await sessions.disconnect(config.id) }
        dismiss()
    }
}
