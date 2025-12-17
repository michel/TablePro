//
//  DatabaseConnection.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import Foundation

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
    
    init(
        id: UUID = UUID(),
        name: String,
        host: String = "localhost",
        port: Int = 3306,
        database: String = "",
        username: String = "root",
        type: DatabaseType = .mysql
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.database = database
        self.username = username
        self.type = type
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
        )
    ]
}
