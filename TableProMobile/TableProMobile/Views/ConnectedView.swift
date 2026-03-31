//
//  ConnectedView.swift
//  TableProMobile
//
//  Wrapper that connects to the database, then shows TableListView.
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

    var body: some View {
        Group {
            if isConnecting {
                ProgressView("Connecting to \(connection.name)...")
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
                TableListView(
                    connection: connection,
                    tables: tables,
                    session: session
                )
            }
        }
        .navigationTitle(connection.name.isEmpty ? connection.host : connection.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await connect() }
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
}
