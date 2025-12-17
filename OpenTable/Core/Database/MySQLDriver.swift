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
        // Note: MySQL batch mode escapes special characters in field values:
        // - Newlines become \n (literal backslash-n)
        // - Tabs become \t (literal backslash-t)
        // - Backslashes become \\ (double backslash)
        // We split by actual newlines (record separators) then unescape field values
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
                if value == "NULL" {
                    return nil
                }
                // Unescape MySQL batch mode escape sequences
                return unescapeMySQLValue(value)
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
    
    /// Unescape MySQL batch mode escape sequences
    /// MySQL -B mode escapes: \n -> newline, \t -> tab, \\ -> backslash, \0 -> null byte
    /// Note: We keep \0 as-is instead of converting to actual null bytes because
    /// null bytes can cause string truncation issues in UI components (NSTextField, etc.)
    /// and in Swift String operations. PHP serialized data commonly contains \0 for
    /// protected/private property markers which we want to preserve for display.
    private func unescapeMySQLValue(_ value: String) -> String {
        var result = ""
        var iterator = value.makeIterator()
        
        while let char = iterator.next() {
            if char == "\\" {
                if let next = iterator.next() {
                    switch next {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    case "\\": result.append("\\")
                    case "0":
                        // Keep escaped null as visible representation instead of actual null byte
                        // Null bytes can truncate strings in many contexts
                        result.append("\\0")
                    default:
                        // Unknown escape, keep as-is
                        result.append("\\")
                        result.append(next)
                    }
                } else {
                    // Trailing backslash
                    result.append("\\")
                }
            } else {
                result.append(char)
            }
        }
        
        return result
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
    
    func fetchIndexes(table: String) async throws -> [IndexInfo] {
        let query = "SHOW INDEX FROM `\(table)`"
        let result = try await execute(query: query)
        
        // Group by index name (Key_name is column index 2)
        var indexMap: [String: (columns: [String], isUnique: Bool, type: String)] = [:]
        
        for row in result.rows {
            guard row.count >= 11,
                  let indexName = row[2],     // Key_name
                  let columnName = row[4] else {  // Column_name
                continue
            }
            
            let nonUnique = row[1] == "1"  // Non_unique: 0 = unique, 1 = not unique
            let indexType = row[10] ?? "BTREE"  // Index_type
            
            if var existing = indexMap[indexName] {
                existing.columns.append(columnName)
                indexMap[indexName] = existing
            } else {
                indexMap[indexName] = (
                    columns: [columnName],
                    isUnique: !nonUnique,
                    type: indexType
                )
            }
        }
        
        return indexMap.map { name, info in
            IndexInfo(
                name: name,
                columns: info.columns,
                isUnique: info.isUnique,
                isPrimary: name == "PRIMARY",
                type: info.type
            )
        }.sorted { $0.isPrimary && !$1.isPrimary }  // PRIMARY key first
    }
    
    func fetchForeignKeys(table: String) async throws -> [ForeignKeyInfo] {
        // Get database name from connection
        let dbName = connection.database
        
        let query = """
            SELECT
                kcu.CONSTRAINT_NAME,
                kcu.COLUMN_NAME,
                kcu.REFERENCED_TABLE_NAME,
                kcu.REFERENCED_COLUMN_NAME,
                rc.DELETE_RULE,
                rc.UPDATE_RULE
            FROM information_schema.KEY_COLUMN_USAGE kcu
            JOIN information_schema.REFERENTIAL_CONSTRAINTS rc
                ON kcu.CONSTRAINT_NAME = rc.CONSTRAINT_NAME
                AND kcu.CONSTRAINT_SCHEMA = rc.CONSTRAINT_SCHEMA
            WHERE kcu.TABLE_SCHEMA = '\(dbName)'
                AND kcu.TABLE_NAME = '\(table)'
                AND kcu.REFERENCED_TABLE_NAME IS NOT NULL
            ORDER BY kcu.CONSTRAINT_NAME
            """
        
        let result = try await execute(query: query)
        
        return result.rows.compactMap { row in
            guard row.count >= 6,
                  let name = row[0],
                  let column = row[1],
                  let refTable = row[2],
                  let refColumn = row[3] else {
                return nil
            }
            
            return ForeignKeyInfo(
                name: name,
                column: column,
                referencedTable: refTable,
                referencedColumn: refColumn,
                onDelete: row[4] ?? "NO ACTION",
                onUpdate: row[5] ?? "NO ACTION"
            )
        }
    }
    
    // MARK: - Paginated Query Support
    
    func fetchRowCount(query: String) async throws -> Int {
        // Strip any existing LIMIT/OFFSET from the query
        let baseQuery = stripLimitOffset(from: query)
        let countQuery = "SELECT COUNT(*) AS cnt FROM (\(baseQuery)) AS __count_subquery__"
        
        let output = try await executeCommand(countQuery)
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        // Skip header (cnt), get first data row
        guard lines.count > 1 else { return 0 }
        return Int(lines[1].trimmingCharacters(in: .whitespaces)) ?? 0
    }
    
    func fetchRows(query: String, offset: Int, limit: Int) async throws -> QueryResult {
        // Strip any existing LIMIT/OFFSET and apply new ones
        let baseQuery = stripLimitOffset(from: query)
        let paginatedQuery = "\(baseQuery) LIMIT \(limit) OFFSET \(offset)"
        return try await execute(query: paginatedQuery)
    }
    
    /// Remove LIMIT and OFFSET clauses from a query
    private func stripLimitOffset(from query: String) -> String {
        var result = query
        
        // Remove LIMIT clause (handles LIMIT n or LIMIT n, m)
        let limitPattern = "(?i)\\s+LIMIT\\s+\\d+(\\s*,\\s*\\d+)?"
        if let regex = try? NSRegularExpression(pattern: limitPattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        
        // Remove OFFSET clause
        let offsetPattern = "(?i)\\s+OFFSET\\s+\\d+"
        if let regex = try? NSRegularExpression(pattern: offsetPattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
        
        // Read output data asynchronously to avoid pipe buffer deadlock
        // (Process can block if pipe buffer fills before we start reading)
        var outputData = Data()
        var errorData = Data()
        
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        
        return try await withCheckedThrowingContinuation { continuation in
            // Set up async reading of stdout
            outputHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    outputHandle.readabilityHandler = nil
                } else {
                    outputData.append(data)
                }
            }
            
            // Set up async reading of stderr
            errorHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    errorHandle.readabilityHandler = nil
                } else {
                    errorData.append(data)
                }
            }
            
            process.terminationHandler = { proc in
                // Ensure we read any remaining data
                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil
                
                // Read any remaining data in the pipes
                outputData.append(outputHandle.readDataToEndOfFile())
                errorData.append(errorHandle.readDataToEndOfFile())
                
                if proc.terminationStatus == 0 {
                    // Try UTF-8 first, then fall back to ISO Latin 1 for non-UTF-8 data
                    let output: String
                    if let utf8String = String(data: outputData, encoding: .utf8) {
                        output = utf8String
                    } else if let latin1String = String(data: outputData, encoding: .isoLatin1) {
                        print("[MySQLDriver] Warning: Output contained non-UTF-8 data, using Latin-1 fallback")
                        output = latin1String
                    } else {
                        print("[MySQLDriver] Error: Could not decode output data (\(outputData.count) bytes)")
                        output = ""
                    }
                    
                    // Debug: log if output is suspiciously empty for a SELECT query
                    if output.isEmpty && outputData.count > 0 {
                        print("[MySQLDriver] Warning: Output data was \(outputData.count) bytes but decoded to empty string")
                    }
                    
                    continuation.resume(returning: output)
                } else {
                    let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: DatabaseError.queryFailed(errorMsg))
                }
            }
            
            do {
                try process.run()
            } catch {
                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil
                continuation.resume(throwing: DatabaseError.connectionFailed(error.localizedDescription))
            }
        }
    }
}
