//
//  ContentView.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import SwiftUI

struct ContentView: View {
    @State private var connections: [DatabaseConnection] = []
    @State private var selectedConnection: DatabaseConnection?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showNewConnectionSheet = false
    @State private var hasLoaded = false
    
    private let storage = ConnectionStorage.shared
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                connections: Binding(
                    get: { connections },
                    set: { newValue in
                        connections = newValue
                        // Save when connections change via sidebar
                        if hasLoaded {
                            storage.saveConnections(newValue)
                        }
                    }
                ),
                selectedConnection: $selectedConnection
            )
        } detail: {
            if let connection = selectedConnection {
                MainContentView(connection: connection)
                    .id(connection.id) // Force recreate when connection changes
            } else {
                WelcomeView {
                    showNewConnectionSheet = true
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showNewConnectionSheet) {
            ConnectionFormView(
                connection: .constant(DatabaseConnection(name: "")),
                isNew: true,
                onSave: { connection in
                    connections.append(connection)
                    selectedConnection = connection
                    storage.saveConnections(connections)
                }
            )
        }
        .onAppear {
            loadConnections()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newConnection)) { _ in
            showNewConnectionSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .deselectConnection)) { _ in
            selectedConnection = nil
        }
    }
    
    // MARK: - Persistence
    
    private func loadConnections() {
        guard !hasLoaded else { return }
        
        let saved = storage.loadConnections()
        if saved.isEmpty {
            connections = DatabaseConnection.sampleConnections
            storage.saveConnections(connections)
        } else {
            connections = saved
        }
        hasLoaded = true
    }
}

#Preview {
    ContentView()
}
