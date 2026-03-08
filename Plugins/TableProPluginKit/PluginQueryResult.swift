import Foundation

public struct PluginQueryResult: Codable, Sendable {
    public let columns: [String]
    public let columnTypeNames: [String]
    public let rows: [[String?]]
    public let rowsAffected: Int
    public let executionTime: TimeInterval

    public init(
        columns: [String],
        columnTypeNames: [String],
        rows: [[String?]],
        rowsAffected: Int,
        executionTime: TimeInterval
    ) {
        self.columns = columns
        self.columnTypeNames = columnTypeNames
        self.rows = rows
        self.rowsAffected = rowsAffected
        self.executionTime = executionTime
    }

    public static let empty = PluginQueryResult(
        columns: [],
        columnTypeNames: [],
        rows: [],
        rowsAffected: 0,
        executionTime: 0
    )
}
