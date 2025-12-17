//
//  DatabaseDriver.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import Foundation

/// Protocol defining database driver operations
protocol DatabaseDriver: AnyObject {
    /// The connection configuration
    var connection: DatabaseConnection { get }
    
    /// Current connection status
    var status: ConnectionStatus { get }
    
    /// Connect to the database
    func connect() async throws
    
    /// Disconnect from the database
    func disconnect()
    
    /// Execute a SQL query and return results
    func execute(query: String) async throws -> QueryResult
    
    /// Fetch all tables in the database
    func fetchTables() async throws -> [TableInfo]
    
    /// Fetch columns for a specific table
    func fetchColumns(table: String) async throws -> [ColumnInfo]
    
    /// Fetch indexes for a specific table
    func fetchIndexes(table: String) async throws -> [IndexInfo]
    
    /// Fetch foreign keys for a specific table
    func fetchForeignKeys(table: String) async throws -> [ForeignKeyInfo]
    
    /// Test the connection (connect and immediately disconnect)
    func testConnection() async throws -> Bool
    
    // MARK: - Paginated Query Support
    
    /// Fetch total row count for a query (wraps with COUNT(*))
    func fetchRowCount(query: String) async throws -> Int
    
    /// Fetch rows with LIMIT/OFFSET pagination
    func fetchRows(query: String, offset: Int, limit: Int) async throws -> QueryResult
}

/// Default implementation for common operations
extension DatabaseDriver {
    func testConnection() async throws -> Bool {
        do {
            try await connect()
            disconnect()
            return true
        } catch {
            throw error
        }
    }
}

/// Factory for creating database drivers
enum DatabaseDriverFactory {
    static func createDriver(for connection: DatabaseConnection) -> DatabaseDriver {
        switch connection.type {
        case .sqlite:
            return SQLiteDriver(connection: connection)
        case .mysql, .mariadb:
            return MySQLDriver(connection: connection)
        case .postgresql:
            return PostgreSQLDriver(connection: connection)
        }
    }
}


