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
            Group {
                if appState.hasCompletedOnboarding {
                    ConnectionListView()
                        .environment(appState)
                } else {
                    OnboardingView()
                        .environment(appState)
                }
            }
            .onOpenURL { url in
                guard url.scheme == "tablepro",
                      url.host == "connect",
                      let uuidString = url.pathComponents.dropFirst().first,
                      let uuid = UUID(uuidString: uuidString) else { return }
                appState.pendingConnectionId = uuid
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                syncTask?.cancel()
                syncTask = Task {
                    await appState.syncCoordinator.sync(
                        localConnections: appState.connections,
                        localGroups: appState.groups,
                        localTags: appState.tags
                    )
                }
            case .background:
                Task { await appState.connectionManager.disconnectAll() }
            default:
                break
            }
        }
    }
}
