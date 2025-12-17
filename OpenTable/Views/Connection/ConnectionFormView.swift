//
//  ConnectionFormView.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import SwiftUI
import UniformTypeIdentifiers

/// Form for creating or editing a database connection
struct ConnectionFormView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var connection: DatabaseConnection
    let isNew: Bool
    var onSave: (DatabaseConnection) -> Void
    var onDelete: (() -> Void)?

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var database: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var type: DatabaseType = .mysql

    // SSH Configuration
    @State private var sshEnabled: Bool = false
    @State private var sshHost: String = ""
    @State private var sshPort: String = "22"
    @State private var sshUsername: String = ""
    @State private var sshPassword: String = ""
    @State private var sshAuthMethod: SSHAuthMethod = .password
    @State private var sshPrivateKeyPath: String = ""
    @State private var sshConfigEntries: [SSHConfigEntry] = []
    @State private var selectedSSHConfigHost: String = ""

    @State private var isTesting: Bool = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Form content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    generalSection
                    connectionSection
                    authSection
                    if type != .sqlite {
                        sshSection
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer
            footer
        }
        .frame(width: 520, height: 680)
        .onAppear {
            loadConnection()
            loadSSHConfig()
        }
        .onChange(of: type) { _, newType in
            // Auto-update port when type changes
            port = String(newType.defaultPort)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: iconForType(type))
                .font(.title2)
                .foregroundStyle(colorForType(type))
                .frame(width: 32, height: 32)
                .background(colorForType(type).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(isNew ? "New Connection" : "Edit Connection")
                .font(.headline)

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - General Section

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                FormField(label: "Name", icon: "tag") {
                    TextField("Connection name", text: $name)
                        .textFieldStyle(.plain)
                }

                FormField(label: "Type", icon: "cylinder.split.1x2") {
                    Picker("", selection: $type) {
                        ForEach(DatabaseType.allCases) { dbType in
                            Label(dbType.rawValue, systemImage: iconForType(dbType))
                                .tag(dbType)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                if type != .sqlite {
                    FormField(label: "Host", icon: "server.rack") {
                        TextField("localhost", text: $host)
                            .textFieldStyle(.plain)
                    }

                    FormField(label: "Port", icon: "number") {
                        TextField(defaultPort, text: $port)
                            .textFieldStyle(.plain)
                    }
                }

                FormField(
                    label: type == .sqlite ? "File Path" : "Database",
                    icon: type == .sqlite ? "doc" : "cylinder"
                ) {
                    HStack {
                        TextField(
                            type == .sqlite ? "/path/to/database.sqlite" : "database_name",
                            text: $database
                        )
                        .textFieldStyle(.plain)

                        if type == .sqlite {
                            Button("Browse...") {
                                browseForFile()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Auth Section

    @ViewBuilder
    private var authSection: some View {
        if type != .sqlite {
            VStack(alignment: .leading, spacing: 12) {
                Text("Authentication")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    FormField(label: "Username", icon: "person") {
                        TextField("root", text: $username)
                            .textFieldStyle(.plain)
                    }

                    FormField(label: "Password", icon: "lock") {
                        SecureField("••••••••", text: $password)
                            .textFieldStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - SSH Section

    private var sshSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SSH Tunnel")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("", isOn: $sshEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if sshEnabled {
                VStack(spacing: 12) {
                    // SSH Host - from config or manual
                    if !sshConfigEntries.isEmpty {
                        FormField(label: "SSH Host", icon: "desktopcomputer") {
                            HStack {
                                Picker("", selection: $selectedSSHConfigHost) {
                                    Text("Manual").tag("")
                                    ForEach(sshConfigEntries) { entry in
                                        Text(entry.displayName).tag(entry.host)
                                    }
                                }
                                .labelsHidden()
                                .fixedSize()
                                .onChange(of: selectedSSHConfigHost) { _, newValue in
                                    applySSHConfigEntry(newValue)
                                }

                                Spacer()
                            }
                        }
                    }

                    // Manual SSH Host input
                    if selectedSSHConfigHost.isEmpty || sshConfigEntries.isEmpty {
                        FormField(label: "SSH Host", icon: "desktopcomputer") {
                            TextField("ssh.example.com", text: $sshHost)
                                .textFieldStyle(.plain)
                        }
                    }

                    FormField(label: "SSH Port", icon: "number") {
                        TextField("22", text: $sshPort)
                            .textFieldStyle(.plain)
                    }

                    FormField(label: "SSH User", icon: "person") {
                        TextField("username", text: $sshUsername)
                            .textFieldStyle(.plain)
                    }

                    // Auth method picker
                    FormField(label: "Auth", icon: "key") {
                        HStack {
                            Picker("", selection: $sshAuthMethod) {
                                ForEach(SSHAuthMethod.allCases) { method in
                                    Label(method.rawValue, systemImage: method.iconName)
                                        .tag(method)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize()

                            Spacer()
                        }
                    }

                    // Password or Private Key based on auth method
                    if sshAuthMethod == .password {
                        FormField(label: "SSH Pass", icon: "lock.shield") {
                            SecureField("••••••••", text: $sshPassword)
                                .textFieldStyle(.plain)
                        }
                    } else {
                        FormField(label: "Key File", icon: "doc.text") {
                            HStack {
                                TextField("~/.ssh/id_rsa", text: $sshPrivateKeyPath)
                                    .textFieldStyle(.plain)

                                Button("Browse") {
                                    browseForPrivateKey()
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Error message
            if case .failure(let message) = testResult {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            HStack {
                // Test connection
                Button(action: testConnection) {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: testResultIcon)
                                .foregroundStyle(testResultColor)
                        }
                        Text("Test Connection")
                    }
                }
                .disabled(isTesting || !isValid)

                Spacer()

                // Delete button (edit mode only)
                if !isNew, let onDelete = onDelete {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }

                // Cancel
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                // Save
                Button(isNew ? "Create" : "Save") {
                    saveConnection()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private var defaultPort: String {
        switch type {
        case .mysql, .mariadb: return "3306"
        case .postgresql: return "5432"
        case .sqlite: return ""
        }
    }

    private var isValid: Bool {
        let basicValid = !name.isEmpty && (type == .sqlite ? !database.isEmpty : !host.isEmpty)
        if sshEnabled {
            let sshValid = !sshHost.isEmpty && !sshUsername.isEmpty
            let authValid = sshAuthMethod == .password || !sshPrivateKeyPath.isEmpty
            return basicValid && sshValid && authValid
        }
        return basicValid
    }

    private var testResultIcon: String {
        switch testResult {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .none: return "bolt.horizontal"
        }
    }

    private var testResultColor: Color {
        switch testResult {
        case .success: return .green
        case .failure: return .red
        case .none: return .secondary
        }
    }

    private func loadConnection() {
        name = connection.name
        host = connection.host
        port = connection.port > 0 ? String(connection.port) : ""
        database = connection.database
        username = connection.username
        type = connection.type

        // Load SSH configuration
        sshEnabled = connection.sshConfig.enabled
        sshHost = connection.sshConfig.host
        sshPort = String(connection.sshConfig.port)
        sshUsername = connection.sshConfig.username
        sshAuthMethod = connection.sshConfig.authMethod
        sshPrivateKeyPath = connection.sshConfig.privateKeyPath

        // Load SSH password from Keychain
        if let savedSSHPassword = ConnectionStorage.shared.loadSSHPassword(for: connection.id) {
            sshPassword = savedSSHPassword
        }

        // Load DB password from Keychain
        if let savedPassword = ConnectionStorage.shared.loadPassword(for: connection.id) {
            password = savedPassword
        }
    }

    private func saveConnection() {
        let sshConfig = SSHConfiguration(
            enabled: sshEnabled,
            host: sshHost,
            port: Int(sshPort) ?? 22,
            username: sshUsername,
            authMethod: sshAuthMethod,
            privateKeyPath: sshPrivateKeyPath,
            useSSHConfig: !selectedSSHConfigHost.isEmpty
        )

        let updated = DatabaseConnection(
            id: connection.id,
            name: name,
            host: host,
            port: Int(port) ?? 0,
            database: database,
            username: username,
            type: type,
            sshConfig: sshConfig
        )

        // Save passwords to Keychain
        if !password.isEmpty {
            ConnectionStorage.shared.savePassword(password, for: updated.id)
        }
        if sshEnabled && sshAuthMethod == .password && !sshPassword.isEmpty {
            ConnectionStorage.shared.saveSSHPassword(sshPassword, for: updated.id)
        }

        onSave(updated)
        dismiss()
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        // Build SSH config
        let sshConfig = SSHConfiguration(
            enabled: sshEnabled,
            host: sshHost,
            port: Int(sshPort) ?? 22,
            username: sshUsername,
            authMethod: sshAuthMethod,
            privateKeyPath: sshPrivateKeyPath,
            useSSHConfig: !selectedSSHConfigHost.isEmpty
        )

        // Build connection from form values
        let testConn = DatabaseConnection(
            name: name,
            host: host,
            port: Int(port) ?? 0,
            database: database,
            username: username,
            type: type,
            sshConfig: sshConfig
        )

        Task {
            do {
                // Save passwords temporarily for test
                if !password.isEmpty {
                    ConnectionStorage.shared.savePassword(password, for: testConn.id)
                }
                if sshEnabled && sshAuthMethod == .password && !sshPassword.isEmpty {
                    ConnectionStorage.shared.saveSSHPassword(sshPassword, for: testConn.id)
                }

                let success = try await DatabaseManager.shared.testConnection(
                    testConn, sshPassword: sshPassword)
                await MainActor.run {
                    isTesting = false
                    testResult = success ? .success : .failure("Connection test failed")
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testResult = .failure(error.localizedDescription)
                }
            }
        }
    }

    private func browseForFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.database, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            database = url.path
        }
    }

    private func browseForPrivateKey() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh")
        panel.showsHiddenFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            sshPrivateKeyPath = url.path
        }
    }

    private func loadSSHConfig() {
        sshConfigEntries = SSHConfigParser.parse()
    }

    private func applySSHConfigEntry(_ host: String) {
        guard let entry = sshConfigEntries.first(where: { $0.host == host }) else {
            return
        }

        sshHost = entry.hostname ?? entry.host
        if let port = entry.port {
            sshPort = String(port)
        }
        if let user = entry.user {
            sshUsername = user
        }
        if let keyPath = entry.identityFile {
            sshPrivateKeyPath = keyPath
            sshAuthMethod = .privateKey
        }
    }

    private func iconForType(_ type: DatabaseType) -> String {
        type.iconName
    }

    private func colorForType(_ type: DatabaseType) -> Color {
        type.themeColor
    }
}

// MARK: - Form Field Component

struct FormField<Content: View>: View {
    let label: String
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            Text(label)
                .frame(width: 80, alignment: .leading)
                .foregroundStyle(.secondary)

            content()
                .frame(maxWidth: .infinity)
        }
    }
}

#Preview("New Connection") {
    ConnectionFormView(
        connection: .constant(DatabaseConnection(name: "")),
        isNew: true,
        onSave: { _ in }
    )
}

#Preview("Edit Connection") {
    ConnectionFormView(
        connection: .constant(DatabaseConnection.sampleConnections[0]),
        isNew: false,
        onSave: { _ in },
        onDelete: {}
    )
}
