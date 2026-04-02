import Foundation
import TableProModels

/// Note: Views hold a snapshot of this struct. Mutable fields (activeDatabase, status)
/// are only updated through ConnectionManager.updateSession and should be re-fetched
/// from the manager when needed rather than read from a held copy.
public struct ConnectionSession: Sendable {
    public let connectionId: UUID
    public let driver: any DatabaseDriver
    public internal(set) var activeDatabase: String
    public internal(set) var currentSchema: String?
    public internal(set) var status: ConnectionStatus
    public internal(set) var tables: [TableInfo]

    public init(
        connectionId: UUID,
        driver: any DatabaseDriver,
        activeDatabase: String,
        currentSchema: String? = nil,
        status: ConnectionStatus = .connected,
        tables: [TableInfo] = []
    ) {
        self.connectionId = connectionId
        self.driver = driver
        self.activeDatabase = activeDatabase
        self.currentSchema = currentSchema
        self.status = status
        self.tables = tables
    }
}
