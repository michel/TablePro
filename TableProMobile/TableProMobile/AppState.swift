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
    let secureStore: KeychainSecureStore

    private let storage = ConnectionPersistence()

    init() {
        let driverFactory = IOSDriverFactory()
        let secureStore = KeychainSecureStore()
        self.secureStore = secureStore
        let sshProvider = IOSSSHProvider(secureStore: secureStore)
        self.sshProvider = sshProvider
        self.connectionManager = ConnectionManager(
            driverFactory: driverFactory,
            secureStore: secureStore,
            sshProvider: sshProvider
        )
        connections = storage.load()
        secureStore.cleanOrphanedCredentials(validConnectionIds: Set(connections.map(\.id)))

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

    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "com.TablePro.hasCompletedOnboarding") {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "com.TablePro.hasCompletedOnboarding") }
    }

    func removeConnection(_ connection: DatabaseConnection) {
        connections.removeAll { $0.id == connection.id }
        try? connectionManager.deletePassword(for: connection.id)
        try? secureStore.delete(forKey: "com.TablePro.sshpassword.\(connection.id.uuidString)")
        try? secureStore.delete(forKey: "com.TablePro.keypassphrase.\(connection.id.uuidString)")
        try? secureStore.delete(forKey: "com.TablePro.sshkeydata.\(connection.id.uuidString)")
        storage.save(connections)
        syncCoordinator.markDeleted(connection.id)
        syncCoordinator.scheduleSyncAfterChange(localConnections: connections)
    }
}

// MARK: - Persistence

private struct ConnectionPersistence {
    private var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let appDir = dir.appendingPathComponent("TableProMobile", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("connections.json")
    }

    func save(_ connections: [DatabaseConnection]) {
        guard let fileURL, let data = try? JSONEncoder().encode(connections) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func load() -> [DatabaseConnection] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let connections = try? JSONDecoder().decode([DatabaseConnection].self, from: data) else {
            return []
        }
        return connections
    }
}
