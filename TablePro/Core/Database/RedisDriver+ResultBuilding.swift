//
//  RedisDriver+ResultBuilding.swift
//  TablePro
//
//  Result building helpers for RedisDriver.
//  Converts raw Redis responses into QueryResult format for UI display.
//

import Foundation

// MARK: - Key Browse Results

extension RedisDriver {
    /// Build a key browse result with Key, Type, TTL, and Value columns
    func buildKeyBrowseResult(
        keys: [String],
        connection conn: RedisConnection,
        startTime: Date
    ) async throws -> QueryResult {
        guard !keys.isEmpty else {
            return buildEmptyKeyResult(startTime: startTime)
        }

        var rows: [[String?]] = []

        for key in keys {
            let typeResult = try await conn.executeCommand(["TYPE", key])
            let typeName = (typeResult.stringValue ?? "unknown").uppercased()

            let ttlResult = try await conn.executeCommand(["TTL", key])
            let ttl = ttlResult.intValue ?? -1
            let ttlStr = String(ttl)

            let value = try await fetchValuePreview(key: key, type: typeName, connection: conn)

            rows.append([key, typeName, ttlStr, value])
        }

        return QueryResult(
            columns: ["Key", "Type", "TTL", "Value"],
            columnTypes: [
                .text(rawType: "String"),
                .enumType(rawType: "RedisType", values: ["STRING", "SET", "ZSET", "LIST", "HASH", "STREAM"]),
                .integer(rawType: "RedisInt"),
                .text(rawType: "RedisRaw"),
            ],
            rows: rows,
            rowsAffected: 0,
            executionTime: Date().timeIntervalSince(startTime),
            error: nil
        )
    }

    /// Fetch the value for a key based on its type, serialized as a raw string.
    /// Matches TablePlus behavior: hashes as JSON objects, lists/sets as JSON arrays.
    func fetchValuePreview(key: String, type: String, connection conn: RedisConnection) async throws -> String? {
        switch type.lowercased() {
        case "string":
            let result = try await conn.executeCommand(["GET", key])
            return result.stringValue

        case "hash":
            let result = try await conn.executeCommand(["HGETALL", key])
            guard let array = result.stringArrayValue, !array.isEmpty else { return "{}" }
            var pairs: [String] = []
            var i = 0
            while i + 1 < array.count {
                pairs.append("\"\(escapeJsonString(array[i]))\":\"\(escapeJsonString(array[i + 1]))\"")
                i += 2
            }
            return "{\(pairs.joined(separator: ","))}"

        case "list":
            let result = try await conn.executeCommand(["LRANGE", key, "0", "-1"])
            guard let items = result.stringArrayValue else { return "[]" }
            let quoted = items.map { "\"\(escapeJsonString($0))\"" }
            return "[\(quoted.joined(separator: ", "))]"

        case "set":
            let result = try await conn.executeCommand(["SMEMBERS", key])
            guard let members = result.stringArrayValue else { return "[]" }
            let quoted = members.map { "\"\(escapeJsonString($0))\"" }
            return "[\(quoted.joined(separator: ", "))]"

        case "zset":
            let result = try await conn.executeCommand(["ZRANGE", key, "0", "-1"])
            guard let members = result.stringArrayValue else { return "[]" }
            let quoted = members.map { "\"\(escapeJsonString($0))\"" }
            return "[\(quoted.joined(separator: ", "))]"

        case "stream":
            let lenResult = try await conn.executeCommand(["XLEN", key])
            let len = lenResult.intValue ?? 0
            return "(\(len) entries)"

        default:
            return nil
        }
    }

    /// Escape special characters for JSON string values
    private func escapeJsonString(_ str: String) -> String {
        var result = ""
        for char in str {
            switch char {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default: result.append(char)
            }
        }
        return result
    }

    func buildEmptyKeyResult(startTime: Date) -> QueryResult {
        QueryResult(
            columns: ["Key", "Type", "TTL", "Value"],
            columnTypes: [
                .text(rawType: "String"),
                .enumType(rawType: "RedisType", values: ["STRING", "SET", "ZSET", "LIST", "HASH", "STREAM"]),
                .integer(rawType: "RedisInt"),
                .text(rawType: "RedisRaw"),
            ],
            rows: [],
            rowsAffected: 0,
            executionTime: Date().timeIntervalSince(startTime),
            error: nil
        )
    }
}

// MARK: - Status & Simple Results

extension RedisDriver {
    func buildStatusResult(_ message: String, startTime: Date) -> QueryResult {
        QueryResult(
            columns: ["status"],
            columnTypes: [.text(rawType: "String")],
            rows: [[message]],
            rowsAffected: 0,
            executionTime: Date().timeIntervalSince(startTime),
            error: nil
        )
    }

    /// Build a generic result from any Redis response
    func buildGenericResult(_ result: RedisReply, startTime: Date) -> QueryResult {
        switch result {
        case .string(let s), .status(let s):
            return QueryResult(
                columns: ["result"],
                columnTypes: [.text(rawType: "String")],
                rows: [[s]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .integer(let i):
            return QueryResult(
                columns: ["result"],
                columnTypes: [.integer(rawType: "Int64")],
                rows: [[String(i)]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .data(let d):
            let str = String(data: d, encoding: .utf8) ?? d.base64EncodedString()
            return QueryResult(
                columns: ["result"],
                columnTypes: [.text(rawType: "String")],
                rows: [[str]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .array(let items):
            let rows = items.map { [redisReplyToString($0)] as [String?] }
            return QueryResult(
                columns: ["result"],
                columnTypes: [.text(rawType: "String")],
                rows: rows,
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )

        case .error(let e):
            return QueryResult(
                columns: ["result"],
                columnTypes: [.text(rawType: "String")],
                rows: [[e]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: .queryFailed(e)
            )

        case .null:
            return QueryResult(
                columns: ["result"],
                columnTypes: [.text(rawType: "String")],
                rows: [["(nil)"]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )
        }
    }

    private func redisReplyToString(_ reply: RedisReply) -> String {
        switch reply {
        case .string(let s), .status(let s), .error(let s): return s
        case .integer(let i): return String(i)
        case .data(let d): return String(data: d, encoding: .utf8) ?? d.base64EncodedString()
        case .array(let items): return "[\(items.map { redisReplyToString($0) }.joined(separator: ", "))]"
        case .null: return "(nil)"
        }
    }
}

// MARK: - Data Type Results

extension RedisDriver {
    /// Build result from HGETALL response (alternating field/value array)
    func buildHashResult(_ result: RedisReply, startTime: Date) -> QueryResult {
        guard let array = result.stringArrayValue, !array.isEmpty else {
            return QueryResult(
                columns: ["Field", "Value"],
                columnTypes: [.text(rawType: "String"), .text(rawType: "String")],
                rows: [],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )
        }

        var rows: [[String?]] = []
        var i = 0
        while i + 1 < array.count {
            rows.append([array[i], array[i + 1]])
            i += 2
        }

        return QueryResult(
            columns: ["Field", "Value"],
            columnTypes: [.text(rawType: "String"), .text(rawType: "String")],
            rows: rows,
            rowsAffected: 0,
            executionTime: Date().timeIntervalSince(startTime),
            error: nil
        )
    }

    /// Build result from list commands (array of values)
    func buildListResult(_ result: RedisReply, startTime: Date) -> QueryResult {
        guard let array = result.stringArrayValue else {
            return QueryResult(
                columns: ["Index", "Value"],
                columnTypes: [.integer(rawType: "Int64"), .text(rawType: "String")],
                rows: [],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )
        }

        let rows = array.enumerated().map { index, value -> [String?] in
            [String(index), value]
        }

        return QueryResult(
            columns: ["Index", "Value"],
            columnTypes: [.integer(rawType: "Int64"), .text(rawType: "String")],
            rows: rows,
            rowsAffected: 0,
            executionTime: Date().timeIntervalSince(startTime),
            error: nil
        )
    }

    /// Build result from SMEMBERS (array of members)
    func buildSetResult(_ result: RedisReply, startTime: Date) -> QueryResult {
        guard let array = result.stringArrayValue else {
            return QueryResult(
                columns: ["Member"],
                columnTypes: [.text(rawType: "String")],
                rows: [],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )
        }

        let rows = array.map { [$0] as [String?] }

        return QueryResult(
            columns: ["Member"],
            columnTypes: [.text(rawType: "String")],
            rows: rows,
            rowsAffected: 0,
            executionTime: Date().timeIntervalSince(startTime),
            error: nil
        )
    }

    /// Build result from ZRANGE (with or without scores)
    func buildSortedSetResult(_ result: RedisReply, withScores: Bool, startTime: Date) -> QueryResult {
        guard let array = result.stringArrayValue else {
            let columns = withScores ? ["Member", "Score"] : ["Member"]
            let types: [ColumnType] = withScores
                ? [.text(rawType: "String"), .decimal(rawType: "Double")]
                : [.text(rawType: "String")]
            return QueryResult(
                columns: columns,
                columnTypes: types,
                rows: [],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )
        }

        if withScores {
            var rows: [[String?]] = []
            var i = 0
            while i + 1 < array.count {
                rows.append([array[i], array[i + 1]])
                i += 2
            }
            return QueryResult(
                columns: ["Member", "Score"],
                columnTypes: [.text(rawType: "String"), .decimal(rawType: "Double")],
                rows: rows,
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )
        } else {
            let rows = array.map { [$0] as [String?] }
            return QueryResult(
                columns: ["Member"],
                columnTypes: [.text(rawType: "String")],
                rows: rows,
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )
        }
    }

    /// Build result from XRANGE (stream entries)
    func buildStreamResult(_ result: RedisReply, startTime: Date) -> QueryResult {
        guard let entries = result.arrayValue else {
            return QueryResult(
                columns: ["ID", "Fields"],
                columnTypes: [.text(rawType: "String"), .text(rawType: "String")],
                rows: [],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )
        }

        var rows: [[String?]] = []
        for entry in entries {
            guard let entryParts = entry.arrayValue, entryParts.count >= 2,
                  let entryId = entryParts[0].stringValue,
                  let fields = entryParts[1].stringArrayValue else {
                continue
            }

            var fieldPairs: [String] = []
            var i = 0
            while i + 1 < fields.count {
                fieldPairs.append("\(fields[i])=\(fields[i + 1])")
                i += 2
            }
            rows.append([entryId, fieldPairs.joined(separator: ", ")])
        }

        return QueryResult(
            columns: ["ID", "Fields"],
            columnTypes: [.text(rawType: "String"), .text(rawType: "String")],
            rows: rows,
            rowsAffected: 0,
            executionTime: Date().timeIntervalSince(startTime),
            error: nil
        )
    }

    /// Build result from CONFIG GET (alternating param/value array)
    func buildConfigResult(_ result: RedisReply, startTime: Date) -> QueryResult {
        guard let array = result.stringArrayValue, !array.isEmpty else {
            return QueryResult(
                columns: ["Parameter", "Value"],
                columnTypes: [.text(rawType: "String"), .text(rawType: "String")],
                rows: [],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime),
                error: nil
            )
        }

        var rows: [[String?]] = []
        var i = 0
        while i + 1 < array.count {
            rows.append([array[i], array[i + 1]])
            i += 2
        }

        return QueryResult(
            columns: ["Parameter", "Value"],
            columnTypes: [.text(rawType: "String"), .text(rawType: "String")],
            rows: rows,
            rowsAffected: 0,
            executionTime: Date().timeIntervalSince(startTime),
            error: nil
        )
    }
}
