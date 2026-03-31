import Testing
import Foundation
@testable import TableProDatabase
@testable import TableProModels
@testable import TableProPluginKit

private final class StubPluginDriver: PluginDatabaseDriver, @unchecked Sendable {
    var connectCalled = false
    var disconnectCalled = false

    func connect() async throws {
        connectCalled = true
    }

    func disconnect() {
        disconnectCalled = true
    }

    func execute(query: String) async throws -> PluginQueryResult {
        PluginQueryResult(
            columns: ["id", "name"],
            columnTypeNames: ["INT", "VARCHAR"],
            rows: [["1", "Alice"]],
            rowsAffected: 0,
            executionTime: 0.01
        )
    }

    func fetchTables(schema: String?) async throws -> [PluginTableInfo] {
        [PluginTableInfo(name: "users", type: "TABLE", rowCount: 42)]
    }

    func fetchColumns(table: String, schema: String?) async throws -> [PluginColumnInfo] {
        [PluginColumnInfo(name: "id", dataType: "INT", isPrimaryKey: true)]
    }

    func fetchIndexes(table: String, schema: String?) async throws -> [PluginIndexInfo] {
        [PluginIndexInfo(name: "pk_id", columns: ["id"], isPrimary: true)]
    }

    func fetchForeignKeys(table: String, schema: String?) async throws -> [PluginForeignKeyInfo] { [] }
    func fetchTableDDL(table: String, schema: String?) async throws -> String { "" }
    func fetchViewDefinition(view: String, schema: String?) async throws -> String { "" }
    func fetchTableMetadata(table: String, schema: String?) async throws -> PluginTableMetadata {
        PluginTableMetadata(tableName: table)
    }
    func fetchDatabases() async throws -> [String] { ["db1", "db2"] }
    func fetchDatabaseMetadata(_ database: String) async throws -> PluginDatabaseMetadata {
        PluginDatabaseMetadata(name: database)
    }
}

@Suite("PluginDriverAdapter Tests")
struct PluginDriverAdapterTests {
    @Test("Execute maps PluginQueryResult to QueryResult")
    func executeMapsResult() async throws {
        let stub = StubPluginDriver()
        let adapter = PluginDriverAdapter(pluginDriver: stub)

        let result = try await adapter.execute(query: "SELECT 1")
        #expect(result.columns.count == 2)
        #expect(result.columns[0].name == "id")
        #expect(result.columns[0].typeName == "INT")
        #expect(result.rows.count == 1)
    }

    @Test("FetchTables maps types correctly")
    func fetchTablesMaps() async throws {
        let stub = StubPluginDriver()
        let adapter = PluginDriverAdapter(pluginDriver: stub)

        let tables = try await adapter.fetchTables(schema: nil)
        #expect(tables.count == 1)
        #expect(tables[0].name == "users")
        #expect(tables[0].type == .table)
        #expect(tables[0].rowCount == 42)
    }

    @Test("FetchColumns maps with ordinal position")
    func fetchColumnsMaps() async throws {
        let stub = StubPluginDriver()
        let adapter = PluginDriverAdapter(pluginDriver: stub)

        let columns = try await adapter.fetchColumns(table: "users", schema: nil)
        #expect(columns.count == 1)
        #expect(columns[0].name == "id")
        #expect(columns[0].isPrimaryKey)
        #expect(columns[0].ordinalPosition == 0)
    }

    @Test("Connect and disconnect delegate to plugin driver")
    func connectDisconnect() async throws {
        let stub = StubPluginDriver()
        let adapter = PluginDriverAdapter(pluginDriver: stub)

        try await adapter.connect()
        #expect(stub.connectCalled)

        try await adapter.disconnect()
        #expect(stub.disconnectCalled)
    }

    @Test("Ping returns true on success")
    func pingSuccess() async throws {
        let stub = StubPluginDriver()
        let adapter = PluginDriverAdapter(pluginDriver: stub)

        let alive = try await adapter.ping()
        #expect(alive)
    }

    @Test("FetchDatabases returns list")
    func fetchDatabases() async throws {
        let stub = StubPluginDriver()
        let adapter = PluginDriverAdapter(pluginDriver: stub)

        let dbs = try await adapter.fetchDatabases()
        #expect(dbs == ["db1", "db2"])
    }
}
