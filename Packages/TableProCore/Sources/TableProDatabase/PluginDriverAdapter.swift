import Foundation
import TableProModels
import TableProPluginKit

public final class PluginDriverAdapter: DatabaseDriver, @unchecked Sendable {
    private let pluginDriver: any PluginDatabaseDriver

    public init(pluginDriver: any PluginDatabaseDriver) {
        self.pluginDriver = pluginDriver
    }

    public func connect() async throws {
        try await pluginDriver.connect()
    }

    // PluginDatabaseDriver.disconnect() is sync and non-throwing, while
    // DatabaseDriver.disconnect() is async throws. A non-throwing call
    // satisfies the throwing requirement, so no try is needed here.
    public func disconnect() async throws {
        pluginDriver.disconnect()
    }

    public func ping() async throws -> Bool {
        do {
            try await pluginDriver.ping()
            return true
        } catch {
            return false
        }
    }

    public func execute(query: String) async throws -> QueryResult {
        let pluginResult = try await pluginDriver.execute(query: query)
        return QueryResult(from: pluginResult)
    }

    public func cancelCurrentQuery() async throws {
        try pluginDriver.cancelQuery()
    }

    public func fetchTables(schema: String?) async throws -> [TableInfo] {
        let pluginTables = try await pluginDriver.fetchTables(schema: schema)
        return pluginTables.map { TableInfo(from: $0) }
    }

    public func fetchColumns(table: String, schema: String?) async throws -> [ColumnInfo] {
        let pluginColumns = try await pluginDriver.fetchColumns(table: table, schema: schema)
        return pluginColumns.enumerated().map { index, col in
            ColumnInfo(from: col, ordinalPosition: index)
        }
    }

    public func fetchIndexes(table: String, schema: String?) async throws -> [IndexInfo] {
        let pluginIndexes = try await pluginDriver.fetchIndexes(table: table, schema: schema)
        return pluginIndexes.map { IndexInfo(from: $0) }
    }

    public func fetchForeignKeys(table: String, schema: String?) async throws -> [ForeignKeyInfo] {
        let pluginFKs = try await pluginDriver.fetchForeignKeys(table: table, schema: schema)
        return pluginFKs.map { ForeignKeyInfo(from: $0) }
    }

    public func fetchDatabases() async throws -> [String] {
        try await pluginDriver.fetchDatabases()
    }

    public func switchDatabase(to name: String) async throws {
        try await pluginDriver.switchDatabase(to: name)
    }

    public var supportsSchemas: Bool {
        pluginDriver.supportsSchemas
    }

    public func switchSchema(to name: String) async throws {
        try await pluginDriver.switchSchema(to: name)
    }

    public var currentSchema: String? {
        pluginDriver.currentSchema
    }

    public var supportsTransactions: Bool {
        pluginDriver.supportsTransactions
    }

    public func beginTransaction() async throws {
        try await pluginDriver.beginTransaction()
    }

    public func commitTransaction() async throws {
        try await pluginDriver.commitTransaction()
    }

    public func rollbackTransaction() async throws {
        try await pluginDriver.rollbackTransaction()
    }

    public var serverVersion: String? {
        pluginDriver.serverVersion
    }
}
