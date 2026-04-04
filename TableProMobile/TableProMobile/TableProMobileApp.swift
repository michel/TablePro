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
    @State private var syncTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if appState.hasCompletedOnboarding {
                ConnectionListView()
                    .environment(appState)
            } else {
                OnboardingView()
                    .environment(appState)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                syncTask?.cancel()
                syncTask = Task { await appState.syncCoordinator.sync(localConnections: appState.connections) }
            case .background:
                Task { await appState.connectionManager.disconnectAll() }
            default:
                break
            }
        }
    }
}
