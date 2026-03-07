//
//  SidebarView.swift
//  TablePro
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import SwiftUI

// MARK: - SidebarView

/// Sidebar view displaying list of database tables
struct SidebarView: View {
    @State private var viewModel: SidebarViewModel
    /// Local search text for responsive typing; synced to/from shared state
    @State private var localSearchText: String = ""
    /// Debounce task for writing local search text to the shared state
    @State private var searchSyncTask: Task<Void, Never>?

    // Keep @Binding on the view for SwiftUI change tracking.
    // The ViewModel stores the same bindings for write access.
    @Binding var tables: [TableInfo]
    var sidebarState: SharedSidebarState
    @Binding var pendingTruncates: Set<String>
    @Binding var pendingDeletes: Set<String>

    var activeTableName: String?
    var onShowAllTables: (() -> Void)?
    var connectionId: UUID

    /// Computed on the view (not ViewModel) so SwiftUI tracks both
    /// `@Binding var tables` and `@Published var searchText` as dependencies.
    private var filteredTables: [TableInfo] {
        guard !viewModel.debouncedSearchText.isEmpty else { return tables }
        return tables.filter { $0.name.localizedCaseInsensitiveContains(viewModel.debouncedSearchText) }
    }

    private var selectedTablesBinding: Binding<Set<TableInfo>> {
        Binding(
            get: { sidebarState.selectedTables },
            set: { sidebarState.selectedTables = $0 }
        )
    }

    init(
        tables: Binding<[TableInfo]>,
        sidebarState: SharedSidebarState,
        activeTableName: String? = nil,
        onShowAllTables: (() -> Void)? = nil,
        pendingTruncates: Binding<Set<String>>,
        pendingDeletes: Binding<Set<String>>,
        tableOperationOptions: Binding<[String: TableOperationOptions]>,
        databaseType: DatabaseType,
        connectionId: UUID,
        schemaProvider: SQLSchemaProvider? = nil
    ) {
        _tables = tables
        self.sidebarState = sidebarState
        _localSearchText = State(initialValue: sidebarState.searchText)
        _pendingTruncates = pendingTruncates
        _pendingDeletes = pendingDeletes
        let selectedBinding = Binding(
            get: { sidebarState.selectedTables },
            set: { sidebarState.selectedTables = $0 }
        )
        let vm = SidebarViewModel(
            tables: tables,
            selectedTables: selectedBinding,
            pendingTruncates: pendingTruncates,
            pendingDeletes: pendingDeletes,
            tableOperationOptions: tableOperationOptions,
            databaseType: databaseType,
            connectionId: connectionId,
            schemaProvider: schemaProvider
        )
        vm.debouncedSearchText = sidebarState.searchText
        _viewModel = State(wrappedValue: vm)
        self.activeTableName = activeTableName
        self.onShowAllTables = onShowAllTables
        self.connectionId = connectionId
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !tables.isEmpty {
                searchField
            }
            content
        }
        .frame(minWidth: 280)
        .onChange(of: localSearchText) { _, newValue in
            viewModel.debouncedSearchText = newValue
            searchSyncTask?.cancel()
            searchSyncTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                if sidebarState.searchText != newValue {
                    sidebarState.searchText = newValue
                }
            }
        }
        .onChange(of: sidebarState.searchText) { _, newValue in
            if localSearchText != newValue {
                localSearchText = newValue
                viewModel.debouncedSearchText = newValue
            }
        }
        .onChange(of: tables) { _, newTables in
            let hasSession = DatabaseManager.shared.activeSessions[connectionId] != nil
            if newTables.isEmpty && hasSession && !viewModel.isLoading {
                viewModel.loadTables()
            }
        }
        .onAppear {
            viewModel.setupNotifications()
            viewModel.onAppear()
        }
        .sheet(isPresented: $viewModel.showOperationDialog) {
            if let operationType = viewModel.pendingOperationType {
                let dialogTables = viewModel.pendingOperationTables
                if let firstTable = dialogTables.first {
                    TableOperationDialog(
                        isPresented: $viewModel.showOperationDialog,
                        tableName: firstTable,
                        tableCount: dialogTables.count,
                        operationType: operationType,
                        databaseType: viewModel.databaseType
                    ) { options in
                        viewModel.confirmOperation(options: options)
                    }
                }
            }
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: DesignConstants.FontSize.medium))

            TextField("Filter", text: $localSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: DesignConstants.FontSize.body))

            if !localSearchText.isEmpty {
                Button(action: { localSearchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: DesignConstants.FontSize.medium))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear table filter"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, DesignConstants.Spacing.xxs)
        .background(Color(nsColor: .quaternaryLabelColor))
        .cornerRadius(6)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Content States

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.errorMessage {
            errorState(message: error)
        } else if tables.isEmpty && viewModel.isLoading {
            loadingState
        } else if tables.isEmpty {
            emptyState
        } else if filteredTables.isEmpty {
            noMatchState
        } else {
            tableList
        }
    }

    private var loadingState: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tablecells")
                .font(.system(size: 28, weight: .thin))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))

            Text(sidebarLabel(mongodb: "No Collections", redis: "No Databases", default: "No Tables"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            Text(sidebarLabel(
                mongodb: "This database has no collections yet.",
                redis: "All databases are empty.",
                default: "This database has no tables yet."
            ))
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text(sidebarLabel(mongodb: "No matching collections", redis: "No matching databases", default: "No matching tables"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Table List

    private var tableList: some View {
        List(selection: selectedTablesBinding) {
            Section(isExpanded: $viewModel.isTablesExpanded) {
                ForEach(filteredTables) { table in
                    TableRow(
                        table: table,
                        isActive: activeTableName == table.name,
                        isPendingTruncate: pendingTruncates.contains(table.name),
                        isPendingDelete: pendingDeletes.contains(table.name)
                    )
                    .tag(table)
                    .contextMenu {
                        SidebarContextMenu(
                            clickedTable: table,
                            selectedTables: selectedTablesBinding,
                            isReadOnly: AppState.shared.isReadOnly,
                            onBatchToggleTruncate: { viewModel.batchToggleTruncate() },
                            onBatchToggleDelete: { viewModel.batchToggleDelete() }
                        )
                    }
                }
            } header: {
                Text(sidebarLabel(mongodb: "Collections", redis: "Databases", default: "Tables"))
                    .help(sidebarLabel(
                        mongodb: "Right-click to show all collections",
                        redis: "Right-click to show all databases",
                        default: "Right-click to show all tables"
                    ))
                    .contextMenu {
                        Button(sidebarLabel(
                            mongodb: String(localized: "Show All Collections"),
                            redis: String(localized: "Show All Databases"),
                            default: String(localized: "Show All Tables")
                        )) {
                            onShowAllTables?()
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .contextMenu {
            SidebarContextMenu(
                clickedTable: nil,
                selectedTables: selectedTablesBinding,
                isReadOnly: AppState.shared.isReadOnly,
                onBatchToggleTruncate: { viewModel.batchToggleTruncate() },
                onBatchToggleDelete: { viewModel.batchToggleDelete() }
            )
        }
        .onExitCommand {
            sidebarState.selectedTables.removeAll()
        }
    }

    // MARK: - Helpers

    private func sidebarLabel(mongodb: String, redis: String, default defaultLabel: String) -> String {
        switch viewModel.databaseType {
        case .mongodb: return mongodb
        case .redis: return redis
        default: return defaultLabel
        }
    }
}

// MARK: - Preview

#Preview {
    SidebarView(
        tables: .constant([]),
        sidebarState: SharedSidebarState(),
        pendingTruncates: .constant([]),
        pendingDeletes: .constant([]),
        tableOperationOptions: .constant([:]),
        databaseType: .mysql,
        connectionId: UUID()
    )
    .frame(width: 250, height: 400)
}
