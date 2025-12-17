//
//  DatabaseConnection.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import Foundation

// MARK: - SSH Configuration

/// SSH authentication method
enum SSHAuthMethod: String, CaseIterable, Identifiable, Codable {
    case password = "Password"
    case privateKey = "Private Key"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .password: return "key.fill"
        case .privateKey: return "doc.text.fill"
        }
    }
}

/// SSH tunnel configuration for database connections
struct SSHConfiguration: Codable, Hashable {
    var enabled: Bool = false
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var authMethod: SSHAuthMethod = .password
    var privateKeyPath: String = ""  // Path to identity file (e.g., ~/.ssh/id_rsa)
    var useSSHConfig: Bool = true  // Auto-fill from ~/.ssh/config when selecting host

    /// Check if SSH configuration is complete enough for connection
    var isValid: Bool {
        guard enabled else { return true }  // Not enabled = valid (skip SSH)
        guard !host.isEmpty, !username.isEmpty else { return false }

        switch authMethod {
        case .password:
            return true  // Password will be provided separately
        case .privateKey:
            return !privateKeyPath.isEmpty
        }
    }
}

// MARK: - Database Type

/// Represents the type of database
enum DatabaseType: String, CaseIterable, Identifiable, Codable {
    case mysql = "MySQL"
    case mariadb = "MariaDB"
    case postgresql = "PostgreSQL"
    case sqlite = "SQLite"

    var id: String { rawValue }

    /// SF Symbol name for each database type
    var iconName: String {
        switch self {
        case .mysql, .mariadb:
            return "cylinder.split.1x2.fill"
        case .postgresql:
            return "server.rack"
        case .sqlite:
            return "doc.fill"
        }
    }

    /// Default port for each database type
    var defaultPort: Int {
        switch self {
        case .mysql, .mariadb: return 3306
        case .postgresql: return 5432
        case .sqlite: return 0
        }
    }
}

/// Model representing a database connection
struct DatabaseConnection: Identifiable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var database: String
    var username: String
    var type: DatabaseType
    var sshConfig: SSHConfiguration

    init(
        id: UUID = UUID(),
        name: String,
        host: String = "localhost",
        port: Int = 3306,
        database: String = "",
        username: String = "root",
        type: DatabaseType = .mysql,
        sshConfig: SSHConfiguration = SSHConfiguration()
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.database = database
        self.username = username
        self.type = type
        self.sshConfig = sshConfig
    }
}

// MARK: - Sample Data for Development

extension DatabaseConnection {
    static let sampleConnections: [DatabaseConnection] = [
        DatabaseConnection(
            name: "Local MySQL",
            host: "localhost",
            port: 3306,
            database: "app_development",
            username: "root",
            type: .mysql
        ),
        DatabaseConnection(
            name: "Production PostgreSQL",
            host: "db.example.com",
            port: 5432,
            database: "production",
            username: "admin",
            type: .postgresql
        ),
        DatabaseConnection(
            name: "SQLite Database",
            host: "",
            port: 0,
            database: "~/Documents/data.sqlite",
            username: "",
            type: .sqlite
        ),
    ]
}
