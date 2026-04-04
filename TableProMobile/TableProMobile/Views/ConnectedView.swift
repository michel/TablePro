//
//  ConnectedView.swift
//  TableProMobile
//

import os
import SwiftUI
import TableProDatabase
import TableProModels

struct ConnectedView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    let connection: DatabaseConnection

    private static let logger = Logger(subsystem: "com.TablePro", category: "ConnectedView")

    @State private var session: ConnectionSession?
    @State private var tables: [TableInfo] = []
    @State private var isConnecting = true
    @State private var appError: AppError?
    @State private var toastMessage: String?
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
            } else if let appError {
                ErrorView(error: appError) {
                    await connect()
                }
            } else {
                connectedContent
            }
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                ErrorToast(message: toastMessage)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            withAnimation { self.toastMessage = nil }
                        }
                    }
            }
        }
        .animation(.default, value: toastMessage)
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
        appError = nil

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
            let context = ErrorContext(
                operation: "connect",
                databaseType: connection.type,
                host: connection.host,
                sshEnabled: connection.sshEnabled
            )
            appError = ErrorClassifier.classify(error, context: context)
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
                let context = ErrorContext(
                    operation: "reconnect",
                    databaseType: connection.type,
                    host: connection.host,
                    sshEnabled: connection.sshEnabled
                )
                appError = ErrorClassifier.classify(error, context: context)
                self.session = nil
            }
        }
    }

    private func refreshTables() async {
        guard let session else { return }
        do {
            self.tables = try await session.driver.fetchTables(schema: nil)
        } catch {
            Self.logger.warning("Failed to refresh tables: \(error.localizedDescription, privacy: .public)")
            withAnimation { toastMessage = "Failed to refresh tables" }
        }
    }
}
