//
//  QueryResult.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import Foundation

/// Result of a database query execution
struct QueryResult {
    let columns: [String]
    let rows: [[String?]]
    let rowsAffected: Int
    let executionTime: TimeInterval
    let error: DatabaseError?
    
    var isEmpty: Bool {
        rows.isEmpty
    }
    
    var rowCount: Int {
        rows.count
    }
    
    var columnCount: Int {
        columns.count
    }
    
    /// Convert to QueryResultRow format for UI
    func toQueryResultRows() -> [QueryResultRow] {
        rows.map { row in
            QueryResultRow(values: row)
        }
    }
    
    static let empty = QueryResult(
        columns: [],
        rows: [],
        rowsAffected: 0,
        executionTime: 0,
        error: nil
    )
}

/// Database error types
enum DatabaseError: Error, LocalizedError {
    case connectionFailed(String)
    case queryFailed(String)
    case invalidCredentials
    case fileNotFound(String)
    case notConnected
    case unsupportedOperation
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .invalidCredentials:
            return "Invalid username or password"
        case .fileNotFound(let path):
            return "Database file not found: \(path)"
        case .notConnected:
            return "Not connected to database"
        case .unsupportedOperation:
            return "This operation is not supported"
        }
    }
}

/// Information about a database table
struct TableInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let type: TableType
    let rowCount: Int?
    
    enum TableType: String {
        case table = "TABLE"
        case view = "VIEW"
        case systemTable = "SYSTEM TABLE"
    }
}

/// Information about a table column
struct ColumnInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let dataType: String
    let isNullable: Bool
    let isPrimaryKey: Bool
    let defaultValue: String?
    let extra: String?
}

/// Connection status
enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
    
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
