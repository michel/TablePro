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
    @State private var expandedTables: Set<String> = []
    @State private var tableColumns: [String: [ColumnInfo]] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    
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
            } else {
                tableList
            }
        }
        .task {
            await loadTablesAsync()
        }
    }
    
    private var tableList: some View {
        List {
            ForEach(tables) { table in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedTables.contains(table.name) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedTables.insert(table.name)
                                loadColumns(for: table.name)
                            } else {
                                expandedTables.remove(table.name)
                            }
                        }
                    )
                ) {
                    // Columns
                    if let columns = tableColumns[table.name] {
                        ForEach(columns) { column in
                            HStack(spacing: 6) {
                                Image(systemName: column.isPrimaryKey ? "key.fill" : "minus")
                                    .font(.caption2)
                                    .foregroundColor(column.isPrimaryKey ? .yellow : .gray)
                                    .frame(width: 12)
                                
                                Text(column.name)
                                    .font(.system(.caption, design: .monospaced))
                                
                                Spacer()
                                
                                Text(column.dataType)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 8)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: table.type == .view ? "eye" : "tablecells")
                            .font(.caption)
                            .foregroundStyle(table.type == .view ? .purple : .blue)
                        
                        Text(table.name)
                            .font(.system(.body, design: .monospaced))
                        
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .background(
                        activeTableName == table.name ?
                            Color.accentColor.opacity(0.2) :
                            Color.clear
                    )
                    .cornerRadius(4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Single-click to open table data
                        onOpenTable?(table.name)
                    }
                    .contextMenu {
                        Button("SELECT * FROM \(table.name)") {
                            onSelectQuery("SELECT * FROM \(table.name);")
                        }
                        Button("SELECT COUNT(*) FROM \(table.name)") {
                            onSelectQuery("SELECT COUNT(*) FROM \(table.name);")
                        }
                        Divider()
                        Button("Copy Table Name") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(table.name, forType: .string)
                        }
                    }
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
    
    private func loadColumns(for tableName: String) {
        guard tableColumns[tableName] == nil else { return }
        
        Task {
            let driver = DatabaseDriverFactory.createDriver(for: connection)
            
            do {
                try await driver.connect()
                let columns = try await driver.fetchColumns(table: tableName)
                driver.disconnect()
                
                await MainActor.run {
                    tableColumns[tableName] = columns
                }
            } catch {
                print("Failed to load columns for \(tableName): \(error)")
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
