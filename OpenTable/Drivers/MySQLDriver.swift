//
//  MySQLDriver.swift
//  OpenTable
//
//  MySQL/MariaDB database driver using mysql CLI
//

import Foundation

/// MySQL/MariaDB database driver using command-line interface
final class MySQLDriver: DatabaseDriver {
    let connection: DatabaseConnection
    private(set) var status: ConnectionStatus = .disconnected
    
    init(connection: DatabaseConnection) {
        self.connection = connection
    }
    
    // MARK: - Connection
    
    func connect() async throws {
        status = .connecting
        
        // Test connection by running a simple query
        do {
            _ = try await executeCommand("SELECT 1")
            status = .connected
        } catch {
            status = .error(error.localizedDescription)
            throw error
        }
    }
    
    func disconnect() {
        status = .disconnected
    }
    
    func testConnection() async throws -> Bool {
        try await connect()
        let isConnected = status == .connected
        disconnect()
        return isConnected
    }
    
    // MARK: - Query Execution
    
    func execute(query: String) async throws -> QueryResult {
        let startTime = Date()
        
        let output = try await executeCommand(query)
        
        // Parse tab-separated output from mysql CLI
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        // If empty, try to get columns from table name (for SELECT * queries)
        if lines.isEmpty {
            // Try to extract table name from SELECT query
            if let tableName = extractTableName(from: query) {
                let columns = try await fetchColumnNames(for: tableName)
                return QueryResult(
                    columns: columns,
                    rows: [],
                    rowsAffected: 0,
                    executionTime: Date().timeIntervalSince(startTime),
                    error: nil
                )
            }
            
            return QueryResult(
                columns: [],
                rows: [],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )
        }
        
        // First line is headers
        let columns = lines[0].components(separatedBy: "\t")
        
        // Remaining lines are data
        var rows: [[String?]] = []
        for i in 1..<lines.count {
            let values = lines[i].components(separatedBy: "\t").map { value -> String? in
                value == "NULL" ? nil : value
            }
            rows.append(values)
        }
        
        return QueryResult(
            columns: columns,
            rows: rows,
            rowsAffected: 0,
            executionTime: Date().timeIntervalSince(startTime),
            error: nil
        )
    }
    
    /// Extract table name from SELECT query
    private func extractTableName(from query: String) -> String? {
        let pattern = "(?i)\\bFROM\\s+[`\"']?([\\w]+)[`\"']?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let range = Range(match.range(at: 1), in: query) else {
            return nil
        }
        return String(query[range])
    }
    
    /// Fetch column names using DESCRIBE
    private func fetchColumnNames(for tableName: String) async throws -> [String] {
        let output = try await executeCommand("DESCRIBE `\(tableName)`")
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        // Skip header row (Field, Type, Null, Key, Default, Extra)
        guard lines.count > 1 else { return [] }
        
        var columns: [String] = []
        for i in 1..<lines.count {
            let parts = lines[i].components(separatedBy: "\t")
            if let columnName = parts.first {
                columns.append(columnName)
            }
        }
        return columns
    }
    
    // MARK: - Schema
    
    func fetchTables() async throws -> [TableInfo] {
        let query = "SHOW FULL TABLES"
        let result = try await execute(query: query)
        
        return result.rows.compactMap { row in
            guard let name = row[0] else { return nil }
            let typeStr = row.count > 1 ? (row[1] ?? "BASE TABLE") : "BASE TABLE"
            let type: TableInfo.TableType = typeStr.contains("VIEW") ? .view : .table
            
            return TableInfo(name: name, type: type, rowCount: nil)
        }
    }
    
    func fetchColumns(table: String) async throws -> [ColumnInfo] {
        let query = "SHOW FULL COLUMNS FROM `\(table)`"
        let result = try await execute(query: query)
        
        return result.rows.compactMap { row in
            guard row.count >= 7,
                  let name = row[0],
                  let dataType = row[1] else {
                return nil
            }
            
            let isNullable = row[3] == "YES"
            let isPrimaryKey = row[4] == "PRI"
            let defaultValue = row[5]
            let extra = row[6]
            
            return ColumnInfo(
                name: name,
                dataType: dataType.uppercased(),
                isNullable: isNullable,
                isPrimaryKey: isPrimaryKey,
                defaultValue: defaultValue,
                extra: extra
            )
        }
    }
    
    // MARK: - Helpers
    
    private func executeCommand(_ query: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/mysql")
        
        var arguments = [
            "-h", connection.host,
            "-P", String(connection.port),
            "-u", connection.username,
            "-B", // Batch mode (tab-separated)
            "--column-names", // Always show column headers
            "-e", query
        ]
        
        if !connection.database.isEmpty {
            arguments.insert(contentsOf: ["-D", connection.database], at: 0)
        }
        
        // Get password from Keychain
        if let password = ConnectionStorage.shared.loadPassword(for: connection.id), !password.isEmpty {
            arguments.append("-p\(password)")
        }
        
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: DatabaseError.queryFailed(errorMsg))
                }
            } catch {
                continuation.resume(throwing: DatabaseError.connectionFailed(error.localizedDescription))
            }
        }
    }
}
