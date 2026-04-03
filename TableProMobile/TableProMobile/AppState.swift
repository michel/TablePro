//
//  AppState.swift
//  TableProMobile
//

import Foundation
import Observation
import TableProDatabase
import TableProModels

@MainActor @Observable
final class AppState {
    var connections: [DatabaseConnection] = []
    let connectionManager: ConnectionManager
    let syncCoordinator = IOSSyncCoordinator()
    let sshProvider: IOSSSHProvider

    private let storage = ConnectionPersistence()

    init() {
        let driverFactory = IOSDriverFactory()
        let secureStore = KeychainSecureStore()
        let sshProvider = IOSSSHProvider(secureStore: secureStore)
        self.sshProvider = sshProvider
        self.connectionManager = ConnectionManager(
            driverFactory: driverFactory,
            secureStore: secureStore,
            sshProvider: sshProvider
        )
        connections = storage.load()

        syncCoordinator.onConnectionsChanged = { [weak self] merged in
            guard let self else { return }
            self.connections = merged
            self.storage.save(merged)
        }
    }

    func addConnection(_ connection: DatabaseConnection) {
        connections.append(connection)
        storage.save(connections)
        syncCoordinator.markDirty(connection.id)
        syncCoordinator.scheduleSyncAfterChange(localConnections: connections)
    }

    func updateConnection(_ connection: DatabaseConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
            storage.save(connections)
            syncCoordinator.markDirty(connection.id)
            syncCoordinator.scheduleSyncAfterChange(localConnections: connections)
        }
    }

    func removeConnection(_ connection: DatabaseConnection) {
        connections.removeAll { $0.id == connection.id }
        try? connectionManager.deletePassword(for: connection.id)
        let secureStore = KeychainSecureStore()
        try? secureStore.delete(forKey: "com.TablePro.sshpassword.\(connection.id.uuidString)")
        try? secureStore.delete(forKey: "com.TablePro.keypassphrase.\(connection.id.uuidString)")
        storage.save(connections)
        syncCoordinator.markDeleted(connection.id)
        syncCoordinator.scheduleSyncAfterChange(localConnections: connections)
    }
}

// MARK: - Persistence

private struct ConnectionPersistence {
    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TableProMobile", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("connections.json")
    }

    func save(_ connections: [DatabaseConnection]) {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func load() -> [DatabaseConnection] {
        guard let data = try? Data(contentsOf: fileURL),
              let connections = try? JSONDecoder().decode([DatabaseConnection].self, from: data) else {
            return migrateFromUserDefaults()
        }
        let normalized = connections.map { conn -> DatabaseConnection in
            var c = conn
            c.type = conn.type.normalized
            return c
        }
        if normalized != connections { save(normalized) }
        return normalized
    }

    private func migrateFromUserDefaults() -> [DatabaseConnection] {
        let key = "com.TablePro.Mobile.connections"
        guard let data = UserDefaults.standard.data(forKey: key),
              let connections = try? JSONDecoder().decode([DatabaseConnection].self, from: data) else {
            return []
        }
        save(connections)
        UserDefaults.standard.removeObject(forKey: key)
        return connections
    }
}
