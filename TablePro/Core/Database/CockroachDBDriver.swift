//
//  CockroachDBDriver.swift
//  TablePro
//
//  CockroachDB database driver using libpq (PostgreSQL wire protocol)
//

import Foundation
import os

/// CockroachDB database driver using libpq native library
final class CockroachDBDriver: DatabaseDriver {
    let connection: DatabaseConnection
    private(set) var status: ConnectionStatus = .disconnected

    private var libpqConnection: LibPQConnection?

    private static let logger = Logger(subsystem: "com.TablePro", category: "CockroachDBDriver")

    private static let limitRegex = try? NSRegularExpression(pattern: "(?i)\\s+LIMIT\\s+\\d+")
    private static let offsetRegex = try? NSRegularExpression(pattern: "(?i)\\s+OFFSET\\s+\\d+")

    private(set) var currentSchema: String = "public"

    var escapedSchema: String {
        SQLEscaping.escapeStringLiteral(currentSchema, databaseType: .cockroachdb)
    }

    var serverVersion: String? {
        libpqConnection?.serverVersion()
    }

    init(connection: DatabaseConnection) {
        self.connection = connection
    }

    // MARK: - Connection

    func connect() async throws {
        status = .connecting

        let pqConn = LibPQConnection(
            host: connection.host,
            port: connection.port,
            user: connection.username,
            password: ConnectionStorage.shared.loadPassword(for: connection.id),
            database: connection.database,
            sslConfig: connection.sslConfig
        )

        do {
            try await pqConn.connect()
            self.libpqConnection = pqConn
            status = .connected

            if let schemaResult = try? await pqConn.executeQuery("SELECT current_schema()"),
               let schema = schemaResult.rows.first?.first.flatMap({ $0 }) {
                currentSchema = schema
            }
        } catch {
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func disconnect() {
        libpqConnection?.disconnect()
        libpqConnection = nil
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
        try await executeWithReconnect(query: query, isRetry: false)
    }

    private func executeWithReconnect(query: String, isRetry: Bool) async throws -> QueryResult {
        guard let pqConn = libpqConnection else {
            throw DatabaseError.connectionFailed("Not connected to CockroachDB")
        }

        let startTime = Date()

        do {
            let result = try await pqConn.executeQuery(query)

            let columnTypes = zip(result.columnOids, result.columnTypeNames).map { oid, rawType in
                ColumnType(fromPostgreSQLOid: oid, rawType: rawType)
            }

            return QueryResult(
                columns: result.columns,
                columnTypes: columnTypes,
                rows: result.rows,
                rowsAffected: result.affectedRows,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil,
                isTruncated: result.isTruncated
            )
        } catch let error as NSError where !isRetry && isConnectionLostError(error) {
            try await reconnect()
            return try await executeWithReconnect(query: query, isRetry: true)
        } catch {
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    // MARK: - Auto-Reconnect

    private func isConnectionLostError(_ error: NSError) -> Bool {
        let errorMessage = error.localizedDescription.lowercased()
        return errorMessage.contains("connection") &&
            (errorMessage.contains("lost") ||
                errorMessage.contains("closed") ||
                errorMessage.contains("no connection") ||
                errorMessage.contains("could not send"))
    }

    private func reconnect() async throws {
        libpqConnection?.disconnect()
        libpqConnection = nil
        status = .connecting
        try await connect()
    }

    // MARK: - Query Cancellation

    func cancelQuery() throws {
        libpqConnection?.cancelCurrentQuery()
    }

    func executeParameterized(query: String, parameters: [Any?]) async throws -> QueryResult {
        try await executeParameterizedWithReconnect(query: query, parameters: parameters, isRetry: false)
    }

    private func executeParameterizedWithReconnect(
        query: String,
        parameters: [Any?],
        isRetry: Bool
    ) async throws -> QueryResult {
        guard let pqConn = libpqConnection else {
            throw DatabaseError.connectionFailed("Not connected to CockroachDB")
        }

        let startTime = Date()

        do {
            let result = try await pqConn.executeParameterizedQuery(query, parameters: parameters)

            let columnTypes = zip(result.columnOids, result.columnTypeNames).map { oid, rawType in
                ColumnType(fromPostgreSQLOid: oid, rawType: rawType)
            }

            return QueryResult(
                columns: result.columns,
                columnTypes: columnTypes,
                rows: result.rows,
                rowsAffected: result.affectedRows,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil,
                isTruncated: result.isTruncated
            )
        } catch let error as NSError where !isRetry && isConnectionLostError(error) {
            try await reconnect()
            return try await executeParameterizedWithReconnect(query: query, parameters: parameters, isRetry: true)
        } catch {
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    // MARK: - Schema

    func fetchTables() async throws -> [TableInfo] {
        let query = """
            SELECT table_name, table_type
            FROM information_schema.tables
            WHERE table_schema = '\(escapedSchema)'
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
        let safeTable = SQLEscaping.escapeStringLiteral(table, databaseType: .cockroachdb)
        let query = """
            SELECT
                c.column_name,
                c.data_type,
                c.is_nullable,
                c.column_default,
                c.collation_name,
                pgd.description,
                c.udt_name
            FROM information_schema.columns c
            LEFT JOIN pg_catalog.pg_class cls
                ON cls.relname = c.table_name
                AND cls.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = c.table_schema)
            LEFT JOIN pg_catalog.pg_description pgd
                ON pgd.objoid = cls.oid
                AND pgd.objsubid = c.ordinal_position
            WHERE c.table_schema = '\(escapedSchema)' AND c.table_name = '\(safeTable)'
            ORDER BY c.ordinal_position
            """

        let result = try await execute(query: query)

        return result.rows.compactMap { row in
            guard row.count >= 4,
                  let name = row[0],
                  let rawDataType = row[1]
            else {
                return nil
            }

            let udtName = row.count > 6 ? row[6] : nil

            let dataType: String
            if rawDataType.uppercased() == "USER-DEFINED", let udt = udtName {
                dataType = "ENUM(\(udt))"
            } else {
                dataType = rawDataType.uppercased()
            }

            let isNullable = row[2] == "YES"
            let defaultValue = row[3]
            let collation = row.count > 4 ? row[4] : nil
            let comment = row.count > 5 ? row[5] : nil

            let charset: String? = {
                guard let coll = collation else { return nil }
                if coll.contains(".") {
                    return coll.components(separatedBy: ".").last
                }
                return nil
            }()

            return ColumnInfo(
                name: name,
                dataType: dataType,
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

    func fetchAllColumns() async throws -> [String: [ColumnInfo]] {
        let query = """
            SELECT
                c.table_name,
                c.column_name,
                c.data_type,
                c.is_nullable,
                c.column_default,
                c.collation_name,
                pgd.description,
                c.udt_name
            FROM information_schema.columns c
            LEFT JOIN pg_catalog.pg_class cls
                ON cls.relname = c.table_name
                AND cls.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = c.table_schema)
            LEFT JOIN pg_catalog.pg_description pgd
                ON pgd.objoid = cls.oid
                AND pgd.objsubid = c.ordinal_position
            WHERE c.table_schema = '\(escapedSchema)'
            ORDER BY c.table_name, c.ordinal_position
            """

        let result = try await execute(query: query)

        var allColumns: [String: [ColumnInfo]] = [:]
        for row in result.rows {
            guard row.count >= 5,
                  let tableName = row[0],
                  let name = row[1],
                  let rawDataType = row[2]
            else {
                continue
            }

            let udtName = row.count > 7 ? row[7] : nil

            let dataType: String
            if rawDataType.uppercased() == "USER-DEFINED", let udt = udtName {
                dataType = "ENUM(\(udt))"
            } else {
                dataType = rawDataType.uppercased()
            }

            let isNullable = row[3] == "YES"
            let defaultValue = row[4]
            let collation = row.count > 5 ? row[5] : nil
            let comment = row.count > 6 ? row[6] : nil

            let charset: String? = {
                guard let coll = collation else { return nil }
                if coll.contains(".") {
                    return coll.components(separatedBy: ".").last
                }
                return nil
            }()

            let column = ColumnInfo(
                name: name,
                dataType: dataType,
                isNullable: isNullable,
                isPrimaryKey: false,
                defaultValue: defaultValue,
                extra: nil,
                charset: charset,
                collation: collation,
                comment: comment?.isEmpty == false ? comment : nil
            )

            allColumns[tableName, default: []].append(column)
        }

        return allColumns
    }

    func fetchIndexes(table: String) async throws -> [IndexInfo] {
        let safeTable = SQLEscaping.escapeStringLiteral(table, databaseType: .cockroachdb)
        let query = """
            SELECT
                i.relname AS index_name,
                array_to_string(array_agg(a.attname ORDER BY x.ordinality), ', ') AS columns,
                ix.indisunique,
                ix.indisprimary,
                am.amname AS index_type
            FROM pg_index ix
            JOIN pg_class t ON t.oid = ix.indrelid
            JOIN pg_class i ON i.oid = ix.indexrelid
            JOIN pg_namespace n ON n.oid = t.relnamespace
            JOIN pg_am am ON am.oid = i.relam
            CROSS JOIN LATERAL unnest(ix.indkey) WITH ORDINALITY AS x(attnum, ordinality)
            JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = x.attnum
            WHERE t.relname = '\(safeTable)'
              AND n.nspname = '\(escapedSchema)'
            GROUP BY i.relname, ix.indisunique, ix.indisprimary, am.amname
            ORDER BY i.relname
            """

        let result = try await execute(query: query)

        return result.rows.compactMap { row in
            guard row.count >= 5,
                  let name = row[0],
                  let columnsStr = row[1]
            else {
                return nil
            }

            let columns = columnsStr.components(separatedBy: ", ")
            let isUnique = row[2] == "t"
            let isPrimary = row[3] == "t"
            let indexType = row[4] ?? "btree"

            return IndexInfo(
                name: name,
                columns: columns,
                isUnique: isUnique,
                isPrimary: isPrimary,
                type: indexType
            )
        }
    }

    func fetchForeignKeys(table: String) async throws -> [ForeignKeyInfo] {
        let safeTable = SQLEscaping.escapeStringLiteral(table, databaseType: .cockroachdb)
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
            WHERE tc.table_name = '\(safeTable)'
                AND tc.constraint_type = 'FOREIGN KEY'
            ORDER BY tc.constraint_name
            """

        let result = try await execute(query: query)

        return result.rows.compactMap { row in
            guard row.count >= 6,
                  let name = row[0],
                  let column = row[1],
                  let refTable = row[2],
                  let refColumn = row[3]
            else {
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

    func fetchApproximateRowCount(table: String) async throws -> Int? {
        let safeTable = SQLEscaping.escapeStringLiteral(table, databaseType: .cockroachdb)

        // Try CockroachDB-specific table_row_statistics first
        do {
            let query = """
                SELECT estimated_row_count
                FROM crdb_internal.table_row_statistics
                WHERE table_name = '\(safeTable)'
                """
            let result = try await execute(query: query)
            if let firstRow = result.rows.first,
               let value = firstRow[0],
               let count = Int(value) {
                return count >= 0 ? count : nil
            }
        } catch {
            Self.logger.debug("crdb_internal.table_row_statistics not available, falling back to pg_class")
        }

        // Fall back to PostgreSQL's pg_class.reltuples
        let fallbackQuery = """
            SELECT reltuples::BIGINT
            FROM pg_class
            WHERE relname = '\(safeTable)'
              AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = '\(escapedSchema)')
            """
        let fallbackResult = try await execute(query: fallbackQuery)
        guard let firstRow = fallbackResult.rows.first,
              let value = firstRow[0],
              let count = Int(value)
        else {
            return nil
        }
        return count >= 0 ? count : nil
    }

    func fetchTableDDL(table: String) async throws -> String {
        let safeTable = SQLEscaping.escapeStringLiteral(table, databaseType: .cockroachdb)
        let quotedTable = "\"\(table.replacingOccurrences(of: "\"", with: "\"\""))\""
        let quotedSchema = "\"\(currentSchema.replacingOccurrences(of: "\"", with: "\"\""))\""

        // Try SHOW CREATE TABLE first (CockroachDB supports this)
        do {
            let showResult = try await execute(query: "SHOW CREATE TABLE \(quotedSchema).\(quotedTable)")
            if let firstRow = showResult.rows.first {
                // CockroachDB returns (table_name, create_statement) — DDL is in column 1
                let ddl = firstRow.count > 1 ? firstRow[1] : firstRow[0]
                if let ddl, !ddl.isEmpty {
                    return ddl
                }
            }
        } catch {
            Self.logger.debug("SHOW CREATE TABLE not available, falling back to manual reconstruction")
        }

        // Fall back to manual reconstruction from pg_class/pg_attribute
        let columnsQuery = """
            SELECT
                quote_ident(a.attname) || ' ' || format_type(a.atttypid, a.atttypmod) ||
                CASE WHEN a.attnotnull THEN ' NOT NULL' ELSE '' END ||
                CASE WHEN a.atthasdef THEN ' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid) ELSE '' END
            FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
            WHERE c.relname = '\(safeTable)'
              AND n.nspname = '\(escapedSchema)'
              AND a.attnum > 0
              AND NOT a.attisdropped
            ORDER BY a.attnum
            """

        let columnsResult = try await execute(query: columnsQuery)
        let columnDefs = columnsResult.rows.compactMap { $0[0] }

        guard !columnDefs.isEmpty else {
            throw DatabaseError.queryFailed("Failed to fetch DDL for table '\(table)'")
        }

        let ddl = "CREATE TABLE \(quotedSchema).\(quotedTable) (\n  " +
            columnDefs.joined(separator: ",\n  ") +
            "\n);"

        return ddl
    }

    func fetchViewDefinition(view: String) async throws -> String {
        let safeView = SQLEscaping.escapeStringLiteral(view, databaseType: .cockroachdb)
        let query = """
            SELECT 'CREATE OR REPLACE VIEW ' || quote_ident(schemaname) || '.' || quote_ident(viewname) || ' AS ' || E'\\n' || definition AS ddl
            FROM pg_views
            WHERE viewname = '\(safeView)'
              AND schemaname = '\(escapedSchema)'
            """

        let result = try await execute(query: query)

        guard let firstRow = result.rows.first,
              let ddl = firstRow[0]
        else {
            throw DatabaseError.queryFailed("Failed to fetch definition for view '\(view)'")
        }

        return ddl
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

    func fetchTableMetadata(tableName: String) async throws -> TableMetadata {
        let safeTable = SQLEscaping.escapeStringLiteral(tableName, databaseType: .cockroachdb)
        let quotedTable = "\"\(tableName.replacingOccurrences(of: "\"", with: "\"\""))\""
        let quotedSchema = "\"\(currentSchema.replacingOccurrences(of: "\"", with: "\"\""))\""
        let fullName = "\(quotedSchema).\(quotedTable)"

        // Use PostgreSQL-compatible size functions (CockroachDB supports these)
        let query = """
            SELECT
                pg_total_relation_size('\(fullName)') AS total_size,
                pg_table_size('\(fullName)') AS data_size,
                pg_indexes_size('\(fullName)') AS index_size,
                c.reltuples::bigint AS row_count,
                CASE WHEN c.reltuples > 0 THEN pg_table_size('\(fullName)') / GREATEST(c.reltuples, 1) ELSE 0 END AS avg_row_length,
                obj_description(c.oid, 'pg_class') AS comment
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relname = '\(safeTable)'
              AND n.nspname = '\(escapedSchema)'
            """

        let result = try await execute(query: query)

        guard let row = result.rows.first else {
            return TableMetadata(
                tableName: tableName,
                dataSize: nil,
                indexSize: nil,
                totalSize: nil,
                avgRowLength: nil,
                rowCount: nil,
                comment: nil,
                engine: nil,
                collation: nil,
                createTime: nil,
                updateTime: nil
            )
        }

        let totalSize = !row.isEmpty ? Int64(row[0] ?? "0") : nil
        let dataSize = row.count > 1 ? Int64(row[1] ?? "0") : nil
        let indexSize = row.count > 2 ? Int64(row[2] ?? "0") : nil
        let rowCount = row.count > 3 ? Int64(row[3] ?? "0") : nil
        let avgRowLength = row.count > 4 ? Int64(row[4] ?? "0") : nil
        let comment = row.count > 5 ? row[5] : nil

        return TableMetadata(
            tableName: tableName,
            dataSize: dataSize,
            indexSize: indexSize,
            totalSize: totalSize,
            avgRowLength: avgRowLength,
            rowCount: rowCount,
            comment: comment?.isEmpty == true ? nil : comment,
            engine: "CockroachDB",
            collation: nil,
            createTime: nil,
            updateTime: nil
        )
    }

    private func stripLimitOffset(from query: String) -> String {
        var result = query

        if let regex = Self.limitRegex {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        if let regex = Self.offsetRegex {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Database Operations

    func fetchDatabases() async throws -> [String] {
        let result = try await execute(
            query: "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname"
        )
        return result.rows.compactMap { row in row.first.flatMap { $0 } }
    }

    func fetchSchemas() async throws -> [String] {
        let result = try await execute(query: """
            SELECT schema_name FROM information_schema.schemata
            WHERE schema_name NOT LIKE 'pg_%'
              AND schema_name <> 'information_schema'
              AND schema_name <> 'crdb_internal'
            ORDER BY schema_name
            """)
        return result.rows.compactMap { row in row.first.flatMap { $0 } }
    }

    func switchSchema(to schema: String) async throws {
        let escapedName = schema.replacingOccurrences(of: "\"", with: "\"\"")
        _ = try await execute(query: "SET search_path TO \"\(escapedName)\", public")
        currentSchema = schema
    }

    func fetchDatabaseMetadata(_ database: String) async throws -> DatabaseMetadata {
        let escapedDbLiteral = SQLEscaping.escapeStringLiteral(database, databaseType: .cockroachdb)

        let query = """
            SELECT
                (SELECT COUNT(*)
                 FROM information_schema.tables
                 WHERE table_schema = 'public' AND table_catalog = '\(escapedDbLiteral)'),
                pg_database_size('\(escapedDbLiteral)')
        """
        let result = try await execute(query: query)
        let row = result.rows.first
        let tableCount = Int(row?[0] ?? "0") ?? 0
        let sizeBytes = Int64(row?[1] ?? "0") ?? 0

        let systemDatabases = ["system", "defaultdb"]
        let isSystem = systemDatabases.contains(database)

        return DatabaseMetadata(
            id: database,
            name: database,
            tableCount: tableCount,
            sizeBytes: sizeBytes,
            lastAccessed: nil,
            isSystemDatabase: isSystem,
            icon: isSystem ? "gearshape.fill" : "cylinder.fill"
        )
    }

    func fetchAllDatabaseMetadata() async throws -> [DatabaseMetadata] {
        let systemDatabases = ["system", "defaultdb"]

        let query = """
            SELECT d.datname, pg_database_size(d.datname)
            FROM pg_database d
            WHERE d.datistemplate = false
            ORDER BY d.datname
            """
        let result = try await execute(query: query)

        return result.rows.compactMap { row in
            guard let dbName = row[0] else { return nil }
            let sizeBytes = Int64(row[1] ?? "0") ?? 0
            let isSystem = systemDatabases.contains(dbName)

            return DatabaseMetadata(
                id: dbName,
                name: dbName,
                tableCount: nil,
                sizeBytes: sizeBytes,
                lastAccessed: nil,
                isSystemDatabase: isSystem,
                icon: isSystem ? "gearshape.fill" : "cylinder.fill"
            )
        }
    }

    func createDatabase(name: String, charset: String, collation: String?) async throws {
        let escapedName = name.replacingOccurrences(of: "\"", with: "\"\"")

        let validCharsets = ["UTF8"]
        let normalizedCharset = charset.uppercased()
        guard validCharsets.contains(normalizedCharset) else {
            throw DatabaseError.queryFailed("Invalid encoding: \(charset)")
        }

        var query = "CREATE DATABASE \"\(escapedName)\" ENCODING '\(normalizedCharset)'"

        if let collation = collation {
            let allowedCollationChars = CharacterSet(
                charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-"
            )
            let isValidCollation = collation.unicodeScalars.allSatisfy { allowedCollationChars.contains($0) }
            guard isValidCollation else {
                throw DatabaseError.queryFailed("Invalid collation")
            }
            let escapedCollation = collation.replacingOccurrences(of: "'", with: "''")
            query += " LC_COLLATE '\(escapedCollation)'"
        }

        _ = try await execute(query: query)
    }

    // MARK: - Dependent Types & Sequences

    func fetchDependentTypes(forTable table: String) async throws -> [(name: String, labels: [String])] {
        let safeTable = SQLEscaping.escapeStringLiteral(table, databaseType: .cockroachdb)
        let query = """
            SELECT DISTINCT t.typname,
                   array_to_string(array_agg(e.enumlabel ORDER BY e.enumsortorder), ',')
            FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_type t ON t.oid = a.atttypid
            JOIN pg_enum e ON e.enumtypid = t.oid
            WHERE c.relname = '\(safeTable)'
              AND n.nspname = '\(escapedSchema)'
              AND a.attnum > 0
              AND NOT a.attisdropped
            GROUP BY t.typname
            ORDER BY t.typname
            """
        let result = try await execute(query: query)
        return result.rows.compactMap { row in
            guard let typeName = row[0], let labelsStr = row[1] else { return nil }
            let labels = labelsStr.components(separatedBy: ",")
            return (name: typeName, labels: labels)
        }
    }

    func fetchDependentSequences(forTable table: String) async throws -> [(name: String, ddl: String)] {
        let safeTable = SQLEscaping.escapeStringLiteral(table, databaseType: .cockroachdb)
        let query = """
            SELECT s.sequencename,
                   s.start_value,
                   s.min_value,
                   s.max_value,
                   s.increment_by,
                   s.cycle
            FROM pg_attrdef ad
            JOIN pg_class c ON c.oid = ad.adrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_sequences s ON s.schemaname = n.nspname
                 AND pg_get_expr(ad.adbin, ad.adrelid) LIKE '%' || quote_ident(s.sequencename) || '%'
            WHERE c.relname = '\(safeTable)'
              AND n.nspname = '\(escapedSchema)'
              AND pg_get_expr(ad.adbin, ad.adrelid) LIKE '%nextval%'
            """
        let result = try await execute(query: query)
        return result.rows.compactMap { row in
            guard let seqName = row[0] else { return nil }
            let startVal = row[1] ?? "1"
            let minVal = row[2] ?? "1"
            let maxVal = row[3] ?? "9223372036854775807"
            let incrementBy = row[4] ?? "1"
            let cycle = row[5] == "t" ? " CYCLE" : ""
            let quotedSeqName = "\"\(seqName.replacingOccurrences(of: "\"", with: "\"\""))\""
            let ddl = "CREATE SEQUENCE \(quotedSeqName) INCREMENT BY \(incrementBy)"
                + " MINVALUE \(minVal) MAXVALUE \(maxVal)"
                + " START WITH \(startVal)\(cycle);"
            return (name: seqName, ddl: ddl)
        }
    }
}
