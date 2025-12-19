//
//  SidebarView.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import SwiftUI

// MARK: - SidebarView

/// Sidebar view displaying list of database tables
struct SidebarView: View {
    @Binding var tables: [TableInfo]
    @Binding var selectedTable: TableInfo?
    var activeTableName: String?
    var onOpenTable: ((String) -> Void)?

    // Pending table operations
    @Binding var pendingTruncates: Set<String>
    @Binding var pendingDeletes: Set<String>

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    /// Prevents selection callback during programmatic updates (e.g., refresh)
    @State private var isRestoringSelection = false

    /// Filtered tables based on search text
    private var filteredTables: [TableInfo] {
        guard !searchText.isEmpty else { return tables }
        return tables.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
            content
        }
        .frame(minWidth: 280)
        .onChange(of: selectedTable) { _, newTable in
            guard !isRestoringSelection, let table = newTable else { return }
            // Defer callback to avoid publishing during view update
            Task { @MainActor in
                onOpenTable?(table.name)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .databaseDidConnect)) { _ in
            Task { @MainActor in
                loadTables()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshAll)) { _ in
            Task { @MainActor in
                loadTables()
            }
        }
        .onChange(of: tables) { _, newTables in
            // When tables become empty (disconnected), reset to loading state
            if newTables.isEmpty {
                // Defer state change to avoid publishing during view update
                Task { @MainActor in
                    isLoading = true
                }
            }
        }
        .onAppear {
            guard tables.isEmpty else { return }
            // Defer state changes to avoid publishing during view update
            Task { @MainActor in
                isLoading = true
                if DatabaseManager.shared.activeDriver != nil {
                    loadTables()
                }
            }
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

            TextField("Filter", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Content States

    @ViewBuilder
    private var content: some View {
        if let error = errorMessage {
            errorState(message: error)
        } else if tables.isEmpty && isLoading {
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
        VStack(spacing: 8) {
            Image(systemName: "tablecells")
                .font(.title)
                .foregroundStyle(.tertiary)

            Text("No Tables")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Refresh") {
                loadTables()
            }
            .buttonStyle(.link)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
    }

    private var noMatchState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("No matching tables")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Table List

    private var tableList: some View {
        List(selection: $selectedTable) {
            Section("Tables") {
                ForEach(filteredTables) { table in
                    TableRow(
                        table: table,
                        isActive: activeTableName == table.name,
                        isPendingTruncate: pendingTruncates.contains(table.name),
                        isPendingDelete: pendingDeletes.contains(table.name)
                    )
                    .tag(table)
                    .contextMenu {
                        tableContextMenu(for: table)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            // Delete key - mark selected table for deletion
            if let table = selectedTable {
                toggleDelete(table.name)
            }
        }
    }

    @ViewBuilder
    private func tableContextMenu(for table: TableInfo) -> some View {
        Button("Copy Table Name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(table.name, forType: .string)
        }
        .keyboardShortcut("c", modifiers: .command)

        Divider()

        Button("Truncate Table") {
            toggleTruncate(table.name)
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])

        Button("Delete Table", role: .destructive) {
            toggleDelete(table.name)
        }
        .keyboardShortcut(.delete, modifiers: [])
    }

    // MARK: - Actions

    private func loadTables() {
        isLoading = true
        errorMessage = nil
        Task {
            await loadTablesAsync()
        }
    }

    private func loadTablesAsync() async {
        let previousSelectedName = selectedTable?.name

        guard let driver = DatabaseManager.shared.activeDriver else {
            await MainActor.run { isLoading = false }
            return
        }

        do {
            let fetchedTables = try await driver.fetchTables()
            await MainActor.run {
                tables = fetchedTables
                // Only restore selection if it was cleared (prevent reopening tabs)
                // If selectedTable still exists with same name, don't reassign
                if let name = previousSelectedName {
                    let currentName = selectedTable?.name
                    if currentName != name {
                        // Selection was cleared, restore it without triggering callback
                        isRestoringSelection = true
                        selectedTable = fetchedTables.first { $0.name == name }
                        isRestoringSelection = false
                    }
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func toggleTruncate(_ tableName: String) {
        pendingDeletes.remove(tableName)
        if pendingTruncates.contains(tableName) {
            pendingTruncates.remove(tableName)
        } else {
            pendingTruncates.insert(tableName)
        }
    }

    private func toggleDelete(_ tableName: String) {
        pendingTruncates.remove(tableName)
        if pendingDeletes.contains(tableName) {
            pendingDeletes.remove(tableName)
        } else {
            pendingDeletes.insert(tableName)
        }
    }
}

// MARK: - TableRow

/// Row view for a single table
struct TableRow: View {
    let table: TableInfo
    let isActive: Bool
    let isPendingTruncate: Bool
    let isPendingDelete: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Icon with status indicator
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: table.type == .view ? "eye" : "tablecells")
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                // Pending operation indicator
                if isPendingDelete {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .offset(x: 4, y: 4)
                } else if isPendingTruncate {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .offset(x: 4, y: 4)
                }
            }

            Text(table.name)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(textColor)
        }
        .padding(.vertical, 2)
    }

    private var iconColor: Color {
        if isPendingDelete { return .red }
        if isPendingTruncate { return .orange }
        return table.type == .view ? .purple : .blue
    }

    private var textColor: Color {
        if isPendingDelete { return .red }
        if isPendingTruncate { return .orange }
        return .primary
    }
}

// MARK: - Preview

#Preview {
    SidebarView(
        tables: .constant([]),
        selectedTable: .constant(nil),
        pendingTruncates: .constant([]),
        pendingDeletes: .constant([])
    )
    .frame(width: 250, height: 400)
}
