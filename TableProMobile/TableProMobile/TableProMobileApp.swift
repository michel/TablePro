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
            if phase == .background {
                Task {
                    await appState.connectionManager.disconnectAll()
                }
            }
        }
    }
}
