//
//  TableBrowserView.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import SwiftUI

/// View for browsing database tables and their structure
struct TableBrowserView: View {
    let connection: DatabaseConnection
    let onSelectQuery: (String) -> Void
    var onOpenTable: ((String) -> Void)?  // Click to open table
    var activeTableName: String?  // Currently active table (synced with tab)

    @State private var tables: [TableInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText: String = ""
    @State private var selectedIndex: Int? = nil  // Keyboard navigation index
    @FocusState private var isFocused: Bool  // Focus state for keyboard navigation

    /// Filtered tables based on search text
    private var filteredTables: [TableInfo] {
        if searchText.isEmpty {
            return tables
        }
        return tables.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Tables")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: loadTables) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.caption)

                TextField("Filter tables...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .default))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tables.isEmpty {
                VStack {
                    Image(systemName: "tray")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("No tables")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredTables.isEmpty {
                VStack {
                    Image(systemName: "magnifyingglass")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("No matching tables")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                tableList
            }
        }
        .task {
            await loadTablesAsync()
        }
        .onKeyPress(.downArrow) {
            navigateDown()
            return .handled
        }
        .onKeyPress(.upArrow) {
            navigateUp()
            return .handled
        }
        .onKeyPress(.return) {
            openSelectedTable()
            return .handled
        }
        .onChange(of: searchText) { _, _ in
            // Reset selection when search changes
            selectedIndex = filteredTables.isEmpty ? nil : 0
        }
    }

    private var tableList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredTables.enumerated()), id: \.element.id) { index, table in
                        HStack(spacing: 6) {
                            Image(systemName: table.type == .view ? "eye" : "tablecells")
                                .font(.caption)
                                .foregroundStyle(table.type == .view ? .purple : .blue)

                            Text(table.name)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            backgroundColorForItem(table: table, index: index)
                        )
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        .id(table.id)
                        .onTapGesture {
                            selectedIndex = index
                            isFocused = true  // Take focus for keyboard navigation
                            onOpenTable?(table.name)
                        }
                        .contextMenu {
                            Button("Copy Table Name") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(table.name, forType: .string)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onChange(of: selectedIndex) { _, newIndex in
                // Scroll to selected item
                if let index = newIndex, index < filteredTables.count {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(filteredTables[index].id, anchor: .center)
                    }
                }
            }
        }
    }

    /// Determine background color for a table item
    private func backgroundColorForItem(table: TableInfo, index: Int) -> Color {
        if activeTableName == table.name {
            return Color.accentColor.opacity(0.2)
        } else if selectedIndex == index {
            return Color.secondary.opacity(0.15)
        }
        return Color.clear
    }

    // MARK: - Keyboard Navigation

    private func navigateDown() {
        guard !filteredTables.isEmpty else { return }

        if let current = selectedIndex {
            selectedIndex = min(current + 1, filteredTables.count - 1)
        } else {
            selectedIndex = 0
        }

        // Auto-open the selected table
        if let index = selectedIndex, index < filteredTables.count {
            onOpenTable?(filteredTables[index].name)
        }
    }

    private func navigateUp() {
        guard !filteredTables.isEmpty else { return }

        if let current = selectedIndex {
            selectedIndex = max(current - 1, 0)
        } else {
            selectedIndex = filteredTables.count - 1
        }

        // Auto-open the selected table
        if let index = selectedIndex, index < filteredTables.count {
            onOpenTable?(filteredTables[index].name)
        }
    }

    private func openSelectedTable() {
        guard let index = selectedIndex, index < filteredTables.count else { return }
        onOpenTable?(filteredTables[index].name)
    }

    private func loadTables() {
        Task {
            await loadTablesAsync()
        }
    }

    private func loadTablesAsync() async {
        isLoading = true
        errorMessage = nil

        let driver = DatabaseDriverFactory.createDriver(for: connection)

        do {
            try await driver.connect()
            let fetchedTables = try await driver.fetchTables()
            driver.disconnect()

            await MainActor.run {
                tables = fetchedTables
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

}

#Preview {
    TableBrowserView(
        connection: DatabaseConnection.sampleConnections[2],
        onSelectQuery: { _ in }
    )
    .frame(width: 250, height: 400)
}
