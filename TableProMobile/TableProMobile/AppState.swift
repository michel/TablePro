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

    private let storage = ConnectionPersistence()

    init() {
        let driverFactory = IOSDriverFactory()
        let secureStore = KeychainSecureStore()
        let sshProvider = IOSSSHProvider(secureStore: secureStore)
        self.connectionManager = ConnectionManager(
            driverFactory: driverFactory,
            secureStore: secureStore,
            sshProvider: sshProvider
        )
        connections = storage.load()
    }

    func addConnection(_ connection: DatabaseConnection) {
        connections.append(connection)
        storage.save(connections)
    }

    func updateConnection(_ connection: DatabaseConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
            storage.save(connections)
        }
    }

    func removeConnection(_ connection: DatabaseConnection) {
        connections.removeAll { $0.id == connection.id }
        try? connectionManager.deletePassword(for: connection.id)
        storage.save(connections)
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
        return connections
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
