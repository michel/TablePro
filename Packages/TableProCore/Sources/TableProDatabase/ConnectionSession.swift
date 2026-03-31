import Foundation
import TableProModels

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
