//
//  MainContentCoordinator+QueryAnalysis.swift
//  TablePro
//
//  Write-query and dangerous-query detection for MainContentCoordinator.
//

import Foundation

extension MainContentCoordinator {
    // MARK: - Write Query Detection

    /// Write-operation SQL prefixes blocked in read-only mode
    private static let writeQueryPrefixes: [String] = [
        "INSERT ", "UPDATE ", "DELETE ", "REPLACE ",
        "DROP ", "TRUNCATE ", "ALTER ", "CREATE ",
        "RENAME ", "GRANT ", "REVOKE ",
    ]

    /// Check if a SQL statement is a write operation (modifies data or schema)
    func isWriteQuery(_ sql: String) -> Bool {
        let uppercased = sql.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.writeQueryPrefixes.contains { uppercased.hasPrefix($0) }
    }

    // MARK: - Dangerous Query Detection

    /// Pre-compiled regex for detecting WHERE clause in DELETE queries (avoids per-call compilation)
    private static let whereClauseRegex = try? NSRegularExpression(pattern: "\\sWHERE\\s", options: [])

    /// Check if a query is potentially dangerous (DROP, TRUNCATE, DELETE without WHERE)
    func isDangerousQuery(_ sql: String) -> Bool {
        let uppercased = sql.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for DROP
        if uppercased.hasPrefix("DROP ") {
            return true
        }

        // Check for TRUNCATE
        if uppercased.hasPrefix("TRUNCATE ") {
            return true
        }

        // Check for DELETE without WHERE clause
        if uppercased.hasPrefix("DELETE ") {
            // Check if there's a WHERE clause (handle any whitespace: space, tab, newline)
            let range = NSRange(uppercased.startIndex..., in: uppercased)
            let hasWhere = Self.whereClauseRegex?.firstMatch(in: uppercased, options: [], range: range) != nil
            return !hasWhere
        }

        return false
    }
}
