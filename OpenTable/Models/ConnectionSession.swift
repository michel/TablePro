//
//  ConnectionSession.swift
//  OpenTable
//
//  Model representing an active database connection session with all its state
//

import Foundation

/// Represents an active database connection session with all associated state
struct ConnectionSession: Identifiable {
    let id: UUID  // Same as connection.id
    let connection: DatabaseConnection
    var driver: DatabaseDriver?
    var status: ConnectionStatus = .disconnected
    var lastError: String?
    
    // Per-connection state
    var tables: [TableInfo] = []
    var selectedTable: TableInfo?
    var tabs: [QueryTab] = []
    var selectedTabId: UUID?
    var pendingTruncates: Set<String> = []
    var pendingDeletes: Set<String> = []
    
    // Metadata
    let connectedAt: Date
    var lastActiveAt: Date
    
    init(connection: DatabaseConnection, driver: DatabaseDriver? = nil) {
        self.id = connection.id
        self.connection = connection
        self.driver = driver
        self.connectedAt = Date()
        self.lastActiveAt = Date()
    }
    
    /// Update last active timestamp
    mutating func markActive() {
        lastActiveAt = Date()
    }
    
    /// Check if session is currently connected
    var isConnected: Bool {
        if case .connected = status {
            return true
        }
        return false
    }
}
