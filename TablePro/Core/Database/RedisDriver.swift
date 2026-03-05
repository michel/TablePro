//
//  RedisDriver.swift
//  TablePro
//
//  Redis database driver implementing the DatabaseDriver protocol.
//  Parses Redis CLI syntax and dispatches to RedisConnection for execution.
//

import Foundation
import OSLog

/// Redis database driver implementing the DatabaseDriver protocol.
/// Parses Redis CLI commands (GET, SET, SCAN, etc.)
/// and dispatches to RedisConnection for execution.
final class RedisDriver: DatabaseDriver {
    private(set) var connection: DatabaseConnection
    private(set) var status: ConnectionStatus = .disconnected

    private var redisConnection: RedisConnection?

    private static let logger = Logger(subsystem: "com.TablePro", category: "RedisDriver")

    /// Maximum number of keys to scan when building namespace list
    private static let maxScanKeys = 100_000

    init(connection: DatabaseConnection) {
        self.connection = connection
    }

    func switchDatabase(to database: String) {
        connection.database = database
    }

    // MARK: - Server Version

    var serverVersion: String? {
        redisConnection?.serverVersion()
    }

    // MARK: - Connection Management

    func connect() async throws {
        status = .connecting

        let password = ConnectionStorage.shared.loadPassword(for: connection.id)

        let conn = RedisConnection(
            host: connection.host,
            port: connection.port,
            password: password,
            database: connection.redisDatabase ?? Int(connection.database) ?? 0,
            sslConfig: connection.sslConfig
        )

        do {
            try await conn.connect()
            redisConnection = conn
            status = .connected
        } catch {
            status = .error(error.localizedDescription)
            throw DatabaseError.connectionFailed(error.localizedDescription)
        }
    }

    func disconnect() {
        redisConnection?.disconnect()
        redisConnection = nil
        status = .disconnected
    }

    func selectDatabase(_ index: Int) async throws {
        guard let conn = redisConnection else {
            throw DatabaseError.notConnected
        }
        try await conn.selectDatabase(index)
        connection.database = String(index)
    }

    func testConnection() async throws -> Bool {
        try await connect()
        let isConnected = status == .connected
        disconnect()
        return isConnected
    }

    // MARK: - Configuration

    func applyQueryTimeout(_ seconds: Int) async throws {
        // Redis does not support session-level query timeouts
    }

    // MARK: - Query Execution

    func execute(query: String) async throws -> QueryResult {
        let startTime = Date()

        guard let conn = redisConnection else {
            throw DatabaseError.notConnected
        }

        var trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle bare "SELECT" (no index) — default to SELECT 0
        if trimmed.caseInsensitiveCompare("SELECT") == .orderedSame {
            trimmed = "SELECT 0"
        }

        // Health monitor sends "SELECT 1" as a ping — intercept and remap to PING.
        // In Redis, "SELECT 1" is a valid database-switch command, so we only intercept
        // the exact "SELECT 1" string. Database switching from the UI goes through
        // RedisConnection.selectDatabase() directly, not through execute(query:).
        if trimmed.lowercased() == "select 1" {
            _ = try await conn.executeCommand(["PING"])
            return QueryResult(
                columns: ["ok"],
                columnTypes: [.integer(rawType: "Int32")],
                rows: [["1"]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )
        }

        let operation: RedisOperation
        do {
            operation = try RedisCommandParser.parse(trimmed)
        } catch {
            throw DatabaseError.queryFailed(error.localizedDescription)
        }

        return try await executeOperation(operation, connection: conn, startTime: startTime)
    }

    func executeParameterized(query: String, parameters: [Any?]) async throws -> QueryResult {
        // Redis commands are self-contained; parameters are embedded in the command
        try await execute(query: query)
    }

    // MARK: - Query Cancellation

    func cancelQuery() throws {
        redisConnection?.cancelCurrentQuery()
    }

    // MARK: - Paginated Query Support

    func fetchRowCount(query: String) async throws -> Int {
        guard let conn = redisConnection else {
            throw DatabaseError.notConnected
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let operation = try RedisCommandParser.parse(trimmed)

            switch operation {
            case .scan(_, let pattern, _):
                // Count keys matching the pattern
                let keys = try await scanAllKeys(connection: conn, pattern: pattern, maxKeys: Self.maxScanKeys)
                return keys.count

            case .keys(let pattern):
                let result = try await conn.executeCommand(["KEYS", pattern])
                if let array = result .stringArrayValue {
                    return array.count
                }
                return 0

            case .dbsize:
                let result = try await conn.executeCommand(["DBSIZE"])
                if let count = result .intValue {
                    return count
                }
                return 0

            default:
                return 0
            }
        } catch {
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    func fetchRows(query: String, offset: Int, limit: Int) async throws -> QueryResult {
        let startTime = Date()

        guard let conn = redisConnection else {
            throw DatabaseError.notConnected
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let operation = try RedisCommandParser.parse(trimmed)

            switch operation {
            case .scan(_, let pattern, _):
                // Scan all matching keys, then paginate
                let allKeys = try await scanAllKeys(connection: conn, pattern: pattern, maxKeys: Self.maxScanKeys)
                let pageEnd = min(offset + limit, allKeys.count)
                guard offset < allKeys.count else {
                    return buildEmptyKeyResult(startTime: startTime)
                }
                let pageKeys = Array(allKeys[offset..<pageEnd])
                return try await buildKeyBrowseResult(keys: pageKeys, connection: conn, startTime: startTime)

            default:
                return try await executeOperation(operation, connection: conn, startTime: startTime)
            }
        } catch let error as DatabaseError {
            throw error
        } catch {
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    // MARK: - Schema Operations (key-based)

    func fetchTables() async throws -> [TableInfo] {
        guard let conn = redisConnection else {
            throw DatabaseError.notConnected
        }

        // Use INFO keyspace to enumerate databases without changing the active database.
        // This avoids race conditions with concurrent queries on the same connection.
        // Output format: "# Keyspace\r\ndb0:keys=11,expires=0,avg_ttl=0\r\ndb3:keys=5,..."
        let result = try await conn.executeCommand(["INFO", "keyspace"])
        guard let info = result.stringValue else { return [] }

        var databases: [TableInfo] = []
        for line in info.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("db"),
                  let colonIndex = trimmed.firstIndex(of: ":") else { continue }

            let dbName = String(trimmed[trimmed.startIndex..<colonIndex])
            let statsStr = String(trimmed[trimmed.index(after: colonIndex)...])

            var keyCount = 0
            for stat in statsStr.components(separatedBy: ",") {
                let parts = stat.components(separatedBy: "=")
                if parts.count == 2, parts[0] == "keys", let count = Int(parts[1]) {
                    keyCount = count
                    break
                }
            }

            if keyCount > 0 {
                databases.append(TableInfo(name: dbName, type: .table, rowCount: keyCount))
            }
        }

        return databases
    }

    func fetchColumns(table: String) async throws -> [ColumnInfo] {
        // For a namespace view, return fixed columns: Key, Type, TTL, Value
        [
            ColumnInfo(
                name: "Key",
                dataType: "String",
                isNullable: false,
                isPrimaryKey: true,
                defaultValue: nil,
                extra: nil,
                charset: nil,
                collation: nil,
                comment: nil
            ),
            ColumnInfo(
                name: "Type",
                dataType: "String",
                isNullable: false,
                isPrimaryKey: false,
                defaultValue: nil,
                extra: nil,
                charset: nil,
                collation: nil,
                comment: nil
            ),
            ColumnInfo(
                name: "TTL",
                dataType: "Int64",
                isNullable: true,
                isPrimaryKey: false,
                defaultValue: nil,
                extra: nil,
                charset: nil,
                collation: nil,
                comment: nil
            ),
            ColumnInfo(
                name: "Value",
                dataType: "String",
                isNullable: true,
                isPrimaryKey: false,
                defaultValue: nil,
                extra: nil,
                charset: nil,
                collation: nil,
                comment: nil
            ),
        ]
    }

    func fetchAllColumns() async throws -> [String: [ColumnInfo]] {
        let tables = try await fetchTables()
        let columns = try await fetchColumns(table: "")
        var result: [String: [ColumnInfo]] = [:]
        for table in tables {
            result[table.name] = columns
        }
        return result
    }

    func fetchIndexes(table: String) async throws -> [IndexInfo] {
        // Redis does not have indexes in the traditional sense
        []
    }

    func fetchForeignKeys(table: String) async throws -> [ForeignKeyInfo] {
        // Redis does not have foreign keys
        []
    }

    func fetchApproximateRowCount(table: String) async throws -> Int? {
        guard let conn = redisConnection else {
            throw DatabaseError.notConnected
        }
        // Table is "db0", "db3", etc. — DBSIZE returns count for current database
        let result = try await conn.executeCommand(["DBSIZE"])
        return result.intValue
    }

    func fetchTableDDL(table: String) async throws -> String {
        guard let conn = redisConnection else {
            throw DatabaseError.notConnected
        }

        let result = try await conn.executeCommand(["DBSIZE"])
        let keyCount = result.intValue ?? 0

        var lines: [String] = [
            "// Redis database: \(table)",
            "// Keys: \(keyCount)",
            "// Use SCAN 0 MATCH * COUNT 200 to browse keys"
        ]

        // Sample a few keys to show type distribution
        let keys = try await scanAllKeys(connection: conn, pattern: nil, maxKeys: 100)
        if !keys.isEmpty {
            let typeCommands = keys.map { ["TYPE", $0] }
            let replies = try await conn.executePipeline(typeCommands)

            var typeCounts: [String: Int] = [:]
            for reply in replies {
                if let typeName = reply.stringValue {
                    typeCounts[typeName, default: 0] += 1
                }
            }

            if !typeCounts.isEmpty {
                lines.append("//")
                lines.append("// Type distribution (sampled \(keys.count) keys):")
                for (type, count) in typeCounts.sorted(by: { $0.key < $1.key }) {
                    lines.append("//   \(type): \(count)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    func fetchViewDefinition(view: String) async throws -> String {
        throw DatabaseError.unsupportedOperation
    }

    func fetchTableMetadata(tableName: String) async throws -> TableMetadata {
        guard let conn = redisConnection else {
            throw DatabaseError.notConnected
        }

        let result = try await conn.executeCommand(["DBSIZE"])
        let keyCount = result.intValue ?? 0

        return TableMetadata(
            tableName: tableName,
            dataSize: nil,
            indexSize: nil,
            totalSize: nil,
            avgRowLength: nil,
            rowCount: Int64(keyCount),
            comment: nil,
            engine: "Redis",
            collation: nil,
            createTime: nil,
            updateTime: nil
        )
    }

    func fetchDatabases() async throws -> [String] {
        []
    }

    func fetchSchemas() async throws -> [String] {
        // Redis does not have schemas
        []
    }

    func fetchDatabaseMetadata(_ database: String) async throws -> DatabaseMetadata {
        guard let conn = redisConnection else {
            throw DatabaseError.notConnected
        }

        // Parse key count from INFO keyspace without switching databases.
        // This avoids race conditions with concurrent queries on the shared connection.
        let dbName = database.hasPrefix("db") ? database : "db\(database)"

        do {
            let infoResult = try await conn.executeCommand(["INFO", "keyspace"])
            guard let infoStr = infoResult.stringValue else {
                return DatabaseMetadata(
                    id: database,
                    name: dbName,
                    tableCount: 0,
                    sizeBytes: nil,
                    lastAccessed: nil,
                    isSystemDatabase: false,
                    icon: "cylinder.fill"
                )
            }

            var keyCount = 0
            for line in infoStr.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("\(dbName):") {
                    let statsStr = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: dbName.count + 1)...])
                    for stat in statsStr.components(separatedBy: ",") {
                        let parts = stat.components(separatedBy: "=")
                        if parts.count == 2, parts[0] == "keys", let count = Int(parts[1]) {
                            keyCount = count
                            break
                        }
                    }
                    break
                }
            }

            return DatabaseMetadata(
                id: database,
                name: dbName,
                tableCount: keyCount,
                sizeBytes: nil,
                lastAccessed: nil,
                isSystemDatabase: false,
                icon: "cylinder.fill"
            )
        } catch {
            Self.logger.debug("Failed to get metadata for database \(database): \(error.localizedDescription)")
            return DatabaseMetadata.minimal(name: dbName)
        }
    }

    func createDatabase(name: String, charset: String, collation: String?) async throws {
        // Redis databases are pre-allocated (0-15 by default), cannot create new ones
        throw DatabaseError.unsupportedOperation
    }

    // MARK: - Transaction Management

    func beginTransaction() async throws {
        guard let conn = redisConnection else {
            throw DatabaseError.notConnected
        }
        _ = try await conn.executeCommand(["MULTI"])
    }

    func commitTransaction() async throws {
        guard let conn = redisConnection else {
            throw DatabaseError.notConnected
        }
        _ = try await conn.executeCommand(["EXEC"])
    }

    func rollbackTransaction() async throws {
        guard let conn = redisConnection else {
            throw DatabaseError.notConnected
        }
        _ = try await conn.executeCommand(["DISCARD"])
    }
}

// MARK: - Operation Dispatch

private extension RedisDriver {
    func executeOperation(
        _ operation: RedisOperation,
        connection conn: RedisConnection,
        startTime: Date
    ) async throws -> QueryResult {
        switch operation {
        case .get, .set, .del, .keys, .scan, .type, .ttl, .pttl, .expire, .persist, .rename, .exists:
            return try await executeKeyOperation(operation, connection: conn, startTime: startTime)

        case .hget, .hset, .hgetall, .hdel:
            return try await executeHashOperation(operation, connection: conn, startTime: startTime)

        case .lrange, .lpush, .rpush, .llen:
            return try await executeListOperation(operation, connection: conn, startTime: startTime)

        case .smembers, .sadd, .srem, .scard:
            return try await executeSetOperation(operation, connection: conn, startTime: startTime)

        case .zrange, .zadd, .zrem, .zcard:
            return try await executeSortedSetOperation(operation, connection: conn, startTime: startTime)

        case .xrange, .xlen:
            return try await executeStreamOperation(operation, connection: conn, startTime: startTime)

        case .ping, .info, .dbsize, .flushdb, .select, .configGet, .configSet, .command, .multi, .exec, .discard:
            return try await executeServerOperation(operation, connection: conn, startTime: startTime)
        }
    }

    // MARK: - Key Operations

    func executeKeyOperation(
        _ operation: RedisOperation,
        connection conn: RedisConnection,
        startTime: Date
    ) async throws -> QueryResult {
        switch operation {
        case .get(let key):
            let result = try await conn.executeCommand(["GET", key])
            let value = result .stringValue
            return QueryResult(
                columns: ["Key", "Value"],
                columnTypes: [.text(rawType: "String"), .text(rawType: "String")],
                rows: [[key, value]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .set(let key, let value, let options):
            var args = ["SET", key, value]
            if let opts = options {
                if let ex = opts.ex { args += ["EX", String(ex)] }
                if let px = opts.px { args += ["PX", String(px)] }
                if opts.nx { args.append("NX") }
                if opts.xx { args.append("XX") }
            }
            _ = try await conn.executeCommand(args)
            return buildStatusResult("OK", startTime: startTime)

        case .del(let keys):
            let args = ["DEL"] + keys
            let result = try await conn.executeCommand(args)
            let deleted = result .intValue ?? 0
            return QueryResult(
                columns: ["deleted"],
                columnTypes: [.integer(rawType: "Int64")],
                rows: [[String(deleted)]],
                rowsAffected: deleted,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .keys(let pattern):
            let result = try await conn.executeCommand(["KEYS", pattern])
            guard let keys = result .stringArrayValue else {
                return buildEmptyKeyResult(startTime: startTime)
            }
            let capped = Array(keys.prefix(DriverRowLimits.defaultMax))
            return try await buildKeyBrowseResult(keys: capped, connection: conn, startTime: startTime)

        case .scan(let cursor, let pattern, let count):
            var args = ["SCAN", String(cursor)]
            if let p = pattern { args += ["MATCH", p] }
            if let c = count { args += ["COUNT", String(c)] }
            let result = try await conn.executeCommand(args)
            return try await handleScanResult(result, connection: conn, startTime: startTime)

        case .type(let key):
            let result = try await conn.executeCommand(["TYPE", key])
            let typeName = result .stringValue ?? "none"
            return QueryResult(
                columns: ["Key", "Type"],
                columnTypes: [.text(rawType: "String"), .text(rawType: "String")],
                rows: [[key, typeName]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .ttl(let key):
            let result = try await conn.executeCommand(["TTL", key])
            let ttl = result .intValue ?? -1
            return QueryResult(
                columns: ["Key", "TTL"],
                columnTypes: [.text(rawType: "String"), .integer(rawType: "Int64")],
                rows: [[key, String(ttl)]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .pttl(let key):
            let result = try await conn.executeCommand(["PTTL", key])
            let pttl = result .intValue ?? -1
            return QueryResult(
                columns: ["Key", "PTTL"],
                columnTypes: [.text(rawType: "String"), .integer(rawType: "Int64")],
                rows: [[key, String(pttl)]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .expire(let key, let seconds):
            let result = try await conn.executeCommand(["EXPIRE", key, String(seconds)])
            let success = (result .intValue ?? 0) == 1
            return buildStatusResult(success ? "OK" : "Key not found", startTime: startTime)

        case .persist(let key):
            let result = try await conn.executeCommand(["PERSIST", key])
            let success = (result .intValue ?? 0) == 1
            return buildStatusResult(success ? "OK" : "Key not found or no TTL", startTime: startTime)

        case .rename(let key, let newKey):
            _ = try await conn.executeCommand(["RENAME", key, newKey])
            return buildStatusResult("OK", startTime: startTime)

        case .exists(let keys):
            let args = ["EXISTS"] + keys
            let result = try await conn.executeCommand(args)
            let count = result .intValue ?? 0
            return QueryResult(
                columns: ["exists"],
                columnTypes: [.integer(rawType: "Int64")],
                rows: [[String(count)]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        default:
            fatalError("Unexpected operation in executeKeyOperation")
        }
    }

    // MARK: - Hash Operations

    func executeHashOperation(
        _ operation: RedisOperation,
        connection conn: RedisConnection,
        startTime: Date
    ) async throws -> QueryResult {
        switch operation {
        case .hget(let key, let field):
            let result = try await conn.executeCommand(["HGET", key, field])
            let value = result .stringValue
            return QueryResult(
                columns: ["Field", "Value"],
                columnTypes: [.text(rawType: "String"), .text(rawType: "String")],
                rows: [[field, value]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .hset(let key, let fieldValues):
            var args = ["HSET", key]
            for (field, value) in fieldValues {
                args += [field, value]
            }
            let result = try await conn.executeCommand(args)
            let added = result .intValue ?? 0
            return QueryResult(
                columns: ["added"],
                columnTypes: [.integer(rawType: "Int64")],
                rows: [[String(added)]],
                rowsAffected: added,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .hgetall(let key):
            let result = try await conn.executeCommand(["HGETALL", key])
            return buildHashResult(result, startTime: startTime)

        case .hdel(let key, let fields):
            let args = ["HDEL", key] + fields
            let result = try await conn.executeCommand(args)
            let removed = result .intValue ?? 0
            return QueryResult(
                columns: ["removed"],
                columnTypes: [.integer(rawType: "Int64")],
                rows: [[String(removed)]],
                rowsAffected: removed,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        default:
            fatalError("Unexpected operation in executeHashOperation")
        }
    }

    // MARK: - List Operations

    func executeListOperation(
        _ operation: RedisOperation,
        connection conn: RedisConnection,
        startTime: Date
    ) async throws -> QueryResult {
        switch operation {
        case .lrange(let key, let start, let stop):
            let result = try await conn.executeCommand(["LRANGE", key, String(start), String(stop)])
            return buildListResult(result, startTime: startTime)

        case .lpush(let key, let values):
            let args = ["LPUSH", key] + values
            let result = try await conn.executeCommand(args)
            let length = result .intValue ?? 0
            return QueryResult(
                columns: ["length"],
                columnTypes: [.integer(rawType: "Int64")],
                rows: [[String(length)]],
                rowsAffected: values.count,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .rpush(let key, let values):
            let args = ["RPUSH", key] + values
            let result = try await conn.executeCommand(args)
            let length = result .intValue ?? 0
            return QueryResult(
                columns: ["length"],
                columnTypes: [.integer(rawType: "Int64")],
                rows: [[String(length)]],
                rowsAffected: values.count,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .llen(let key):
            let result = try await conn.executeCommand(["LLEN", key])
            let length = result .intValue ?? 0
            return QueryResult(
                columns: ["Key", "Length"],
                columnTypes: [.text(rawType: "String"), .integer(rawType: "Int64")],
                rows: [[key, String(length)]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        default:
            fatalError("Unexpected operation in executeListOperation")
        }
    }

    // MARK: - Set Operations

    func executeSetOperation(
        _ operation: RedisOperation,
        connection conn: RedisConnection,
        startTime: Date
    ) async throws -> QueryResult {
        switch operation {
        case .smembers(let key):
            let result = try await conn.executeCommand(["SMEMBERS", key])
            return buildSetResult(result, startTime: startTime)

        case .sadd(let key, let members):
            let args = ["SADD", key] + members
            let result = try await conn.executeCommand(args)
            let added = result .intValue ?? 0
            return QueryResult(
                columns: ["added"],
                columnTypes: [.integer(rawType: "Int64")],
                rows: [[String(added)]],
                rowsAffected: added,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .srem(let key, let members):
            let args = ["SREM", key] + members
            let result = try await conn.executeCommand(args)
            let removed = result .intValue ?? 0
            return QueryResult(
                columns: ["removed"],
                columnTypes: [.integer(rawType: "Int64")],
                rows: [[String(removed)]],
                rowsAffected: removed,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .scard(let key):
            let result = try await conn.executeCommand(["SCARD", key])
            let count = result .intValue ?? 0
            return QueryResult(
                columns: ["Key", "Cardinality"],
                columnTypes: [.text(rawType: "String"), .integer(rawType: "Int64")],
                rows: [[key, String(count)]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        default:
            fatalError("Unexpected operation in executeSetOperation")
        }
    }

    // MARK: - Sorted Set Operations

    func executeSortedSetOperation(
        _ operation: RedisOperation,
        connection conn: RedisConnection,
        startTime: Date
    ) async throws -> QueryResult {
        switch operation {
        case .zrange(let key, let start, let stop, let withScores):
            var args = ["ZRANGE", key, String(start), String(stop)]
            if withScores { args.append("WITHSCORES") }
            let result = try await conn.executeCommand(args)
            return buildSortedSetResult(result, withScores: withScores, startTime: startTime)

        case .zadd(let key, let scoreMembers):
            var args = ["ZADD", key]
            for (score, member) in scoreMembers {
                args += [String(score), member]
            }
            let result = try await conn.executeCommand(args)
            let added = result .intValue ?? 0
            return QueryResult(
                columns: ["added"],
                columnTypes: [.integer(rawType: "Int64")],
                rows: [[String(added)]],
                rowsAffected: added,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .zrem(let key, let members):
            let args = ["ZREM", key] + members
            let result = try await conn.executeCommand(args)
            let removed = result .intValue ?? 0
            return QueryResult(
                columns: ["removed"],
                columnTypes: [.integer(rawType: "Int64")],
                rows: [[String(removed)]],
                rowsAffected: removed,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .zcard(let key):
            let result = try await conn.executeCommand(["ZCARD", key])
            let count = result .intValue ?? 0
            return QueryResult(
                columns: ["Key", "Cardinality"],
                columnTypes: [.text(rawType: "String"), .integer(rawType: "Int64")],
                rows: [[key, String(count)]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        default:
            fatalError("Unexpected operation in executeSortedSetOperation")
        }
    }

    // MARK: - Stream Operations

    func executeStreamOperation(
        _ operation: RedisOperation,
        connection conn: RedisConnection,
        startTime: Date
    ) async throws -> QueryResult {
        switch operation {
        case .xrange(let key, let start, let end, let count):
            var args = ["XRANGE", key, start, end]
            if let c = count { args += ["COUNT", String(c)] }
            let result = try await conn.executeCommand(args)
            return buildStreamResult(result, startTime: startTime)

        case .xlen(let key):
            let result = try await conn.executeCommand(["XLEN", key])
            let length = result .intValue ?? 0
            return QueryResult(
                columns: ["Key", "Length"],
                columnTypes: [.text(rawType: "String"), .integer(rawType: "Int64")],
                rows: [[key, String(length)]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        default:
            fatalError("Unexpected operation in executeStreamOperation")
        }
    }

    // MARK: - Server Operations

    func executeServerOperation(
        _ operation: RedisOperation,
        connection conn: RedisConnection,
        startTime: Date
    ) async throws -> QueryResult {
        switch operation {
        case .ping:
            _ = try await conn.executeCommand(["PING"])
            return QueryResult(
                columns: ["ok"],
                columnTypes: [.integer(rawType: "Int32")],
                rows: [["1"]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .info(let section):
            var args = ["INFO"]
            if let s = section { args.append(s) }
            let result = try await conn.executeCommand(args)
            let infoText = result .stringValue ?? String(describing: result)
            return QueryResult(
                columns: ["info"],
                columnTypes: [.text(rawType: "String")],
                rows: [[infoText]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .dbsize:
            let result = try await conn.executeCommand(["DBSIZE"])
            let count = result .intValue ?? 0
            return QueryResult(
                columns: ["keys"],
                columnTypes: [.integer(rawType: "Int64")],
                rows: [[String(count)]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .flushdb:
            _ = try await conn.executeCommand(["FLUSHDB"])
            return buildStatusResult("OK", startTime: startTime)

        case .select(let database):
            _ = try await conn.executeCommand(["SELECT", String(database)])
            return buildStatusResult("OK", startTime: startTime)

        case .configGet(let parameter):
            let result = try await conn.executeCommand(["CONFIG", "GET", parameter])
            return buildConfigResult(result, startTime: startTime)

        case .configSet(let parameter, let value):
            _ = try await conn.executeCommand(["CONFIG", "SET", parameter, value])
            return buildStatusResult("OK", startTime: startTime)

        case .command(let args):
            let result = try await conn.executeCommand(args)
            return buildGenericResult(result, startTime: startTime)

        case .multi:
            _ = try await conn.executeCommand(["MULTI"])
            return buildStatusResult("OK", startTime: startTime)

        case .exec:
            let result = try await conn.executeCommand(["EXEC"])
            return buildGenericResult(result, startTime: startTime)

        case .discard:
            _ = try await conn.executeCommand(["DISCARD"])
            return buildStatusResult("OK", startTime: startTime)

        default:
            fatalError("Unexpected operation in executeServerOperation")
        }
    }
}

// MARK: - SCAN Helpers

private extension RedisDriver {
    /// Scan all keys matching a pattern using cursor-based iteration.
    /// Caps at maxKeys to prevent OOM on large databases.
    func scanAllKeys(
        connection conn: RedisConnection,
        pattern: String?,
        maxKeys: Int
    ) async throws -> [String] {
        var allKeys: [String] = []
        var cursor = "0"

        repeat {
            var args = ["SCAN", cursor]
            if let p = pattern {
                args += ["MATCH", p]
            }
            args += ["COUNT", "1000"]

            let result = try await conn.executeCommand(args)

            // SCAN returns [cursor_string, [key1, key2, ...]]
            guard case .array(let scanResult) = result,
                  scanResult.count == 2 else {
                break
            }

            // Extract next cursor (hiredis returns it as .string or .status)
            let nextCursor: String
            switch scanResult[0] {
            case .string(let s): nextCursor = s
            case .status(let s): nextCursor = s
            case .data(let d): nextCursor = String(data: d, encoding: .utf8) ?? "0"
            default: nextCursor = "0"
            }
            cursor = nextCursor

            // Extract keys from second element
            if case .array(let keyReplies) = scanResult[1] {
                for reply in keyReplies {
                    switch reply {
                    case .string(let k): allKeys.append(k)
                    case .data(let d):
                        if let k = String(data: d, encoding: .utf8) { allKeys.append(k) }
                    default: break
                    }
                }
            }

            if allKeys.count >= maxKeys {
                allKeys = Array(allKeys.prefix(maxKeys))
                break
            }
        } while cursor != "0"

        return allKeys.sorted()
    }

    /// Process SCAN result into a QueryResult with key details
    func handleScanResult(
        _ result: RedisReply,
        connection conn: RedisConnection,
        startTime: Date
    ) async throws -> QueryResult {
        guard case .array(let scanResult) = result,
              scanResult.count == 2,
              case .array(let keyReplies) = scanResult[1] else {
            return buildEmptyKeyResult(startTime: startTime)
        }

        let keys = keyReplies.compactMap { reply -> String? in
            if case .string(let k) = reply { return k }
            if case .data(let d) = reply { return String(data: d, encoding: .utf8) }
            return nil
        }

        let capped = Array(keys.prefix(DriverRowLimits.defaultMax))
        return try await buildKeyBrowseResult(keys: capped, connection: conn, startTime: startTime)
    }
}

// MARK: - Result Building (see RedisDriver+ResultBuilding.swift)
