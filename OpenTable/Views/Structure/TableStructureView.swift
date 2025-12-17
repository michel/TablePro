//
//  TableStructureView.swift
//  OpenTable
//
//  View for displaying table structure: columns, indexes, foreign keys
//

import SwiftUI

/// Tab selection for structure view
enum StructureTab: String, CaseIterable {
    case columns = "Columns"
    case indexes = "Indexes"
    case foreignKeys = "Foreign Keys"
}

/// View displaying table structure like TablePlus
struct TableStructureView: View {
    let tableName: String
    let connection: DatabaseConnection
    
    @State private var selectedTab: StructureTab = .columns
    @State private var columns: [ColumnInfo] = []
    @State private var indexes: [IndexInfo] = []
    @State private var foreignKeys: [ForeignKeyInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(StructureTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            // Content
            if isLoading {
                ProgressView("Loading structure...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch selectedTab {
                case .columns:
                    columnsTable
                case .indexes:
                    indexesTable
                case .foreignKeys:
                    foreignKeysTable
                }
            }
        }
        .task {
            await loadStructure()
        }
    }
    
    // MARK: - Columns Tab
    
    private var columnsTable: some View {
        Table(columns) {
            TableColumn("Name") { column in
                HStack(spacing: 4) {
                    if column.isPrimaryKey {
                        Image(systemName: "key.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                    Text(column.name)
                        .fontWeight(column.isPrimaryKey ? .semibold : .regular)
                }
            }
            .width(min: 120, ideal: 150)
            
            TableColumn("Type") { column in
                Text(column.dataType)
                    .foregroundColor(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 100, ideal: 120)
            
            TableColumn("Nullable") { column in
                Image(systemName: column.isNullable ? "checkmark.circle" : "xmark.circle")
                    .foregroundColor(column.isNullable ? .green : .red)
            }
            .width(70)
            
            TableColumn("Default") { column in
                Text(column.defaultValue ?? "-")
                    .foregroundColor(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 80, ideal: 120)
            
            TableColumn("Extra") { column in
                Text(column.extra ?? "-")
                    .foregroundColor(.secondary)
            }
            .width(min: 80, ideal: 100)
        }
    }
    
    // MARK: - Indexes Tab
    
    private var indexesTable: some View {
        Group {
            if indexes.isEmpty {
                emptyState("No indexes found")
            } else {
                Table(indexes) {
                    TableColumn("Name") { index in
                        HStack(spacing: 4) {
                            if index.isPrimary {
                                Image(systemName: "key.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                            } else if index.isUnique {
                                Image(systemName: "seal.fill")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                            }
                            Text(index.name)
                                .fontWeight(index.isPrimary ? .semibold : .regular)
                        }
                    }
                    .width(min: 150, ideal: 200)
                    
                    TableColumn("Columns") { index in
                        Text(index.columns.joined(separator: ", "))
                            .font(.system(.body, design: .monospaced))
                    }
                    .width(min: 150, ideal: 250)
                    
                    TableColumn("Type") { index in
                        Text(index.type)
                            .foregroundColor(.secondary)
                    }
                    .width(80)
                    
                    TableColumn("Unique") { index in
                        Image(systemName: index.isUnique ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(index.isUnique ? .green : .secondary)
                    }
                    .width(60)
                }
            }
        }
    }
    
    // MARK: - Foreign Keys Tab
    
    private var foreignKeysTable: some View {
        Group {
            if foreignKeys.isEmpty {
                emptyState("No foreign keys found")
            } else {
                Table(foreignKeys) {
                    TableColumn("Name") { fk in
                        Text(fk.name)
                            .fontWeight(.medium)
                    }
                    .width(min: 150, ideal: 200)
                    
                    TableColumn("Column") { fk in
                        Text(fk.column)
                            .font(.system(.body, design: .monospaced))
                    }
                    .width(min: 100, ideal: 150)
                    
                    TableColumn("References") { fk in
                        HStack(spacing: 2) {
                            Text(fk.referencedTable)
                                .foregroundColor(.blue)
                            Text(".")
                                .foregroundColor(.secondary)
                            Text(fk.referencedColumn)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .width(min: 150, ideal: 200)
                    
                    TableColumn("On Delete") { fk in
                        Text(fk.onDelete)
                            .foregroundColor(fk.onDelete == "CASCADE" ? .orange : .secondary)
                    }
                    .width(90)
                    
                    TableColumn("On Update") { fk in
                        Text(fk.onUpdate)
                            .foregroundColor(fk.onUpdate == "CASCADE" ? .orange : .secondary)
                    }
                    .width(90)
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(message)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Load Data
    
    private func loadStructure() async {
        isLoading = true
        errorMessage = nil
        
        let driver = DatabaseDriverFactory.createDriver(for: connection)
        
        do {
            try await driver.connect()
            
            // Load all in parallel
            async let columnsTask = driver.fetchColumns(table: tableName)
            async let indexesTask = driver.fetchIndexes(table: tableName)
            async let fkTask = driver.fetchForeignKeys(table: tableName)
            
            columns = try await columnsTask
            indexes = try await indexesTask
            foreignKeys = try await fkTask
            
            driver.disconnect()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

#Preview {
    TableStructureView(
        tableName: "users",
        connection: DatabaseConnection(
            name: "Test",
            host: "localhost",
            port: 3306,
            database: "test",
            username: "root",
            type: .mysql
        )
    )
    .frame(width: 800, height: 400)
}
