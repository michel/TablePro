//
//  OpenTableApp.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import Combine
import SwiftUI

// MARK: - App State for Menu Commands

final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var isConnected: Bool = false
}

// MARK: - App

@main
struct OpenTableApp: App {
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("New Connection...") {
                    NotificationCenter.default.post(name: .newConnection, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    NotificationCenter.default.post(name: .newTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!appState.isConnected)

                Divider()

                Button("Save Changes") {
                    NotificationCenter.default.post(name: .saveChanges, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!appState.isConnected)

                Button("Close Tab") {
                    NotificationCenter.default.post(name: .closeCurrentTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("Refresh") {
                    NotificationCenter.default.post(name: .refreshData, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!appState.isConnected)
            }

            // View menu
            CommandGroup(after: .sidebar) {
                Button("Toggle Table Browser") {
                    NotificationCenter.default.post(name: .toggleTableBrowser, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(!appState.isConnected)

                Button("Toggle Inspector") {
                    NotificationCenter.default.post(name: .toggleRightSidebar, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(!appState.isConnected)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newConnection = Notification.Name("newConnection")
    static let newTab = Notification.Name("newTab")
    static let closeCurrentTab = Notification.Name("closeCurrentTab")
    static let deselectConnection = Notification.Name("deselectConnection")
    static let saveChanges = Notification.Name("saveChanges")
    static let refreshData = Notification.Name("refreshData")
    static let refreshAll = Notification.Name("refreshAll")
    static let toggleTableBrowser = Notification.Name("toggleTableBrowser")
    static let toggleRightSidebar = Notification.Name("toggleRightSidebar")
    static let executeQuery = Notification.Name("executeQuery")
    static let formatQuery = Notification.Name("formatQuery")
    static let clearQuery = Notification.Name("clearQuery")
    static let deleteSelectedRows = Notification.Name("deleteSelectedRows")
}
