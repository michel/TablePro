//
//  ConnectedView.swift
//  TableProMobile
//

import SwiftUI
import TableProDatabase
import TableProModels

struct ConnectedView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    let connection: DatabaseConnection

    @State private var session: ConnectionSession?
    @State private var tables: [TableInfo] = []
    @State private var isConnecting = true
    @State private var errorMessage: String?
    @State private var selectedTab = ConnectedTab.tables

    enum ConnectedTab: String, CaseIterable {
        case tables = "Tables"
        case query = "Query"
    }

    private var displayName: String {
        connection.name.isEmpty ? connection.host : connection.name
    }

    var body: some View {
        Group {
            if isConnecting {
                ProgressView {
                    Text(verbatim: "Connecting to \(displayName)...")
                }
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
                connectedContent
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await connect() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, session != nil {
                Task { await reconnectIfNeeded() }
            }
        }
    }

    private var connectedContent: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                ForEach(ConnectedTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch selectedTab {
            case .tables:
                TableListView(
                    connection: connection,
                    tables: tables,
                    session: session,
                    onRefresh: { await refreshTables() }
                )
            case .query:
                QueryEditorView(
                    session: session,
                    tables: tables
                )
            }
        }
    }

    private func connect() async {
        guard session == nil else {
            isConnecting = false
            return
        }

        isConnecting = true
        errorMessage = nil

        // Reuse existing session if still alive in ConnectionManager
        if let existing = appState.connectionManager.session(for: connection.id) {
            self.session = existing
            do {
                self.tables = try await existing.driver.fetchTables(schema: nil)
            } catch {
                // Session stale — disconnect and reconnect
                await appState.connectionManager.disconnect(connection.id)
                await connectFresh()
                return
            }
            isConnecting = false
            return
        }

        await connectFresh()
    }

    private func connectFresh() async {
        await appState.sshProvider.setPendingConnectionId(connection.id)

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

    private func reconnectIfNeeded() async {
        guard let session else { return }
        do {
            _ = try await session.driver.ping()
        } catch {
            // Connection lost — reconnect
            do {
                await appState.sshProvider.setPendingConnectionId(connection.id)
                let newSession = try await appState.connectionManager.connect(connection)
                self.session = newSession
            } catch {
                errorMessage = error.localizedDescription
                self.session = nil
            }
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
