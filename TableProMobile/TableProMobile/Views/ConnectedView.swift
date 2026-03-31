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
                connectedContent
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await connect()
        }
        .task(id: "lifecycle") {
            // Wait for task cancellation (view removed from navigation stack)
            // then disconnect. This avoids false onDisappear during push navigation.
            do { try await Task.sleep(for: .seconds(Double.greatestFiniteMagnitude)) } catch {}
            if let session {
                try? await session.driver.disconnect()
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
