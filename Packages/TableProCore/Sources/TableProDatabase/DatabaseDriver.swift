import Foundation
import TableProModels

public protocol DatabaseDriver: AnyObject, Sendable {
    func connect() async throws
    func disconnect() async throws
    func ping() async throws -> Bool

    func execute(query: String) async throws -> QueryResult
    func cancelCurrentQuery() async throws

    func fetchTables(schema: String?) async throws -> [TableInfo]
    func fetchColumns(table: String, schema: String?) async throws -> [ColumnInfo]
    func fetchIndexes(table: String, schema: String?) async throws -> [IndexInfo]
    func fetchForeignKeys(table: String, schema: String?) async throws -> [ForeignKeyInfo]
    func fetchDatabases() async throws -> [String]

    func switchDatabase(to name: String) async throws
    var supportsSchemas: Bool { get }
    func switchSchema(to name: String) async throws
    func fetchSchemas() async throws -> [String]
    var currentSchema: String? { get }

    var supportsTransactions: Bool { get }
    func beginTransaction() async throws
    func commitTransaction() async throws
    func rollbackTransaction() async throws

    var serverVersion: String? { get }
}
