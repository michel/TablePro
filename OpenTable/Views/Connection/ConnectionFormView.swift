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
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer
            footer
        }
        .frame(width: 480, height: 520)
        .onAppear {
            loadConnection()
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
                
                FormField(label: type == .sqlite ? "File Path" : "Database", icon: type == .sqlite ? "doc" : "cylinder") {
                    HStack {
                        TextField(type == .sqlite ? "/path/to/database.sqlite" : "database_name", text: $database)
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
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            // Test connection
            Button(action: testConnection) {
                HStack(spacing: 6) {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: testResultIcon)
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
        .padding(16)
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
        !name.isEmpty && (type == .sqlite ? !database.isEmpty : !host.isEmpty)
    }
    
    private var testResultIcon: String {
        switch testResult {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .none: return "bolt.horizontal"
        }
    }
    
    private func loadConnection() {
        name = connection.name
        host = connection.host
        port = connection.port > 0 ? String(connection.port) : ""
        database = connection.database
        username = connection.username
        type = connection.type
    }
    
    private func saveConnection() {
        let updated = DatabaseConnection(
            id: connection.id,
            name: name,
            host: host,
            port: Int(port) ?? 0,
            database: database,
            username: username,
            type: type
        )
        onSave(updated)
        dismiss()
    }
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        
        // Build connection from form values
        let testConn = DatabaseConnection(
            name: name,
            host: host,
            port: Int(port) ?? 0,
            database: database,
            username: username,
            type: type
        )
        
        Task {
            do {
                let success = try await DatabaseManager.shared.testConnection(testConn)
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
        onDelete: { }
    )
}
