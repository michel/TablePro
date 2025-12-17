//
//  DatabaseManager.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import Combine
import Foundation

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

        activeConnection = connection
        status = .connecting
        lastError = nil

        // Create SSH tunnel if needed
        var effectiveConnection = connection
        if connection.sshConfig.enabled {
            let sshPassword = ConnectionStorage.shared.loadSSHPassword(for: connection.id)
            let tunnelPort = try await SSHTunnelManager.shared.createTunnel(
                connectionId: connection.id,
                sshHost: connection.sshConfig.host,
                sshPort: connection.sshConfig.port,
                sshUsername: connection.sshConfig.username,
                authMethod: connection.sshConfig.authMethod,
                privateKeyPath: connection.sshConfig.privateKeyPath,
                sshPassword: sshPassword,
                remoteHost: connection.host,
                remotePort: connection.port
            )

            // Create a modified connection that uses the tunnel
            effectiveConnection = DatabaseConnection(
                id: connection.id,
                name: connection.name,
                host: "127.0.0.1",
                port: tunnelPort,
                database: connection.database,
                username: connection.username,
                type: connection.type,
                sshConfig: SSHConfiguration()  // Disable SSH for actual driver
            )
        }

        // Create appropriate driver with effective connection
        let driver = DatabaseDriverFactory.createDriver(for: effectiveConnection)
        activeDriver = driver

        do {
            try await driver.connect()
            status = driver.status
        } catch {
            // Close tunnel if connection failed
            if connection.sshConfig.enabled {
                Task {
                    try? await SSHTunnelManager.shared.closeTunnel(connectionId: connection.id)
                }
            }
            status = .error(error.localizedDescription)
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Disconnect from current database
    func disconnect() {
        // Close SSH tunnel if exists
        if let connection = activeConnection, connection.sshConfig.enabled {
            Task {
                try? await SSHTunnelManager.shared.closeTunnel(connectionId: connection.id)
            }
        }

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
    func testConnection(_ connection: DatabaseConnection, sshPassword: String? = nil) async throws
        -> Bool
    {
        // Create SSH tunnel if needed
        var tunnelPort: Int?
        if connection.sshConfig.enabled {
            let sshPwd = sshPassword ?? ConnectionStorage.shared.loadSSHPassword(for: connection.id)
            tunnelPort = try await SSHTunnelManager.shared.createTunnel(
                connectionId: connection.id,
                sshHost: connection.sshConfig.host,
                sshPort: connection.sshConfig.port,
                sshUsername: connection.sshConfig.username,
                authMethod: connection.sshConfig.authMethod,
                privateKeyPath: connection.sshConfig.privateKeyPath,
                sshPassword: sshPwd,
                remoteHost: connection.host,
                remotePort: connection.port
            )
        }

        defer {
            // Close tunnel after test
            if connection.sshConfig.enabled {
                Task {
                    try? await SSHTunnelManager.shared.closeTunnel(connectionId: connection.id)
                }
            }
        }

        // Create connection with tunnel port if applicable
        let testConnection: DatabaseConnection
        if let port = tunnelPort {
            testConnection = DatabaseConnection(
                id: connection.id,
                name: connection.name,
                host: "127.0.0.1",
                port: port,
                database: connection.database,
                username: connection.username,
                type: connection.type,
                sshConfig: SSHConfiguration()  // Disable SSH for the actual driver connection
            )
        } else {
            testConnection = connection
        }

        let driver = DatabaseDriverFactory.createDriver(for: testConnection)
        return try await driver.testConnection()
    }
}
