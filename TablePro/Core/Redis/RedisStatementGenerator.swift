//
//  RedisStatementGenerator.swift
//  TablePro
//
//  Generates Redis commands from tracked cell changes (edit tracking).
//  Parallel to MongoDBStatementGenerator for MongoDB and SQLStatementGenerator for SQL databases.
//

import Foundation
import os

struct RedisStatementGenerator {
    private static let logger = Logger(subsystem: "com.TablePro", category: "RedisStatementGenerator")

    let namespaceName: String
    let columns: [String]

    /// Index of the "Key" column (used as primary identifier, like MongoDB's "_id")
    var keyColumnIndex: Int? {
        columns.firstIndex(of: "Key")
    }

    /// Index of the "Value" column
    private var valueColumnIndex: Int? {
        columns.firstIndex(of: "Value")
    }

    /// Index of the "TTL" column
    private var ttlColumnIndex: Int? {
        columns.firstIndex(of: "TTL")
    }

    // MARK: - Public API

    /// Generate Redis commands from changes
    func generateStatements(
        from changes: [RowChange],
        insertedRowData: [Int: [String?]],
        deletedRowIndices: Set<Int>,
        insertedRowIndices: Set<Int>
    ) -> [ParameterizedStatement] {
        var statements: [ParameterizedStatement] = []
        var deleteKeys: [String] = []

        for change in changes {
            switch change.type {
            case .insert:
                guard insertedRowIndices.contains(change.rowIndex) else { continue }
                statements += generateInsert(for: change, insertedRowData: insertedRowData)

            case .update:
                statements += generateUpdate(for: change)

            case .delete:
                guard deletedRowIndices.contains(change.rowIndex) else { continue }
                if let key = extractKey(from: change) {
                    deleteKeys.append(key)
                }
            }
        }

        // Batch deletes into a single DEL command
        if !deleteKeys.isEmpty {
            let keyList = deleteKeys.map { escapeArgument($0) }.joined(separator: " ")
            let cmd = "DEL \(keyList)"
            statements.append(ParameterizedStatement(sql: cmd, parameters: []))
        }

        return statements
    }

    // MARK: - INSERT

    private func generateInsert(
        for change: RowChange,
        insertedRowData: [Int: [String?]]
    ) -> [ParameterizedStatement] {
        var statements: [ParameterizedStatement] = []

        var key: String?
        var value: String?
        var ttl: Int?

        if let values = insertedRowData[change.rowIndex] {
            if let ki = keyColumnIndex, ki < values.count {
                key = values[ki]
            }
            if let vi = valueColumnIndex, vi < values.count {
                value = values[vi]
            }
            if let ti = ttlColumnIndex, ti < values.count, let ttlStr = values[ti] {
                ttl = Int(ttlStr)
            }
        } else {
            for cellChange in change.cellChanges {
                switch cellChange.columnName {
                case "Key": key = cellChange.newValue
                case "Value": value = cellChange.newValue
                case "TTL":
                    if let ttlStr = cellChange.newValue { ttl = Int(ttlStr) }
                default: break
                }
            }
        }

        guard let k = key, !k.isEmpty else {
            Self.logger.warning("Skipping INSERT for namespace '\(self.namespaceName)' - no key")
            return []
        }

        let v = value ?? ""
        let cmd = "SET \(escapeArgument(k)) \(escapeArgument(v))"
        statements.append(ParameterizedStatement(sql: cmd, parameters: []))

        if let ttlSeconds = ttl, ttlSeconds > 0 {
            let expireCmd = "EXPIRE \(escapeArgument(k)) \(ttlSeconds)"
            statements.append(ParameterizedStatement(sql: expireCmd, parameters: []))
        }

        return statements
    }

    // MARK: - UPDATE

    private func generateUpdate(for change: RowChange) -> [ParameterizedStatement] {
        guard !change.cellChanges.isEmpty else { return [] }

        guard let key = extractKey(from: change) else {
            Self.logger.warning("Skipping UPDATE for namespace '\(self.namespaceName)' - no key value")
            return []
        }

        var statements: [ParameterizedStatement] = []

        // Check for key rename
        if let keyChange = change.cellChanges.first(where: { $0.columnName == "Key" }),
           let newKey = keyChange.newValue, newKey != key {
            let renameCmd = "RENAME \(escapeArgument(key)) \(escapeArgument(newKey))"
            statements.append(ParameterizedStatement(sql: renameCmd, parameters: []))
        }

        let effectiveKey: String = {
            if let keyChange = change.cellChanges.first(where: { $0.columnName == "Key" }),
               let newKey = keyChange.newValue {
                return newKey
            }
            return key
        }()

        for cellChange in change.cellChanges {
            switch cellChange.columnName {
            case "Key":
                continue // Already handled above
            case "Value":
                if let newValue = cellChange.newValue {
                    let cmd = "SET \(escapeArgument(effectiveKey)) \(escapeArgument(newValue))"
                    statements.append(ParameterizedStatement(sql: cmd, parameters: []))
                }
            case "TTL":
                if let ttlStr = cellChange.newValue, let ttlSeconds = Int(ttlStr), ttlSeconds > 0 {
                    let cmd = "EXPIRE \(escapeArgument(effectiveKey)) \(ttlSeconds)"
                    statements.append(ParameterizedStatement(sql: cmd, parameters: []))
                } else if cellChange.newValue == nil || cellChange.newValue == "-1" {
                    let cmd = "PERSIST \(escapeArgument(effectiveKey))"
                    statements.append(ParameterizedStatement(sql: cmd, parameters: []))
                }
            default:
                break
            }
        }

        return statements
    }

    // MARK: - Helpers

    /// Extract the key value from a RowChange's original row
    private func extractKey(from change: RowChange) -> String? {
        guard let keyIndex = keyColumnIndex,
              let originalRow = change.originalRow,
              keyIndex < originalRow.count else {
            return nil
        }
        return originalRow[keyIndex]
    }

    /// Escape a Redis argument for safe embedding in a command string.
    /// Wraps in double quotes if the value contains whitespace or special characters.
    private func escapeArgument(_ value: String) -> String {
        let needsQuoting = value.isEmpty || value.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "'" })
        if needsQuoting {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
