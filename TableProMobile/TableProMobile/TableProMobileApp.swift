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

    var body: some Scene {
        WindowGroup {
            ConnectionListView()
                .environment(appState)
        }
    }
}
