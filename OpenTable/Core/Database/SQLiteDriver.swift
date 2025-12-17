//
//  SQLiteDriver.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import Foundation
import SQLite3

/// Native SQLite database driver using libsqlite3
final class SQLiteDriver: DatabaseDriver {
    let connection: DatabaseConnection
    private(set) var status: ConnectionStatus = .disconnected
    
    private var db: OpaquePointer?
    
    init(connection: DatabaseConnection) {
        self.connection = connection
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Connection
    
    func connect() async throws {
        guard status != .connected else { return }
        
        status = .connecting
        
        let path = expandPath(connection.database)
        
        // Check if file exists (for existing databases)
        if !FileManager.default.fileExists(atPath: path) {
            // Create new database file
            let directory = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        
        let result = sqlite3_open(path, &db)
        
        if result != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            status = .error(errorMessage)
            throw DatabaseError.connectionFailed(errorMessage)
        }
        
        status = .connected
    }
    
    func disconnect() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
        status = .disconnected
    }
    
    // MARK: - Query Execution
    
    func execute(query: String) async throws -> QueryResult {
        guard status == .connected, let db = db else {
            throw DatabaseError.notConnected
        }
        
        let startTime = Date()
        var statement: OpaquePointer?
        
        // Prepare statement
        let prepareResult = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        
        if prepareResult != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.queryFailed(errorMessage)
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        // Get column info
        let columnCount = sqlite3_column_count(statement)
        var columns: [String] = []
        
        for i in 0..<columnCount {
            if let name = sqlite3_column_name(statement, i) {
                columns.append(String(cString: name))
            } else {
                columns.append("column_\(i)")
            }
        }
        
        // Execute and fetch rows
        var rows: [[String?]] = []
        var rowsAffected = 0
        
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String?] = []
            
            for i in 0..<columnCount {
                if sqlite3_column_type(statement, i) == SQLITE_NULL {
                    row.append(nil)
                } else if let text = sqlite3_column_text(statement, i) {
                    row.append(String(cString: text))
                } else {
                    row.append(nil)
                }
            }
            
            rows.append(row)
        }
        
        // For non-SELECT queries, get affected rows
        if columns.isEmpty {
            rowsAffected = Int(sqlite3_changes(db))
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        
        return QueryResult(
            columns: columns,
            rows: rows,
            rowsAffected: rowsAffected,
            executionTime: executionTime,
            error: nil
        )
    }
    
    // MARK: - Schema
    
    func fetchTables() async throws -> [TableInfo] {
        guard status == .connected else {
            throw DatabaseError.notConnected
        }
        
        let query = """
            SELECT name, type FROM sqlite_master 
            WHERE type IN ('table', 'view') 
            AND name NOT LIKE 'sqlite_%'
            ORDER BY name
        """
        
        let result = try await execute(query: query)
        
        return result.rows.compactMap { row in
            guard let name = row[0] else { return nil }
            let typeString = row[1] ?? "table"
            let type: TableInfo.TableType = typeString.lowercased() == "view" ? .view : .table
            
            return TableInfo(name: name, type: type, rowCount: nil)
        }
    }
    
    func fetchColumns(table: String) async throws -> [ColumnInfo] {
        guard status == .connected else {
            throw DatabaseError.notConnected
        }
        
        let query = "PRAGMA table_info('\(table)')"
        let result = try await execute(query: query)
        
        return result.rows.compactMap { row in
            guard row.count >= 6,
                  let name = row[1],
                  let dataType = row[2] else {
                return nil
            }
            
            let isNullable = row[3] == "0"
            let isPrimaryKey = row[5] == "1"
            let defaultValue = row[4]
            
            return ColumnInfo(
                name: name,
                dataType: dataType,
                isNullable: isNullable,
                isPrimaryKey: isPrimaryKey,
                defaultValue: defaultValue,
                extra: nil
            )
        }
    }
    
    func fetchIndexes(table: String) async throws -> [IndexInfo] {
        guard status == .connected else {
            throw DatabaseError.notConnected
        }
        
        // Get list of indexes for this table
        let indexListQuery = "PRAGMA index_list('\(table)')"
        let indexListResult = try await execute(query: indexListQuery)
        
        var indexes: [IndexInfo] = []
        
        for row in indexListResult.rows {
            guard row.count >= 3,
                  let indexName = row[1] else { continue }
            
            let isUnique = row[2] == "1"
            let origin = row.count >= 4 ? (row[3] ?? "c") : "c"  // c=CREATE INDEX, pk=PRIMARY KEY
            
            // Get columns for this index
            let indexInfoQuery = "PRAGMA index_info('\(indexName)')"
            let indexInfoResult = try await execute(query: indexInfoQuery)
            
            let columns = indexInfoResult.rows.compactMap { $0.count >= 3 ? $0[2] : nil }
            
            indexes.append(IndexInfo(
                name: indexName,
                columns: columns,
                isUnique: isUnique,
                isPrimary: origin == "pk",
                type: "BTREE"
            ))
        }
        
        return indexes.sorted { $0.isPrimary && !$1.isPrimary }
    }
    
    func fetchForeignKeys(table: String) async throws -> [ForeignKeyInfo] {
        guard status == .connected else {
            throw DatabaseError.notConnected
        }
        
        let query = "PRAGMA foreign_key_list('\(table)')"
        let result = try await execute(query: query)
        
        return result.rows.compactMap { row in
            guard row.count >= 5,
                  let refTable = row[2],
                  let fromCol = row[3],
                  let toCol = row[4] else {
                return nil
            }
            
            let id = row[0] ?? "0"
            let onUpdate = row.count >= 6 ? (row[5] ?? "NO ACTION") : "NO ACTION"
            let onDelete = row.count >= 7 ? (row[6] ?? "NO ACTION") : "NO ACTION"
            
            return ForeignKeyInfo(
                name: "fk_\(table)_\(id)",
                column: fromCol,
                referencedTable: refTable,
                referencedColumn: toCol,
                onDelete: onDelete,
                onUpdate: onUpdate
            )
        }
    }
    
    // MARK: - Paginated Query Support
    
    func fetchRowCount(query: String) async throws -> Int {
        let baseQuery = stripLimitOffset(from: query)
        let countQuery = "SELECT COUNT(*) FROM (\(baseQuery))"
        
        let result = try await execute(query: countQuery)
        guard let firstRow = result.rows.first, let countStr = firstRow.first else { return 0 }
        return Int(countStr ?? "0") ?? 0
    }
    
    func fetchRows(query: String, offset: Int, limit: Int) async throws -> QueryResult {
        let baseQuery = stripLimitOffset(from: query)
        let paginatedQuery = "\(baseQuery) LIMIT \(limit) OFFSET \(offset)"
        return try await execute(query: paginatedQuery)
    }
    
    private func stripLimitOffset(from query: String) -> String {
        var result = query
        
        let limitPattern = "(?i)\\s+LIMIT\\s+\\d+"
        if let regex = try? NSRegularExpression(pattern: limitPattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        
        let offsetPattern = "(?i)\\s+OFFSET\\s+\\d+"
        if let regex = try? NSRegularExpression(pattern: offsetPattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Helpers
    
    private func expandPath(_ path: String) -> String {
        if path.hasPrefix("~") {
            return NSString(string: path).expandingTildeInPath
        }
        return path
    }
}
