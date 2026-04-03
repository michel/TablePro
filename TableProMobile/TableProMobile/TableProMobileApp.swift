//
//  TableProMobileApp.swift
//  TableProMobile
//

import SwiftUI
import TableProDatabase
import TableProModels

@main
struct TableProMobileApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ConnectionListView()
                .environment(appState)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await appState.syncCoordinator.sync(localConnections: appState.connections) }
            case .background:
                Task { await appState.connectionManager.disconnectAll() }
            default:
                break
            }
        }
    }
}
