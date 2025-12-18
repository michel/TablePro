//
//  OpenTableApp.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import SwiftUI

@main
struct OpenTableApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // Replace New Item menu
            CommandGroup(replacing: .newItem) {
                Button("New Connection...") {
                    NotificationCenter.default.post(name: .newConnection, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            // File menu - Save & Close
            CommandGroup(after: .newItem) {
                Button("Save Changes") {
                    print("DEBUG: Save Changes menu item clicked, posting .saveChanges notification")
                    NotificationCenter.default.post(name: .saveChanges, object: nil)
                }
                .keyboardShortcut(KeyboardShortcut("s", modifiers: .command))
                
                Button("Close Tab") {
                    NotificationCenter.default.post(name: .closeCurrentTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            
            // Query menu
            CommandMenu("Query") {
                Button("Execute Query") {
                    NotificationCenter.default.post(name: .executeQuery, object: nil)
                }
                .keyboardShortcut(.return, modifiers: .command)
                
                Button("Format Query") {
                    NotificationCenter.default.post(name: .formatQuery, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Delete Selected Rows") {
                    NotificationCenter.default.post(name: .deleteSelectedRows, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [])
                
                Button("Clear Query") {
                    NotificationCenter.default.post(name: .clearQuery, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
            
            // View menu additions
            CommandGroup(after: .sidebar) {
                Button("Toggle Table Browser") {
                    NotificationCenter.default.post(name: .toggleTableBrowser, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                
                Button("Refresh") {
                    NotificationCenter.default.post(name: .refreshData, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newConnection = Notification.Name("newConnection")
    static let executeQuery = Notification.Name("executeQuery")
    static let formatQuery = Notification.Name("formatQuery")
    static let clearQuery = Notification.Name("clearQuery")
    static let toggleTableBrowser = Notification.Name("toggleTableBrowser")
    static let closeCurrentTab = Notification.Name("closeCurrentTab")
    static let deselectConnection = Notification.Name("deselectConnection")
    static let saveChanges = Notification.Name("saveChanges")
    static let refreshData = Notification.Name("refreshData")
    static let deleteSelectedRows = Notification.Name("deleteSelectedRows")
    static let refreshAll = Notification.Name("refreshAll")
}
