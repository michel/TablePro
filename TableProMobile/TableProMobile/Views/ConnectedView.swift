//
//  ConnectedView.swift
//  TableProMobile
//

import SwiftUI
import TableProDatabase
import TableProModels

struct ConnectedView: View {
    @Environment(AppState.self) private var appState
    let connection: DatabaseConnection

    @State private var session: ConnectionSession?
    @State private var tables: [TableInfo] = []
    @State private var isConnecting = true
    @State private var errorMessage: String?
    @State private var selectedTab = 0

    private var displayName: String {
        connection.name.isEmpty ? connection.host : connection.name
    }

    var body: some View {
        Group {
            if isConnecting {
                ProgressView("Connecting to \(displayName)...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Connection Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") {
                        Task { await connect() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                connectedTabs
            }
        }
        .toolbar(session != nil && errorMessage == nil ? .hidden : .visible, for: .navigationBar)
        .task { await connect() }
        .onDisappear {
            Task {
                if let session {
                    try? await session.driver.disconnect()
                }
            }
        }
    }

    private var connectedTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Tables", systemImage: "tablecells", value: 0) {
                NavigationStack {
                    TableListView(
                        connection: connection,
                        tables: tables,
                        session: session,
                        onRefresh: { await refreshTables() }
                    )
                    .toolbar {
                        ToolbarItem(placement: .status) {
                            connectionStatusBadge
                        }
                    }
                }
            }

            Tab("Query", systemImage: "terminal", value: 1) {
                NavigationStack {
                    QueryEditorView(
                        session: session,
                        tables: tables
                    )
                    .toolbar {
                        ToolbarItem(placement: .status) {
                            connectionStatusBadge
                        }
                    }
                }
            }
        }
    }

    private var connectionStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
            Text(displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil

        do {
            let session = try await appState.connectionManager.connect(connection)
            self.session = session
            self.tables = try await session.driver.fetchTables(schema: nil)
            isConnecting = false
        } catch {
            errorMessage = error.localizedDescription
            isConnecting = false
        }
    }

    private func refreshTables() async {
        guard let session else { return }
        do {
            self.tables = try await session.driver.fetchTables(schema: nil)
        } catch {
            // Keep existing tables on refresh failure
        }
    }
}
