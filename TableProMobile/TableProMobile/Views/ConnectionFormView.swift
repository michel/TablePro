//
//  ConnectionFormView.swift
//  TableProMobile
//

import SwiftUI
import TableProModels

struct ConnectionFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: DatabaseType = .mysql
    @State private var host = "127.0.0.1"
    @State private var port = "3306"
    @State private var username = ""
    @State private var password = ""
    @State private var database = ""
    @State private var sslEnabled = false

    var onSave: (DatabaseConnection) -> Void

    private let databaseTypes: [(DatabaseType, String)] = [
        (.mysql, "MySQL"),
        (.postgresql, "PostgreSQL"),
        (.sqlite, "SQLite"),
        (.redis, "Redis"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.never)

                    Picker("Database Type", selection: $type) {
                        ForEach(databaseTypes, id: \.0.rawValue) { dbType, label in
                            Text(label).tag(dbType)
                        }
                    }
                    .onChange(of: type) { _, newType in
                        updateDefaultPort(for: newType)
                    }
                }

                if type != .sqlite {
                    Section("Server") {
                        TextField("Host", text: $host)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)

                        TextField("Port", text: $port)
                            .keyboardType(.numberPad)

                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)

                        SecureField("Password", text: $password)
                    }
                }

                Section("Database") {
                    TextField(type == .sqlite ? "File Path" : "Database Name", text: $database)
                        .textInputAutocapitalization(.never)
                }

                if type != .sqlite && type != .redis {
                    Section {
                        Toggle("SSL", isOn: $sslEnabled)
                    }
                }
            }
            .navigationTitle("New Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(host.isEmpty && type != .sqlite)
                }
            }
        }
    }

    private func updateDefaultPort(for type: DatabaseType) {
        switch type {
        case .mysql, .mariadb: port = "3306"
        case .postgresql: port = "5432"
        case .redis: port = "6379"
        case .sqlite: port = ""
        default: port = "3306"
        }
    }

    private func save() {
        let connection = DatabaseConnection(
            name: name.isEmpty ? host : name,
            type: type,
            host: host,
            port: Int(port) ?? 3306,
            username: username,
            database: database,
            sslEnabled: sslEnabled
        )
        // TODO: Store password in KeychainSecureStore
        onSave(connection)
    }
}
