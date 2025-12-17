//
//  PostgreSQLDriver.swift
//  OpenTable
//
//  PostgreSQL database driver using psql CLI
//

import Foundation

/// PostgreSQL database driver using command-line interface
final class PostgreSQLDriver: DatabaseDriver {
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
        
        // Parse output from psql
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        guard !lines.isEmpty else {
            return QueryResult(
                columns: [],
                rows: [],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )
        }
        
        // First line is headers (tab-separated in unaligned mode)
        let columns = lines[0].components(separatedBy: "|")
        
        // Remaining lines are data
        var rows: [[String?]] = []
        for i in 1..<lines.count {
            let values = lines[i].components(separatedBy: "|").map { value -> String? in
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty || trimmed == "" ? nil : trimmed
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
    
    // MARK: - Schema
    
    func fetchTables() async throws -> [TableInfo] {
        let query = """
            SELECT table_name, table_type
            FROM information_schema.tables
            WHERE table_schema = 'public'
            ORDER BY table_name
        """
        
        let result = try await execute(query: query)
        
        return result.rows.compactMap { row in
            guard let name = row[0] else { return nil }
            let typeStr = row[1] ?? "BASE TABLE"
            let type: TableInfo.TableType = typeStr.contains("VIEW") ? .view : .table
            
            return TableInfo(name: name, type: type, rowCount: nil)
        }
    }
    
    func fetchColumns(table: String) async throws -> [ColumnInfo] {
        let query = """
            SELECT 
                column_name,
                data_type,
                is_nullable,
                column_default
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = '\(table)'
            ORDER BY ordinal_position
        """
        
        let result = try await execute(query: query)
        
        return result.rows.compactMap { row in
            guard row.count >= 4,
                  let name = row[0],
                  let dataType = row[1] else {
                return nil
            }
            
            let isNullable = row[2] == "YES"
            let defaultValue = row[3]
            
            return ColumnInfo(
                name: name,
                dataType: dataType.uppercased(),
                isNullable: isNullable,
                isPrimaryKey: false,
                defaultValue: defaultValue,
                extra: nil
            )
        }
    }
    
    // MARK: - Helpers
    
    private func executeCommand(_ query: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/psql")
        
        // Build connection string
        var connStr = "host=\(connection.host) port=\(connection.port) dbname=\(connection.database)"
        
        if !connection.username.isEmpty {
            connStr += " user=\(connection.username)"
        }
        
        if let password = ConnectionStorage.shared.loadPassword(for: connection.id), !password.isEmpty {
            connStr += " password=\(password)"
        }
        
        process.arguments = [
            connStr,
            "-t",           // Tuples only (no headers for data)
            "-A",           // Unaligned output
            "-F", "|",      // Field separator
            "-c", query
        ]
        
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
