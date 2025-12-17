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
    
    // MARK: - Helpers
    
    private func expandPath(_ path: String) -> String {
        if path.hasPrefix("~") {
            return NSString(string: path).expandingTildeInPath
        }
        return path
    }
}
