//
//  ContentView.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var dbManager = DatabaseManager.shared
    @State private var connections: [DatabaseConnection] = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var showNewConnectionSheet = false
    @State private var showEditConnectionSheet = false
    @State private var connectionToEdit: DatabaseConnection?
    @State private var connectionToDelete: DatabaseConnection?
    @State private var showDeleteConfirmation = false
    @State private var showUnsavedChangesAlert = false
    @State private var pendingCloseSessionId: UUID?
    @State private var hasLoaded = false

    private let storage = ConnectionStorage.shared
    
    // Get current session from database manager
    private var currentSession: ConnectionSession? {
        dbManager.currentSession
    }
    
    // Get all sessions as array
    private var sessions: [ConnectionSession] {
        Array(dbManager.activeSessions.values)
    }

    var body: some View {
        mainContent
            .frame(minWidth: 900, minHeight: 600)
            .sheet(isPresented: $showNewConnectionSheet) {
                newConnectionSheet
            }
            .sheet(isPresented: $showEditConnectionSheet) {
                editConnectionSheet
            }
            .confirmationDialog(
                "Delete Connection",
                isPresented: $showDeleteConfirmation,
                presenting: connectionToDelete
            ) { connection in
                Button("Delete", role: .destructive) {
                    deleteConnection(connection)
                }
                Button("Cancel", role: .cancel) {}
            } message: { connection in
                Text("Are you sure you want to delete \"\(connection.name)\"?")
            }
            .alert(
                "Unsaved Changes",
                isPresented: $showUnsavedChangesAlert
            ) {
                Button("Cancel", role: .cancel) {
                    pendingCloseSessionId = nil
                }
                Button("Close Without Saving", role: .destructive) {
                    if let sessionId = pendingCloseSessionId {
                        Task {
                            await dbManager.disconnectSession(sessionId)
                        }
                    }
                    pendingCloseSessionId = nil
                }
            } message: {
                Text("This connection has unsaved changes. Are you sure you want to close it?")
            }
            .onAppear {
                loadConnections()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newConnection)) { _ in
                Task { @MainActor in
                    showNewConnectionSheet = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .deselectConnection)) { _ in
                if let sessionId = dbManager.currentSessionId {
                    Task {
                        await dbManager.disconnectSession(sessionId)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleTableBrowser)) { _ in
                guard currentSession != nil else { return }
                Task { @MainActor in
                    withAnimation {
                        columnVisibility = columnVisibility == .all ? .detailOnly : .all
                    }
                }
            }
            .onChange(of: dbManager.currentSessionId) { _, newSessionId in
                Task { @MainActor in
                    withAnimation {
                        columnVisibility = newSessionId == nil ? .detailOnly : .all
                    }
                    AppState.shared.isConnected = newSessionId != nil
                }
            }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var mainContent: some View {
        if currentSession != nil {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                VStack(spacing: 0) {
                    if !sessions.isEmpty {
                        ConnectionSidebarHeader(
                            sessions: sessions,
                            currentSessionId: dbManager.currentSessionId,
                            savedConnections: connections,
                            onSelectSession: { sessionId in
                                Task { @MainActor in
                                    saveCurrentSessionState()
                                    dbManager.switchToSession(sessionId)
                                }
                            },
                            onOpenConnection: { connection in
                                Task { @MainActor in
                                    connectToDatabase(connection)
                                }
                            },
                            onNewConnection: {
                                Task { @MainActor in
                                    showNewConnectionSheet = true
                                }
                            }
                        )
                    }
                    
                    SidebarView(
                        tables: sessionTablesBinding,
                        selectedTable: sessionSelectedTableBinding,
                        activeTableName: currentSession?.selectedTable?.name,
                        onOpenTable: { _ in },
                        pendingTruncates: sessionPendingTruncatesBinding,
                        pendingDeletes: sessionPendingDeletesBinding
                    )
                }
            } detail: {
                MainContentView(
                    connection: currentSession!.connection,
                    tables: sessionTablesBinding,
                    selectedTable: sessionSelectedTableBinding,
                    pendingTruncates: sessionPendingTruncatesBinding,
                    pendingDeletes: sessionPendingDeletesBinding
                )
                .id(currentSession!.id)
            }
        } else {
            WelcomeView(
                connections: connections,
                onSelectConnection: { connection in
                    connectToDatabase(connection)
                },
                onEditConnection: { connection in
                    connectionToEdit = connection
                    showEditConnectionSheet = true
                },
                onDeleteConnection: { connection in
                    connectionToDelete = connection
                    showDeleteConfirmation = true
                },
                onAddConnection: {
                    showNewConnectionSheet = true
                }
            )
            .toolbar(.hidden)
        }
    }
    
    @ViewBuilder
    private var newConnectionSheet: some View {
        ConnectionFormView(
            connection: .constant(DatabaseConnection(name: "")),
            isNew: true,
            onSave: { connection in
                connections.append(connection)
                storage.saveConnections(connections)
                connectToDatabase(connection)
            }
        )
    }
    
    @ViewBuilder
    private var editConnectionSheet: some View {
        if let connection = connectionToEdit {
            ConnectionFormView(
                connection: .constant(connection),
                isNew: false,
                onSave: { updated in
                    if let index = connections.firstIndex(where: { $0.id == connection.id }) {
                        connections[index] = updated
                        storage.saveConnections(connections)
                    }
                },
                onDelete: {
                    connectionToDelete = connection
                    showDeleteConfirmation = true
                    showEditConnectionSheet = false
                }
            )
        }
    }

    // MARK: - Session State Bindings
    
    /// Generic helper to create bindings that update session state
    private func createSessionBinding<T>(
        get: @escaping (ConnectionSession) -> T,
        set: @escaping (inout ConnectionSession, T) -> Void,
        defaultValue: T
    ) -> Binding<T> {
        Binding(
            get: {
                guard let session = currentSession else {
                    return defaultValue
                }
                return get(session)
            },
            set: { newValue in
                guard let sessionId = dbManager.currentSessionId else { return }
                Task { @MainActor in
                    dbManager.updateSession(sessionId) { session in
                        set(&session, newValue)
                    }
                }
            }
        )
    }
    
    private var sessionTablesBinding: Binding<[TableInfo]> {
        createSessionBinding(
            get: { $0.tables },
            set: { $0.tables = $1 },
            defaultValue: []
        )
    }
    
    private var sessionSelectedTableBinding: Binding<TableInfo?> {
        createSessionBinding(
            get: { $0.selectedTable },
            set: { $0.selectedTable = $1 },
            defaultValue: nil
        )
    }
    
    private var sessionPendingTruncatesBinding: Binding<Set<String>> {
        createSessionBinding(
            get: { $0.pendingTruncates },
            set: { $0.pendingTruncates = $1 },
            defaultValue: []
        )
    }
    
    private var sessionPendingDeletesBinding: Binding<Set<String>> {
        createSessionBinding(
            get: { $0.pendingDeletes },
            set: { $0.pendingDeletes = $1 },
            defaultValue: []
        )
    }

    // MARK: - Actions

    private func connectToDatabase(_ connection: DatabaseConnection) {
        Task {
            do {
                try await dbManager.connectToSession(connection)
            } catch {
                print("Failed to connect: \(error)")
            }
        }
    }
    
    private func handleCloseSession(_ sessionId: UUID) {
        Task {
            await dbManager.disconnectSession(sessionId)
        }
    }
    
    private func saveCurrentSessionState() {
        // State is automatically saved through bindings
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

    private func deleteConnection(_ connection: DatabaseConnection) {
        if dbManager.activeSessions[connection.id] != nil {
            Task {
                await dbManager.disconnectSession(connection.id)
            }
        }

        connections.removeAll { $0.id == connection.id }
        storage.deleteConnection(connection)
        storage.saveConnections(connections)
    }
}

#Preview {
    ContentView()
}
