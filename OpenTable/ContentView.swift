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
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var showNewConnectionSheet = false
    @State private var hasLoaded = false

    // Table state for sidebar
    @State private var tables: [TableInfo] = []
    @State private var selectedTable: TableInfo?
    @State private var pendingTruncates: Set<String> = []
    @State private var pendingDeletes: Set<String> = []

    private let storage = ConnectionStorage.shared

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // MARK: - Left Sidebar (Table Browser)
            SidebarView(
                tables: $tables,
                selectedTable: $selectedTable,
                activeTableName: selectedTable?.name,
                onOpenTable: { tableName in
                    // Table opening handled via selectedTable binding
                },
                pendingTruncates: $pendingTruncates,
                pendingDeletes: $pendingDeletes
            )
        } detail: {
            // MARK: - Main Content + Right Sidebar
            if selectedConnection != nil {
                MainContentView(
                    connection: selectedConnection!,
                    tables: $tables,
                    selectedTable: $selectedTable,
                    pendingTruncates: $pendingTruncates,
                    pendingDeletes: $pendingDeletes
                )
                .id(selectedConnection!.id)
            } else {
                WelcomeView(
                    connections: connections,
                    onSelectConnection: { connection in
                        selectedConnection = connection
                    },
                    onAddConnection: {
                        showNewConnectionSheet = true
                    }
                )
                .toolbar(.hidden)
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
            tables = []
            selectedTable = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTableBrowser)) { _ in
            // Toggle LEFT sidebar (table browser)
            guard selectedConnection != nil else { return }
            withAnimation {
                columnVisibility = columnVisibility == .all ? .detailOnly : .all
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleRightSidebar)) { _ in
            // Right sidebar not implemented - toolbar handles alert
        }
        .onChange(of: selectedConnection) { _, newConnection in
            withAnimation {
                // Hide left sidebar on welcome screen, show when connection is selected
                columnVisibility = newConnection == nil ? .detailOnly : .all
            }
            // Update app state for menu commands
            AppState.shared.isConnected = newConnection != nil
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
