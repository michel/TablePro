//
//  ConnectionStorage.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import Foundation
import Security

/// Service for persisting database connections
final class ConnectionStorage {
    static let shared = ConnectionStorage()

    private let connectionsKey = "com.opentable.connections"
    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Connection CRUD

    /// Load all saved connections
    func loadConnections() -> [DatabaseConnection] {
        guard let data = defaults.data(forKey: connectionsKey) else {
            return []
        }

        do {
            let decoder = JSONDecoder()
            let storedConnections = try decoder.decode([StoredConnection].self, from: data)

            return storedConnections.map { stored in
                let connection = stored.toConnection()
                // Password is stored in Keychain, accessed when needed via loadPassword()
                _ = loadPassword(for: stored.id)  // Verify password exists
                return connection
            }
        } catch {
            print("Failed to load connections: \(error)")
            return []
        }
    }

    /// Save all connections
    func saveConnections(_ connections: [DatabaseConnection]) {
        let storedConnections = connections.map { StoredConnection(from: $0) }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(storedConnections)
            defaults.set(data, forKey: connectionsKey)
        } catch {
            print("Failed to save connections: \(error)")
        }
    }

    /// Add a new connection
    func addConnection(_ connection: DatabaseConnection, password: String? = nil) {
        var connections = loadConnections()
        connections.append(connection)
        saveConnections(connections)

        if let password = password, !password.isEmpty {
            savePassword(password, for: connection.id)
        }
    }

    /// Update an existing connection
    func updateConnection(_ connection: DatabaseConnection, password: String? = nil) {
        var connections = loadConnections()
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
            saveConnections(connections)

            if let password = password {
                if password.isEmpty {
                    deletePassword(for: connection.id)
                } else {
                    savePassword(password, for: connection.id)
                }
            }
        }
    }

    /// Delete a connection
    func deleteConnection(_ connection: DatabaseConnection) {
        var connections = loadConnections()
        connections.removeAll { $0.id == connection.id }
        saveConnections(connections)
        deletePassword(for: connection.id)
        deleteSSHPassword(for: connection.id)
    }

    // MARK: - Keychain (Password Storage)

    /// Save password to Keychain
    func savePassword(_ password: String, for connectionId: UUID) {
        let key = "com.opentable.password.\(connectionId.uuidString)"

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        guard let data = password.data(using: .utf8) else { return }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Load password from Keychain
    func loadPassword(for connectionId: UUID) -> String? {
        let key = "com.opentable.password.\(connectionId.uuidString)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
            let data = result as? Data,
            let password = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return password
    }

    /// Delete password from Keychain
    func deletePassword(for connectionId: UUID) {
        let key = "com.opentable.password.\(connectionId.uuidString)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - SSH Password Storage

    /// Save SSH password to Keychain
    func saveSSHPassword(_ password: String, for connectionId: UUID) {
        let key = "com.opentable.sshpassword.\(connectionId.uuidString)"

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        guard let data = password.data(using: .utf8) else { return }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Load SSH password from Keychain
    func loadSSHPassword(for connectionId: UUID) -> String? {
        let key = "com.opentable.sshpassword.\(connectionId.uuidString)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
            let data = result as? Data,
            let password = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return password
    }

    /// Delete SSH password from Keychain
    func deleteSSHPassword(for connectionId: UUID) {
        let key = "com.opentable.sshpassword.\(connectionId.uuidString)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Stored Connection (Codable wrapper)

private struct StoredConnection: Codable {
    let id: UUID
    let name: String
    let host: String
    let port: Int
    let database: String
    let username: String
    let type: String

    // SSH Configuration
    let sshEnabled: Bool
    let sshHost: String
    let sshPort: Int
    let sshUsername: String
    let sshAuthMethod: String
    let sshPrivateKeyPath: String
    let sshUseSSHConfig: Bool

    init(from connection: DatabaseConnection) {
        self.id = connection.id
        self.name = connection.name
        self.host = connection.host
        self.port = connection.port
        self.database = connection.database
        self.username = connection.username
        self.type = connection.type.rawValue

        // SSH Configuration
        self.sshEnabled = connection.sshConfig.enabled
        self.sshHost = connection.sshConfig.host
        self.sshPort = connection.sshConfig.port
        self.sshUsername = connection.sshConfig.username
        self.sshAuthMethod = connection.sshConfig.authMethod.rawValue
        self.sshPrivateKeyPath = connection.sshConfig.privateKeyPath
        self.sshUseSSHConfig = connection.sshConfig.useSSHConfig
    }

    func toConnection() -> DatabaseConnection {
        let sshConfig = SSHConfiguration(
            enabled: sshEnabled,
            host: sshHost,
            port: sshPort,
            username: sshUsername,
            authMethod: SSHAuthMethod(rawValue: sshAuthMethod) ?? .password,
            privateKeyPath: sshPrivateKeyPath,
            useSSHConfig: sshUseSSHConfig
        )

        return DatabaseConnection(
            id: id,
            name: name,
            host: host,
            port: port,
            database: database,
            username: username,
            type: DatabaseType(rawValue: type) ?? .mysql,
            sshConfig: sshConfig
        )
    }
}
