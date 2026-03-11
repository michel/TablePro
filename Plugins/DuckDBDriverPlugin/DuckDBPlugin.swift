//
//  DuckDBPlugin.swift
//  TablePro
//

import CDuckDB
import Foundation
import os
import TableProPluginKit

final class DuckDBPlugin: NSObject, TableProPlugin, DriverPlugin {
    static let pluginName = "DuckDB Driver"
    static let pluginVersion = "1.0.0"
    static let pluginDescription = "DuckDB analytical database support"
    static let capabilities: [PluginCapability] = [.databaseDriver]

    static let databaseTypeId = "DuckDB"
    static let databaseDisplayName = "DuckDB"
    static let iconName = "duckdb-icon"
    static let defaultPort = 0

    func createDriver(config: DriverConnectionConfig) -> any PluginDatabaseDriver {
        DuckDBPluginDriver(config: config)
    }
}

// MARK: - DuckDB Connection Actor

private actor DuckDBConnectionActor {
    private static let logger = Logger(subsystem: "com.TablePro", category: "DuckDBConnectionActor")

    private var database: duckdb_database?
    private var connection: duckdb_connection?

    var isConnected: Bool { connection != nil }

    var connectionHandleForInterrupt: duckdb_connection? { connection }

    func open(path: String) throws {
        var db: duckdb_database?
        let state = duckdb_open(path, &db)

        if state == DuckDBError {
            throw DuckDBPluginError.connectionFailed(
                "Failed to open DuckDB database at '\(path)'"
            )
        }

        var conn: duckdb_connection?
        let connState = duckdb_connect(db, &conn)

        if connState == DuckDBError {
            duckdb_close(&db)
            throw DuckDBPluginError.connectionFailed("Failed to create DuckDB connection")
        }

        database = db
        connection = conn
    }

    func close() {
        if var conn = connection {
            duckdb_disconnect(&conn)
            connection = nil
        }
        if var db = database {
            duckdb_close(&db)
            database = nil
        }
    }

    func executeQuery(_ query: String) throws -> DuckDBRawResult {
        guard let conn = connection else {
            throw DuckDBPluginError.notConnected
        }

        let startTime = Date()
        var result = duckdb_result()

        let state = duckdb_query(conn, query, &result)

        if state == DuckDBError {
            let errorMsg: String
            if let errPtr = duckdb_result_error(&result) {
                errorMsg = String(cString: errPtr)
            } else {
                errorMsg = "Unknown DuckDB error"
            }
            duckdb_destroy_result(&result)
            throw DuckDBPluginError.queryFailed(errorMsg)
        }

        defer {
            duckdb_destroy_result(&result)
        }

        let colCount = duckdb_column_count(&result)
        let rowCount = duckdb_row_count(&result)
        let rowsChanged = duckdb_rows_changed(&result)

        var columns: [String] = []
        var columnTypeNames: [String] = []

        for i in 0..<colCount {
            if let namePtr = duckdb_column_name(&result, i) {
                columns.append(String(cString: namePtr))
            } else {
                columns.append("column_\(i)")
            }

            let colType = duckdb_column_type(&result, i)
            columnTypeNames.append(Self.typeName(for: colType))
        }

        var rows: [[String?]] = []
        var truncated = false

        let maxRows = min(rowCount, UInt64(PluginRowLimits.defaultMax))
        if rowCount > UInt64(PluginRowLimits.defaultMax) {
            truncated = true
        }

        for row in 0..<maxRows {
            var rowData: [String?] = []

            for col in 0..<colCount {
                if duckdb_value_is_null(&result, col, row) {
                    rowData.append(nil)
                } else if let valPtr = duckdb_value_varchar(&result, col, row) {
                    rowData.append(String(cString: valPtr))
                    duckdb_free(valPtr)
                } else {
                    rowData.append(nil)
                }
            }

            rows.append(rowData)
        }

        let executionTime = Date().timeIntervalSince(startTime)

        return DuckDBRawResult(
            columns: columns,
            columnTypeNames: columnTypeNames,
            rows: rows,
            rowsAffected: Int(rowsChanged),
            executionTime: executionTime,
            isTruncated: truncated
        )
    }

    private static func typeName(for type: duckdb_type) -> String {
        switch type {
        case DUCKDB_TYPE_BOOLEAN: return "BOOLEAN"
        case DUCKDB_TYPE_TINYINT: return "TINYINT"
        case DUCKDB_TYPE_SMALLINT: return "SMALLINT"
        case DUCKDB_TYPE_INTEGER: return "INTEGER"
        case DUCKDB_TYPE_BIGINT: return "BIGINT"
        case DUCKDB_TYPE_UTINYINT: return "UTINYINT"
        case DUCKDB_TYPE_USMALLINT: return "USMALLINT"
        case DUCKDB_TYPE_UINTEGER: return "UINTEGER"
        case DUCKDB_TYPE_UBIGINT: return "UBIGINT"
        case DUCKDB_TYPE_FLOAT: return "FLOAT"
        case DUCKDB_TYPE_DOUBLE: return "DOUBLE"
        case DUCKDB_TYPE_TIMESTAMP: return "TIMESTAMP"
        case DUCKDB_TYPE_DATE: return "DATE"
        case DUCKDB_TYPE_TIME: return "TIME"
        case DUCKDB_TYPE_INTERVAL: return "INTERVAL"
        case DUCKDB_TYPE_HUGEINT: return "HUGEINT"
        case DUCKDB_TYPE_VARCHAR: return "VARCHAR"
        case DUCKDB_TYPE_BLOB: return "BLOB"
        case DUCKDB_TYPE_DECIMAL: return "DECIMAL"
        case DUCKDB_TYPE_TIMESTAMP_S: return "TIMESTAMP_S"
        case DUCKDB_TYPE_TIMESTAMP_MS: return "TIMESTAMP_MS"
        case DUCKDB_TYPE_TIMESTAMP_NS: return "TIMESTAMP_NS"
        case DUCKDB_TYPE_ENUM: return "ENUM"
        case DUCKDB_TYPE_LIST: return "LIST"
        case DUCKDB_TYPE_STRUCT: return "STRUCT"
        case DUCKDB_TYPE_MAP: return "MAP"
        case DUCKDB_TYPE_UUID: return "UUID"
        case DUCKDB_TYPE_UNION: return "UNION"
        case DUCKDB_TYPE_BIT: return "BIT"
        default: return "VARCHAR"
        }
    }
}

private struct DuckDBRawResult: Sendable {
    let columns: [String]
    let columnTypeNames: [String]
    let rows: [[String?]]
    let rowsAffected: Int
    let executionTime: TimeInterval
    let isTruncated: Bool
}

// MARK: - DuckDB Plugin Driver

final class DuckDBPluginDriver: PluginDatabaseDriver, @unchecked Sendable {
    private let config: DriverConnectionConfig
    private let connectionActor = DuckDBConnectionActor()
    private let interruptLock = NSLock()
    nonisolated(unsafe) private var _connectionForInterrupt: duckdb_connection?
    private var _currentSchema: String = "main"

    private static let logger = Logger(subsystem: "com.TablePro", category: "DuckDBPluginDriver")
    private static let limitRegex = try? NSRegularExpression(pattern: "(?i)\\s+LIMIT\\s+\\d+")
    private static let offsetRegex = try? NSRegularExpression(pattern: "(?i)\\s+OFFSET\\s+\\d+")

    var currentSchema: String? { _currentSchema }
    var serverVersion: String? { String(cString: duckdb_library_version()) }
    var supportsSchemas: Bool { true }
    var supportsTransactions: Bool { true }

    init(config: DriverConnectionConfig) {
        self.config = config
    }

    // MARK: - Connection

    func connect() async throws {
        let path = expandPath(config.database)

        if !FileManager.default.fileExists(atPath: path) {
            let directory = (path as NSString).deletingLastPathComponent
            if !directory.isEmpty {
                try? FileManager.default.createDirectory(
                    atPath: directory,
                    withIntermediateDirectories: true
                )
            }
        }

        try await connectionActor.open(path: path)

        if let conn = await connectionActor.connectionHandleForInterrupt {
            setInterruptHandle(conn)
        }
    }

    func disconnect() {
        interruptLock.lock()
        _connectionForInterrupt = nil
        interruptLock.unlock()
        let actor = connectionActor
        Task { await actor.close() }
    }

    func ping() async throws {
        _ = try await execute(query: "SELECT 1")
    }

    func applyQueryTimeout(_ seconds: Int) async throws {
        // DuckDB doesn't have a session-level query timeout like network databases
    }

    // MARK: - Query Execution

    func execute(query: String) async throws -> PluginQueryResult {
        let rawResult = try await connectionActor.executeQuery(query)
        return PluginQueryResult(
            columns: rawResult.columns,
            columnTypeNames: rawResult.columnTypeNames,
            rows: rawResult.rows,
            rowsAffected: rawResult.rowsAffected,
            executionTime: rawResult.executionTime,
            isTruncated: rawResult.isTruncated
        )
    }

    func executeParameterized(
        query: String,
        parameters: [String?]
    ) async throws -> PluginQueryResult {
        var processedQuery = query
        for param in parameters {
            if let range = processedQuery.range(of: "?") {
                if let value = param {
                    let escaped = value.replacingOccurrences(of: "'", with: "''")
                    processedQuery.replaceSubrange(range, with: "'\(escaped)'")
                } else {
                    processedQuery.replaceSubrange(range, with: "NULL")
                }
            }
        }
        return try await execute(query: processedQuery)
    }

    func cancelQuery() throws {
        interruptLock.lock()
        let conn = _connectionForInterrupt
        interruptLock.unlock()
        guard let conn else { return }
        duckdb_interrupt(conn)
    }

    // MARK: - Pagination

    func fetchRowCount(query: String) async throws -> Int {
        let baseQuery = stripLimitOffset(from: query)
        let countQuery = "SELECT COUNT(*) FROM (\(baseQuery)) AS _count_subquery"
        let result = try await execute(query: countQuery)
        guard let firstRow = result.rows.first, let countStr = firstRow.first else { return 0 }
        return Int(countStr ?? "0") ?? 0
    }

    func fetchRows(query: String, offset: Int, limit: Int) async throws -> PluginQueryResult {
        let baseQuery = stripLimitOffset(from: query)
        let paginatedQuery = "\(baseQuery) LIMIT \(limit) OFFSET \(offset)"
        return try await execute(query: paginatedQuery)
    }

    // MARK: - Schema Operations

    func fetchTables(schema: String?) async throws -> [PluginTableInfo] {
        let schemaName = schema ?? _currentSchema
        let query = """
            SELECT table_name, table_type
            FROM information_schema.tables
            WHERE table_schema = '\(escapeStringLiteral(schemaName))'
            ORDER BY table_name
        """
        let result = try await execute(query: query)
        return result.rows.compactMap { row in
            guard let name = row[safe: 0] ?? nil else { return nil }
            let typeString = (row[safe: 1] ?? nil) ?? "BASE TABLE"
            let tableType = typeString.uppercased().contains("VIEW") ? "VIEW" : "TABLE"
            return PluginTableInfo(name: name, type: tableType)
        }
    }

    func fetchColumns(table: String, schema: String?) async throws -> [PluginColumnInfo] {
        let schemaName = schema ?? _currentSchema
        let query = """
            SELECT column_name, data_type, is_nullable, column_default, ordinal_position
            FROM information_schema.columns
            WHERE table_schema = '\(escapeStringLiteral(schemaName))'
              AND table_name = '\(escapeStringLiteral(table))'
            ORDER BY ordinal_position
        """
        let result = try await execute(query: query)

        let pkColumns = try await fetchPrimaryKeyColumns(table: table, schema: schemaName)

        return result.rows.compactMap { row in
            guard let name = row[safe: 0] ?? nil,
                  let dataType = row[safe: 1] ?? nil else {
                return nil
            }

            let isNullable = (row[safe: 2] ?? nil) == "YES"
            let defaultValue = row[safe: 3] ?? nil
            let isPrimaryKey = pkColumns.contains(name)

            return PluginColumnInfo(
                name: name,
                dataType: dataType,
                isNullable: isNullable,
                isPrimaryKey: isPrimaryKey,
                defaultValue: defaultValue
            )
        }
    }

    func fetchAllColumns(schema: String?) async throws -> [String: [PluginColumnInfo]] {
        let schemaName = schema ?? _currentSchema
        let query = """
            SELECT table_name, column_name, data_type, is_nullable, column_default, ordinal_position
            FROM information_schema.columns
            WHERE table_schema = '\(escapeStringLiteral(schemaName))'
            ORDER BY table_name, ordinal_position
        """
        let result = try await execute(query: query)

        let pkQuery = """
            SELECT tc.table_name, kcu.column_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON tc.constraint_name = kcu.constraint_name
              AND tc.table_schema = kcu.table_schema
            WHERE tc.constraint_type = 'PRIMARY KEY'
              AND tc.table_schema = '\(escapeStringLiteral(schemaName))'
        """
        let pkResult = try await execute(query: pkQuery)
        var pkMap: [String: Set<String>] = [:]
        for row in pkResult.rows {
            if let tableName = row[safe: 0] ?? nil, let colName = row[safe: 1] ?? nil {
                pkMap[tableName, default: []].insert(colName)
            }
        }

        var allColumns: [String: [PluginColumnInfo]] = [:]

        for row in result.rows {
            guard let tableName = row[safe: 0] ?? nil,
                  let columnName = row[safe: 1] ?? nil,
                  let dataType = row[safe: 2] ?? nil else {
                continue
            }

            let isNullable = (row[safe: 3] ?? nil) == "YES"
            let defaultValue = row[safe: 4] ?? nil
            let isPrimaryKey = pkMap[tableName]?.contains(columnName) ?? false

            let column = PluginColumnInfo(
                name: columnName,
                dataType: dataType,
                isNullable: isNullable,
                isPrimaryKey: isPrimaryKey,
                defaultValue: defaultValue
            )

            allColumns[tableName, default: []].append(column)
        }

        return allColumns
    }

    func fetchIndexes(table: String, schema: String?) async throws -> [PluginIndexInfo] {
        let schemaName = schema ?? _currentSchema
        let query = """
            SELECT index_name, is_unique, sql, index_oid
            FROM duckdb_indexes()
            WHERE schema_name = '\(escapeStringLiteral(schemaName))'
              AND table_name = '\(escapeStringLiteral(table))'
        """

        do {
            let result = try await execute(query: query)
            return result.rows.compactMap { row in
                guard let name = row[safe: 0] ?? nil else { return nil }
                let isUnique = (row[safe: 1] ?? nil) == "true"
                let sql = row[safe: 2] ?? nil
                let isPrimary = name.lowercased().contains("primary")
                    || (sql?.uppercased().contains("PRIMARY KEY") ?? false)

                let columns = extractIndexColumns(from: sql)

                return PluginIndexInfo(
                    name: name,
                    columns: columns,
                    isUnique: isUnique || isPrimary,
                    isPrimary: isPrimary,
                    type: "ART"
                )
            }.sorted { $0.isPrimary && !$1.isPrimary }
        } catch {
            return []
        }
    }

    func fetchForeignKeys(table: String, schema: String?) async throws -> [PluginForeignKeyInfo] {
        let schemaName = schema ?? _currentSchema
        let query = """
            SELECT
                rc.constraint_name,
                kcu.column_name,
                kcu2.table_name AS referenced_table,
                kcu2.column_name AS referenced_column,
                rc.delete_rule,
                rc.update_rule
            FROM information_schema.referential_constraints rc
            JOIN information_schema.key_column_usage kcu
                ON rc.constraint_name = kcu.constraint_name
                AND rc.constraint_schema = kcu.constraint_schema
            JOIN information_schema.key_column_usage kcu2
                ON rc.unique_constraint_name = kcu2.constraint_name
                AND rc.unique_constraint_schema = kcu2.constraint_schema
                AND kcu.ordinal_position = kcu2.ordinal_position
            WHERE kcu.table_schema = '\(escapeStringLiteral(schemaName))'
              AND kcu.table_name = '\(escapeStringLiteral(table))'
        """

        do {
            let result = try await execute(query: query)
            return result.rows.compactMap { row in
                guard let name = row[safe: 0] ?? nil,
                      let column = row[safe: 1] ?? nil,
                      let refTable = row[safe: 2] ?? nil,
                      let refColumn = row[safe: 3] ?? nil else {
                    return nil
                }

                let onDelete = (row[safe: 4] ?? nil) ?? "NO ACTION"
                let onUpdate = (row[safe: 5] ?? nil) ?? "NO ACTION"

                return PluginForeignKeyInfo(
                    name: name,
                    column: column,
                    referencedTable: refTable,
                    referencedColumn: refColumn,
                    onDelete: onDelete,
                    onUpdate: onUpdate
                )
            }
        } catch {
            return []
        }
    }

    func fetchTableDDL(table: String, schema: String?) async throws -> String {
        let schemaName = schema ?? _currentSchema
        let columns = try await fetchColumns(table: table, schema: schemaName)
        let indexes = try await fetchIndexes(table: table, schema: schemaName)
        let fks = try await fetchForeignKeys(table: table, schema: schemaName)

        var ddl = "CREATE TABLE \"\(escapeIdentifier(schemaName))\".\"\(escapeIdentifier(table))\" (\n"

        let columnDefs = columns.map { col in
            var def = "  \"\(escapeIdentifier(col.name))\" \(col.dataType)"
            if !col.isNullable { def += " NOT NULL" }
            if let defaultVal = col.defaultValue { def += " DEFAULT \(defaultVal)" }
            return def
        }

        var allDefs = columnDefs

        let pkColumns = columns.filter(\.isPrimaryKey)
        if !pkColumns.isEmpty {
            let pkCols = pkColumns.map { "\"\(escapeIdentifier($0.name))\"" }
                .joined(separator: ", ")
            allDefs.append("  PRIMARY KEY (\(pkCols))")
        }

        for fk in fks {
            let fkDef = "  FOREIGN KEY (\"\(escapeIdentifier(fk.column))\")"
                + " REFERENCES \"\(escapeIdentifier(fk.referencedTable))\""
                + "(\"\(escapeIdentifier(fk.referencedColumn))\")"
                + " ON DELETE \(fk.onDelete) ON UPDATE \(fk.onUpdate)"
            allDefs.append(fkDef)
        }

        ddl += allDefs.joined(separator: ",\n")
        ddl += "\n);"

        for index in indexes where !index.isPrimary {
            let uniqueStr = index.isUnique ? "UNIQUE " : ""
            let cols = index.columns.map { "\"\(escapeIdentifier($0))\"" }.joined(separator: ", ")
            ddl += "\n\nCREATE \(uniqueStr)INDEX \"\(escapeIdentifier(index.name))\""
                + " ON \"\(escapeIdentifier(schemaName))\".\"\(escapeIdentifier(table))\""
                + " (\(cols));"
        }

        return ddl
    }

    func fetchViewDefinition(view: String, schema: String?) async throws -> String {
        let schemaName = schema ?? _currentSchema
        let query = """
            SELECT view_definition
            FROM information_schema.views
            WHERE table_schema = '\(escapeStringLiteral(schemaName))'
              AND table_name = '\(escapeStringLiteral(view))'
        """
        let result = try await execute(query: query)

        guard let firstRow = result.rows.first,
              let definition = firstRow[0] else {
            throw DuckDBPluginError.queryFailed(
                "Failed to fetch definition for view '\(view)'"
            )
        }

        return "CREATE VIEW \"\(escapeIdentifier(schemaName))\".\"\(escapeIdentifier(view))\" AS\n\(definition)"
    }

    func fetchTableMetadata(table: String, schema: String?) async throws -> PluginTableMetadata {
        let schemaName = schema ?? _currentSchema
        let safeTable = escapeIdentifier(table)
        let safeSchema = escapeIdentifier(schemaName)
        let countQuery =
            "SELECT COUNT(*) FROM (SELECT 1 FROM \"\(safeSchema)\".\"\(safeTable)\" LIMIT 100001)"
        let countResult = try await execute(query: countQuery)
        let rowCount: Int64? = {
            guard let row = countResult.rows.first, let countStr = row.first else { return nil }
            return Int64(countStr ?? "0")
        }()

        return PluginTableMetadata(
            tableName: table,
            rowCount: rowCount,
            engine: "DuckDB"
        )
    }

    // MARK: - Schema Navigation

    func fetchSchemas() async throws -> [String] {
        let query = "SELECT schema_name FROM information_schema.schemata ORDER BY schema_name"
        let result = try await execute(query: query)
        return result.rows.compactMap { $0[safe: 0] ?? nil }
    }

    func switchSchema(to schema: String) async throws {
        _ = try await execute(query: "SET schema = '\(escapeStringLiteral(schema))'")
        _currentSchema = schema
    }

    // MARK: - Database Operations

    func fetchDatabases() async throws -> [String] {
        let query = "PRAGMA database_list"
        let result = try await execute(query: query)
        return result.rows.compactMap { row in
            row[safe: 1] ?? nil
        }
    }

    func fetchDatabaseMetadata(_ database: String) async throws -> PluginDatabaseMetadata {
        PluginDatabaseMetadata(name: database)
    }

    func createDatabase(name: String, charset: String, collation: String?) async throws {
        throw DuckDBPluginError.unsupportedOperation
    }

    // MARK: - Private Helpers

    nonisolated private func setInterruptHandle(_ handle: duckdb_connection?) {
        interruptLock.lock()
        _connectionForInterrupt = handle
        interruptLock.unlock()
    }

    private func expandPath(_ path: String) -> String {
        if path.hasPrefix("~") {
            return NSString(string: path).expandingTildeInPath
        }
        return path
    }

    private func escapeStringLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private func escapeIdentifier(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\"\"")
    }

    private func stripLimitOffset(from query: String) -> String {
        var result = query

        if let limitRegex = Self.limitRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = limitRegex.stringByReplacingMatches(
                in: result, range: range, withTemplate: ""
            )
        }

        if let offsetRegex = Self.offsetRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = offsetRegex.stringByReplacingMatches(
                in: result, range: range, withTemplate: ""
            )
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchPrimaryKeyColumns(
        table: String,
        schema: String
    ) async throws -> Set<String> {
        let query = """
            SELECT kcu.column_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON tc.constraint_name = kcu.constraint_name
              AND tc.table_schema = kcu.table_schema
            WHERE tc.constraint_type = 'PRIMARY KEY'
              AND tc.table_schema = '\(escapeStringLiteral(schema))'
              AND tc.table_name = '\(escapeStringLiteral(table))'
        """
        let result = try await execute(query: query)
        return Set(result.rows.compactMap { $0[safe: 0] ?? nil })
    }

    private func extractIndexColumns(from sql: String?) -> [String] {
        guard let sql else { return [] }

        guard let parenRange = sql.range(of: "(", options: .backwards),
              let closeRange = sql.range(of: ")", options: .backwards) else {
            return []
        }

        let columnsStr = String(sql[parenRange.upperBound..<closeRange.lowerBound])
        return columnsStr.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\"", with: "")
        }
    }
}

// MARK: - Errors

enum DuckDBPluginError: Error {
    case connectionFailed(String)
    case notConnected
    case queryFailed(String)
    case unsupportedOperation
}

extension DuckDBPluginError: PluginDriverError {
    var pluginErrorMessage: String {
        switch self {
        case .connectionFailed(let msg): return msg
        case .notConnected: return String(localized: "Not connected to database")
        case .queryFailed(let msg): return msg
        case .unsupportedOperation: return String(localized: "Operation not supported")
        }
    }
}
