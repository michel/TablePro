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
        self.connectionManager = ConnectionManager(
            driverFactory: driverFactory,
            secureStore: secureStore
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

    func disconnectAll() {
        Task {
            await connectionManager.disconnectAll()
        }
    }
}

// MARK: - Persistence

private struct ConnectionPersistence {
    private let key = "com.TablePro.Mobile.connections"

    func save(_ connections: [DatabaseConnection]) {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func load() -> [DatabaseConnection] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let connections = try? JSONDecoder().decode([DatabaseConnection].self, from: data) else {
            return []
        }
        return connections
    }
}
