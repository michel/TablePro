import Testing
import Foundation
@testable import TableProDatabase
@testable import TableProModels
@testable import TableProPluginKit

// MARK: - Mock Types

private final class MockPluginDriver: PluginDatabaseDriver, @unchecked Sendable {
    var connected = false
    var disconnected = false

    func connect() async throws {
        connected = true
    }

    func disconnect() {
        disconnected = true
    }

    func execute(query: String) async throws -> PluginQueryResult {
        .empty
    }

    func fetchTables(schema: String?) async throws -> [PluginTableInfo] { [] }
    func fetchColumns(table: String, schema: String?) async throws -> [PluginColumnInfo] { [] }
    func fetchIndexes(table: String, schema: String?) async throws -> [PluginIndexInfo] { [] }
    func fetchForeignKeys(table: String, schema: String?) async throws -> [PluginForeignKeyInfo] { [] }
    func fetchTableDDL(table: String, schema: String?) async throws -> String { "" }
    func fetchViewDefinition(view: String, schema: String?) async throws -> String { "" }
    func fetchTableMetadata(table: String, schema: String?) async throws -> PluginTableMetadata {
        PluginTableMetadata(tableName: table)
    }
    func fetchDatabases() async throws -> [String] { [] }
    func fetchDatabaseMetadata(_ database: String) async throws -> PluginDatabaseMetadata {
        PluginDatabaseMetadata(name: database)
    }
}

private final class MockDriverPlugin: DriverPlugin {
    static var pluginName: String { "MockDriver" }
    static var pluginVersion: String { "1.0" }
    static var pluginDescription: String { "Mock" }
    static var capabilities: [PluginCapability] { [.databaseDriver] }

    static var databaseTypeId: String { "mock" }
    static var databaseDisplayName: String { "Mock DB" }
    static var iconName: String { "server.rack" }
    static var defaultPort: Int { 5432 }

    required init() {}

    private static let sharedDriver = MockPluginDriver()

    func createDriver(config: DriverConnectionConfig) -> any PluginDatabaseDriver {
        MockDriverPlugin.sharedDriver
    }
}

private final class MockPluginLoader: PluginLoader, Sendable {
    func availablePlugins() -> [any DriverPlugin] {
        [MockDriverPlugin()]
    }

    func driverPlugin(for typeId: String) -> (any DriverPlugin)? {
        if typeId == "mock" { return MockDriverPlugin() }
        return nil
    }
}

private final class MockSecureStore: SecureStore, Sendable {
    private let passwords: [String: String]

    init(passwords: [String: String] = [:]) {
        self.passwords = passwords
    }

    func store(_ value: String, forKey key: String) throws {}

    func retrieve(forKey key: String) throws -> String? {
        passwords[key]
    }

    func delete(forKey key: String) throws {}
}

@Suite("ConnectionManager Tests")
struct ConnectionManagerTests {
    @Test("Connect creates a session")
    func connectCreatesSession() async throws {
        let loader = MockPluginLoader()
        let store = MockSecureStore()
        let manager = ConnectionManager(pluginLoader: loader, secureStore: store)

        let connection = DatabaseConnection(
            name: "Test",
            type: DatabaseType(rawValue: "mock"),
            host: "localhost",
            port: 5432
        )

        let session = try await manager.connect(connection)
        #expect(session.connectionId == connection.id)
        #expect(session.activeDatabase == connection.database)

        let retrieved = manager.session(for: connection.id)
        #expect(retrieved != nil)
    }

    @Test("Disconnect removes session")
    func disconnectRemovesSession() async throws {
        let loader = MockPluginLoader()
        let store = MockSecureStore()
        let manager = ConnectionManager(pluginLoader: loader, secureStore: store)

        let connection = DatabaseConnection(
            name: "Test",
            type: DatabaseType(rawValue: "mock")
        )

        _ = try await manager.connect(connection)
        await manager.disconnect(connection.id)

        let session = manager.session(for: connection.id)
        #expect(session == nil)
    }

    @Test("Connect with unknown plugin throws error")
    func connectUnknownPlugin() async throws {
        let loader = MockPluginLoader()
        let store = MockSecureStore()
        let manager = ConnectionManager(pluginLoader: loader, secureStore: store)

        let connection = DatabaseConnection(
            name: "Test",
            type: DatabaseType(rawValue: "nonexistent")
        )

        await #expect(throws: ConnectionError.self) {
            _ = try await manager.connect(connection)
        }
    }

    @Test("Connect with SSH but no provider throws error")
    func connectSSHNoProvider() async throws {
        let loader = MockPluginLoader()
        let store = MockSecureStore()
        let manager = ConnectionManager(pluginLoader: loader, secureStore: store, sshProvider: nil)

        var connection = DatabaseConnection(
            name: "Test",
            type: DatabaseType(rawValue: "mock")
        )
        connection.sshEnabled = true
        connection.sshConfiguration = SSHConfiguration(host: "jump.example.com")

        await #expect(throws: ConnectionError.self) {
            _ = try await manager.connect(connection)
        }
    }
}
