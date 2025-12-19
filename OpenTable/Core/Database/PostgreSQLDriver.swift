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
                c.column_name,
                c.data_type,
                c.is_nullable,
                c.column_default,
                c.collation_name,
                pgd.description
            FROM information_schema.columns c
            LEFT JOIN pg_catalog.pg_statio_all_tables st 
                ON st.schemaname = c.table_schema 
                AND st.relname = c.table_name
            LEFT JOIN pg_catalog.pg_description pgd 
                ON pgd.objoid = st.relid 
                AND pgd.objsubid = c.ordinal_position
            WHERE c.table_schema = 'public' AND c.table_name = '\(table)'
            ORDER BY c.ordinal_position
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
            let collation = row.count > 4 ? row[4] : nil
            let comment = row.count > 5 ? row[5] : nil
            
            // PostgreSQL doesn't have separate charset - it uses database encoding
            // Collation format: "en_US.UTF-8" or "C" or "POSIX"
            let charset: String? = {
                guard let coll = collation else { return nil }
                if coll.contains(".") {
                    // Extract encoding from "locale.ENCODING" format
                    return coll.components(separatedBy: ".").last
                }
                return nil
            }()
            
            return ColumnInfo(
                name: name,
                dataType: dataType.uppercased(),
                isNullable: isNullable,
                isPrimaryKey: false,
                defaultValue: defaultValue,
                extra: nil,
                charset: charset,
                collation: collation,
                comment: comment?.isEmpty == false ? comment : nil
            )
        }
    }
    
    func fetchIndexes(table: String) async throws -> [IndexInfo] {
        let query = """
            SELECT
                i.relname AS index_name,
                ARRAY_AGG(a.attname ORDER BY array_position(ix.indkey, a.attnum)) AS columns,
                ix.indisunique AS is_unique,
                ix.indisprimary AS is_primary,
                am.amname AS index_type
            FROM pg_index ix
            JOIN pg_class i ON i.oid = ix.indexrelid
            JOIN pg_class t ON t.oid = ix.indrelid
            JOIN pg_am am ON am.oid = i.relam
            JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
            WHERE t.relname = '\(table)'
            GROUP BY i.relname, ix.indisunique, ix.indisprimary, am.amname
            ORDER BY ix.indisprimary DESC, i.relname
            """
        
        let result = try await execute(query: query)
        
        return result.rows.compactMap { row in
            guard row.count >= 5,
                  let name = row[0],
                  let columnsStr = row[1] else {
                return nil
            }
            
            // Parse PostgreSQL array format: {col1,col2}
            let columns = columnsStr
                .trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                .components(separatedBy: ",")
            
            return IndexInfo(
                name: name,
                columns: columns,
                isUnique: row[2] == "t",
                isPrimary: row[3] == "t",
                type: row[4]?.uppercased() ?? "BTREE"
            )
        }
    }
    
    func fetchForeignKeys(table: String) async throws -> [ForeignKeyInfo] {
        let query = """
            SELECT
                tc.constraint_name,
                kcu.column_name,
                ccu.table_name AS referenced_table,
                ccu.column_name AS referenced_column,
                rc.delete_rule,
                rc.update_rule
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
                ON tc.constraint_name = kcu.constraint_name
            JOIN information_schema.referential_constraints rc
                ON tc.constraint_name = rc.constraint_name
            JOIN information_schema.constraint_column_usage ccu
                ON rc.unique_constraint_name = ccu.constraint_name
            WHERE tc.table_name = '\(table)'
                AND tc.constraint_type = 'FOREIGN KEY'
            ORDER BY tc.constraint_name
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
        let baseQuery = stripLimitOffset(from: query)
        let countQuery = "SELECT COUNT(*) FROM (\(baseQuery)) AS __count_subquery__"
        
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
