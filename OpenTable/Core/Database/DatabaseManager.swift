//
//  DatabaseManager.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import Foundation
import Combine

/// Manages database connections and active drivers
@MainActor
final class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    
    /// Currently active driver
    @Published private(set) var activeDriver: DatabaseDriver?
    
    /// Connection status of active driver
    @Published private(set) var status: ConnectionStatus = .disconnected
    
    /// Last error message
    @Published private(set) var lastError: String?
    
    /// Currently connected connection
    @Published private(set) var activeConnection: DatabaseConnection?
    
    private init() {}
    
    // MARK: - Connection Management
    
    /// Connect to a database
    func connect(to connection: DatabaseConnection) async throws {
        // Disconnect existing connection
        disconnect()
        
        // Create appropriate driver
        let driver = DatabaseDriverFactory.createDriver(for: connection)
        activeDriver = driver
        activeConnection = connection
        status = .connecting
        lastError = nil
        
        do {
            try await driver.connect()
            status = driver.status
        } catch {
            status = .error(error.localizedDescription)
            lastError = error.localizedDescription
            throw error
        }
    }
    
    /// Disconnect from current database
    func disconnect() {
        activeDriver?.disconnect()
        activeDriver = nil
        activeConnection = nil
        status = .disconnected
        lastError = nil
    }
    
    /// Execute a query on the active connection
    func execute(query: String) async throws -> QueryResult {
        guard let driver = activeDriver else {
            throw DatabaseError.notConnected
        }
        
        return try await driver.execute(query: query)
    }
    
    /// Fetch tables from the active connection
    func fetchTables() async throws -> [TableInfo] {
        guard let driver = activeDriver else {
            throw DatabaseError.notConnected
        }
        
        return try await driver.fetchTables()
    }
    
    /// Fetch columns for a table
    func fetchColumns(table: String) async throws -> [ColumnInfo] {
        guard let driver = activeDriver else {
            throw DatabaseError.notConnected
        }
        
        return try await driver.fetchColumns(table: table)
    }
    
    /// Test a connection without keeping it open
    func testConnection(_ connection: DatabaseConnection) async throws -> Bool {
        let driver = DatabaseDriverFactory.createDriver(for: connection)
        return try await driver.testConnection()
    }
}
