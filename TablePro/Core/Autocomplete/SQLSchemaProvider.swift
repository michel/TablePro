//
//  SQLSchemaProvider.swift
//  TablePro
//
//  Cached database schema provider for autocomplete
//

import Foundation

/// Provides cached database schema information for autocomplete
actor SQLSchemaProvider {
    // MARK: - Properties

    private var tables: [TableInfo] = []
    private var columnCache: [String: [ColumnInfo]] = [:]
    private var isLoading = false
    private var lastLoadError: Error?

    // Store a weak driver reference to avoid retaining it after disconnect (MEM-9)
    private weak var cachedDriver: (any DatabaseDriver)?

    // Store connection info for reference
    private var connectionInfo: DatabaseConnection?

    // MARK: - Public API

    /// Load schema from the database (driver should already be connected)
    func loadSchema(using driver: DatabaseDriver, connection: DatabaseConnection? = nil) async {
        guard !isLoading else { return }

        // Store driver reference for later column fetching
        self.cachedDriver = driver
        self.connectionInfo = connection
        isLoading = true
        lastLoadError = nil

        do {
            // Fetch all tables
            tables = try await driver.fetchTables()

            // Bulk-fetch columns for all tables in a single query when supported
            // (DAT-4: avoids N+1 queries — 1 query for tables + 1 for all columns
            //  instead of 1 + N where N = table count).
            let allColumns = try await driver.fetchAllColumns()
            for (tableName, columns) in allColumns {
                columnCache[tableName.lowercased()] = columns
            }

            isLoading = false
        } catch {
            lastLoadError = error
            isLoading = false
        }
    }

    /// Get all tables
    func getTables() -> [TableInfo] {
        tables
    }

    /// Get columns for a specific table (with caching)
    func getColumns(for tableName: String) async -> [ColumnInfo] {
        // Check cache first
        if let cached = columnCache[tableName.lowercased()] {
            return cached
        }

        // Use the cached driver from loadSchema() to ensure we're querying the correct connection
        guard let driver = cachedDriver else {
            return []
        }

        do {
            let columns = try await driver.fetchColumns(table: tableName)
            columnCache[tableName.lowercased()] = columns
            return columns
        } catch {
            return []
        }
    }

    /// Check if schema is loaded
    func isSchemaLoaded() -> Bool {
        !tables.isEmpty
    }

    /// Check if currently loading
    func isCurrentlyLoading() -> Bool {
        isLoading
    }

    /// Invalidate cache and reload
    func invalidateCache() {
        tables.removeAll()
        columnCache.removeAll()
        cachedDriver = nil
    }

    /// Find table name from alias
    func resolveAlias(_ aliasOrName: String, in references: [TableReference]) -> String? {
        // First check if it's an alias
        for ref in references {
            if ref.alias?.lowercased() == aliasOrName.lowercased() {
                return ref.tableName
            }
        }

        // Then check if it's a table name directly
        for ref in references {
            if ref.tableName.lowercased() == aliasOrName.lowercased() {
                return ref.tableName
            }
        }

        // Finally check against known tables
        for table in tables {
            if table.name.lowercased() == aliasOrName.lowercased() {
                return table.name
            }
        }

        return nil
    }

    // MARK: - AI Schema Context

    /// Build schema context string for AI prompts using cached data.
    /// Returns nil if no schema is loaded or settings disable schema inclusion.
    func buildSchemaContextForAI(settings: AISettings) -> String? {
        guard !tables.isEmpty, let connection = connectionInfo else { return nil }

        return AISchemaContext.buildSystemPrompt(
            databaseType: connection.type,
            databaseName: connection.database,
            tables: tables,
            columnsByTable: columnCache,
            foreignKeys: [:],
            currentQuery: nil,
            queryResults: nil,
            settings: settings
        )
    }

    // MARK: - Completion Items

    /// Get completion items for tables
    func tableCompletionItems() async -> [SQLCompletionItem] {
        let tableData = tables.map { (name: $0.name, isView: $0.type == .view) }
        return await MainActor.run {
            tableData.map { SQLCompletionItem.table($0.name, isView: $0.isView) }
        }
    }

    /// Get completion items for columns of a specific table
    func columnCompletionItems(for tableName: String) async -> [SQLCompletionItem] {
        let columns = await getColumns(for: tableName)
        let columnData = columns.map { col in
            (name: col.name, type: col.dataType, isPK: col.isPrimaryKey,
             isNullable: col.isNullable, defaultValue: col.defaultValue, comment: col.comment)
        }
        return await MainActor.run {
            columnData.map {
                SQLCompletionItem.column(
                    $0.name, dataType: $0.type, tableName: tableName,
                    isPrimaryKey: $0.isPK, isNullable: $0.isNullable,
                    defaultValue: $0.defaultValue, comment: $0.comment
                )
            }
        }
    }

    /// Get completion items for all columns of tables in scope
    func allColumnsInScope(for references: [TableReference]) async -> [SQLCompletionItem] {
        // swiftlint:disable:next large_tuple
        var itemDataBuilder: [(
            label: String, insertText: String, type: String, table: String,
            isPK: Bool, isNullable: Bool, defaultValue: String?, comment: String?
        )] = []

        for ref in references {
            let columns = await getColumns(for: ref.tableName)
            let refId = ref.identifier
            for column in columns {
                // Include table/alias prefix for clarity when multiple tables
                let label = references.count > 1 ? "\(refId).\(column.name)" : column.name
                let insertText = references.count > 1 ? "\(refId).\(column.name)" : column.name

                itemDataBuilder.append(
                    (
                        label: label, insertText: insertText, type: column.dataType,
                        table: ref.tableName, isPK: column.isPrimaryKey,
                        isNullable: column.isNullable, defaultValue: column.defaultValue,
                        comment: column.comment
                    ))
            }
        }

        // Capture as immutable for Sendable compliance
        let itemData = itemDataBuilder

        return await MainActor.run {
            itemData.map {
                SQLCompletionItem.column(
                    $0.label, dataType: $0.type, tableName: $0.table,
                    isPrimaryKey: $0.isPK, isNullable: $0.isNullable,
                    defaultValue: $0.defaultValue, comment: $0.comment
                )
            }
        }
    }
}
