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

    init() {
        let pluginLoader = StaticPluginLoader()
        let secureStore = KeychainSecureStore()
        self.connectionManager = ConnectionManager(
            pluginLoader: pluginLoader,
            secureStore: secureStore
        )

        loadSampleConnections()
    }

    private func loadSampleConnections() {
        // TODO: Load from persistent storage / iCloud sync
        // For now, empty — user adds connections manually
    }

    func addConnection(_ connection: DatabaseConnection) {
        connections.append(connection)
    }

    func removeConnection(_ connection: DatabaseConnection) {
        connections.removeAll { $0.id == connection.id }
    }
}
