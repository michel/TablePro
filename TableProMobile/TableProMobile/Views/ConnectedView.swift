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
    @State private var toastTask: Task<Void, Never>?
    @State private var selectedTab = ConnectedTab.tables
    @State private var queryHistory: [String] = []
    @State private var databases: [String] = []
    @State private var activeDatabase: String = ""
    @State private var schemas: [String] = []
    @State private var activeSchema: String = "public"
    @State private var isSwitching = false

    enum ConnectedTab: String, CaseIterable {
        case tables = "Tables"
        case query = "Query"
    }

    private var displayName: String {
        connection.name.isEmpty ? connection.host : connection.name
    }

    private var supportsDatabaseSwitching: Bool {
        connection.type == .mysql || connection.type == .mariadb ||
        connection.type == .postgresql || connection.type == .redshift
    }

    private var supportsSchemas: Bool {
        connection.type == .postgresql || connection.type == .redshift
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
                    .allowsHitTesting(!isSwitching)
                    .overlay {
                        if isSwitching {
                            ZStack {
                                Rectangle()
                                    .fill(.ultraThinMaterial)
                                    .ignoresSafeArea()
                                ProgressView()
                                    .controlSize(.large)
                            }
                            .transition(.opacity)
                        }
                    }
                    .animation(.default, value: isSwitching)
            }
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                ErrorToast(message: toastMessage)
                    .onAppear {
                        toastTask?.cancel()
                        toastTask = Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            withAnimation { self.toastMessage = nil }
                        }
                    }
                    .onDisappear {
                        toastTask?.cancel()
                        toastTask = nil
                    }
            }
        }
        .animation(.default, value: toastMessage)
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if supportsDatabaseSwitching && databases.count > 1 {
                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(databases, id: \.self) { db in
                            Button {
                                Task { await switchDatabase(to: db) }
                            } label: {
                                if db == activeDatabase {
                                    Label(db, systemImage: "checkmark")
                                } else {
                                    Text(db)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(activeDatabase)
                                .font(.headline)
                            if isSwitching {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isSwitching)
                }
            }
            if supportsSchemas && schemas.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(schemas, id: \.self) { schema in
                            Button {
                                Task { await switchSchema(to: schema) }
                            } label: {
                                if schema == activeSchema {
                                    Label(schema, systemImage: "checkmark")
                                } else {
                                    Text(schema)
                                }
                            }
                        }
                    } label: {
                        Label(activeSchema, systemImage: "square.3.layers.3d")
                            .font(.subheadline)
                    }
                    .disabled(isSwitching)
                }
            }
        }
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
                    tables: tables,
                    queryHistory: $queryHistory
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
                await loadDatabases()
                await loadSchemas()
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
            await loadDatabases()
            await loadSchemas()
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
        guard let session, !isSwitching else { return }
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

    private func loadDatabases() async {
        guard let session, supportsDatabaseSwitching else { return }
        do {
            databases = try await session.driver.fetchDatabases()
            activeDatabase = connection.database
        } catch {
            // Silently fail — just don't show picker
        }
    }

    private func loadSchemas() async {
        guard let session, supportsSchemas else { return }
        do {
            schemas = try await session.driver.fetchSchemas()
            activeSchema = session.driver.currentSchema ?? "public"
        } catch {
            // Silently fail — don't show picker
        }
    }

    private func switchSchema(to name: String) async {
        guard let session, name != activeSchema, !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }

        do {
            try await session.driver.switchSchema(to: name)
            activeSchema = name
            self.tables = try await session.driver.fetchTables(schema: name)
        } catch {
            withAnimation { toastMessage = String(localized: "Failed to switch schema") }
        }
    }

    private func switchDatabase(to name: String) async {
        guard let session, name != activeDatabase, !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }

        if connection.type == .postgresql || connection.type == .redshift {
            await reconnectWithDatabase(name)
        } else {
            do {
                try await session.driver.switchDatabase(to: name)
                activeDatabase = name
                self.tables = try await session.driver.fetchTables(schema: nil)
            } catch {
                withAnimation { toastMessage = String(localized: "Failed to switch database") }
            }
        }
    }

    private func reconnectWithDatabase(_ database: String) async {
        await appState.connectionManager.disconnect(connection.id)
        self.session = nil

        var newConnection = connection
        newConnection.database = database

        await appState.sshProvider.setPendingConnectionId(connection.id)

        do {
            let newSession = try await appState.connectionManager.connect(newConnection)
            self.session = newSession
            self.tables = try await newSession.driver.fetchTables(schema: nil)
            activeDatabase = database
            await loadSchemas()
        } catch {
            // Reconnect to original database as fallback
            Self.logger.error("Failed to switch to database \(database, privacy: .public): \(error.localizedDescription, privacy: .public)")
            await appState.sshProvider.setPendingConnectionId(connection.id)
            do {
                let fallbackSession = try await appState.connectionManager.connect(connection)
                self.session = fallbackSession
                self.tables = try await fallbackSession.driver.fetchTables(schema: nil)
                withAnimation { toastMessage = String(localized: "Failed to switch database") }
            } catch {
                // Both failed — show error view
                let context = ErrorContext(
                    operation: "switchDatabase",
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
            let schema = supportsSchemas ? activeSchema : nil
            self.tables = try await session.driver.fetchTables(schema: schema)
        } catch {
            Self.logger.warning("Failed to refresh tables: \(error.localizedDescription, privacy: .public)")
            withAnimation { toastMessage = String(localized: "Failed to refresh tables") }
        }
    }
}
