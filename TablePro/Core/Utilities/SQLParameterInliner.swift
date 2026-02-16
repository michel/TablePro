//
//  SQLParameterInliner.swift
//  TablePro
//
//  Utility for inlining parameter values into parameterized SQL strings.
//  Used for display/preview purposes only — actual execution uses prepared statements.
//

import Foundation

struct SQLParameterInliner {

    // MARK: - Public API

    /// Inlines parameter values into a parameterized SQL string for display purposes.
    ///
    /// - Parameters:
    ///   - statement: The parameterized statement containing SQL with placeholders and bound values.
    ///   - databaseType: The database type, which determines placeholder style (`?` vs `$N`).
    /// - Returns: A SQL string with placeholders replaced by formatted literal values.
    static func inline(_ statement: ParameterizedStatement, databaseType: DatabaseType) -> String {
        switch databaseType {
        case .postgresql:
            return inlineDollarPlaceholders(statement.sql, parameters: statement.parameters)
        case .mysql, .mariadb, .sqlite:
            return inlineQuestionMarkPlaceholders(statement.sql, parameters: statement.parameters)
        }
    }

    // MARK: - Private Helpers

    /// Replaces `?` placeholders sequentially with formatted parameter values.
    /// Skips `?` characters inside single-quoted SQL string literals.
    private static func inlineQuestionMarkPlaceholders(_ sql: String, parameters: [Any?]) -> String {
        var result = ""
        var paramIndex = 0
        var inString = false
        var previousWasQuote = false
        var iterator = sql.makeIterator()

        while let char = iterator.next() {
            if char == "'" {
                if inString {
                    if previousWasQuote {
                        // This is the second quote of an escaped '' pair — still inside string
                        previousWasQuote = false
                    } else {
                        // Could be end of string or start of escaped ''
                        previousWasQuote = true
                    }
                } else {
                    // Start of string literal
                    inString = true
                    previousWasQuote = false
                }
                result.append(char)
            } else {
                if previousWasQuote {
                    // Previous quote was the closing quote (not an escape)
                    inString = false
                    previousWasQuote = false
                }
                if char == "?" && !inString && paramIndex < parameters.count {
                    result += formatValue(parameters[paramIndex])
                    paramIndex += 1
                } else {
                    result.append(char)
                }
            }
        }

        return result
    }

    /// Replaces `$1`, `$2`, ... placeholders with formatted parameter values.
    /// Processes from highest index to lowest to avoid `$1` matching inside `$10`.
    private static func inlineDollarPlaceholders(_ sql: String, parameters: [Any?]) -> String {
        var result = sql

        // Replace from highest index to lowest so $10 is replaced before $1
        for index in stride(from: parameters.count, through: 1, by: -1) {
            let placeholder = "$\(index)"
            let value = formatValue(parameters[index - 1])
            result = result.replacingOccurrences(of: placeholder, with: value)
        }

        return result
    }

    /// Formats a parameter value as a SQL literal string.
    private static func formatValue(_ value: Any?) -> String {
        guard let value else {
            return "NULL"
        }

        switch value {
        case let boolVal as Bool:
            return boolVal ? "TRUE" : "FALSE"
        case let intVal as Int:
            return String(intVal)
        case let int8Val as Int8:
            return String(int8Val)
        case let int16Val as Int16:
            return String(int16Val)
        case let int32Val as Int32:
            return String(int32Val)
        case let int64Val as Int64:
            return String(int64Val)
        case let uintVal as UInt:
            return String(uintVal)
        case let uint8Val as UInt8:
            return String(uint8Val)
        case let uint16Val as UInt16:
            return String(uint16Val)
        case let uint32Val as UInt32:
            return String(uint32Val)
        case let uint64Val as UInt64:
            return String(uint64Val)
        case let floatVal as Float:
            return String(floatVal)
        case let doubleVal as Double:
            return String(doubleVal)
        case let stringVal as String:
            return "'\(escapeString(stringVal))'"
        default:
            return "'\(escapeString(String(describing: value)))'"
        }
    }

    /// Escapes single quotes by doubling them for SQL string literals.
    private static func escapeString(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
