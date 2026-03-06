//
//  SQLStatementScanner.swift
//  TablePro
//

import Foundation

enum SQLStatementScanner {
    struct LocatedStatement {
        let sql: String
        let offset: Int
    }

    static func allStatements(in sql: String) -> [String] {
        var results: [String] = []
        scan(sql: sql, cursorPosition: nil) { stmt, _ in
            if !stmt.isEmpty {
                results.append(stmt)
            }
            return true
        }
        return results
    }

    static func statementAtCursor(in sql: String, cursorPosition: Int) -> String {
        var result = locatedStatementAtCursor(in: sql, cursorPosition: cursorPosition)
            .sql
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasSuffix(";") {
            result = String(result.dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    static func locatedStatementAtCursor(in sql: String, cursorPosition: Int) -> LocatedStatement {
        let nsQuery = sql as NSString
        let length = nsQuery.length
        guard length > 0 else { return LocatedStatement(sql: "", offset: 0) }

        guard nsQuery.range(of: ";").location != NSNotFound else {
            return LocatedStatement(sql: sql, offset: 0)
        }

        let safePosition = min(max(0, cursorPosition), length)

        var currentStart = 0
        var inString = false
        var stringCharVal: UInt16 = 0
        var inLineComment = false
        var inBlockComment = false
        var i = 0

        while i < length {
            let ch = nsQuery.character(at: i)

            if inLineComment {
                if ch == newline { inLineComment = false }
                i += 1
                continue
            }

            if inBlockComment {
                if ch == star && i + 1 < length && nsQuery.character(at: i + 1) == slash {
                    inBlockComment = false
                    i += 2
                    continue
                }
                i += 1
                continue
            }

            if !inString && ch == dash && i + 1 < length && nsQuery.character(at: i + 1) == dash {
                inLineComment = true
                i += 2
                continue
            }

            if !inString && ch == slash && i + 1 < length && nsQuery.character(at: i + 1) == star {
                inBlockComment = true
                i += 2
                continue
            }

            if inString && ch == backslash && i + 1 < length {
                i += 2
                continue
            }

            if ch == singleQuote || ch == doubleQuote || ch == backtick {
                if !inString {
                    inString = true
                    stringCharVal = ch
                } else if ch == stringCharVal {
                    if i + 1 < length && nsQuery.character(at: i + 1) == stringCharVal {
                        i += 1
                    } else {
                        inString = false
                    }
                }
            }

            if ch == semicolonChar && !inString {
                let stmtEnd = i + 1
                if safePosition >= currentStart && safePosition <= stmtEnd {
                    let stmtRange = NSRange(location: currentStart, length: stmtEnd - currentStart)
                    return LocatedStatement(
                        sql: nsQuery.substring(with: stmtRange),
                        offset: currentStart
                    )
                }
                currentStart = stmtEnd
            }

            i += 1
        }

        if currentStart < length {
            let stmtRange = NSRange(location: currentStart, length: length - currentStart)
            return LocatedStatement(
                sql: nsQuery.substring(with: stmtRange),
                offset: currentStart
            )
        }

        return LocatedStatement(sql: sql, offset: 0)
    }

    // MARK: - Private

    private static let singleQuote = UInt16(UnicodeScalar("'").value)
    private static let doubleQuote = UInt16(UnicodeScalar("\"").value)
    private static let backtick = UInt16(UnicodeScalar("`").value)
    private static let semicolonChar = UInt16(UnicodeScalar(";").value)
    private static let dash = UInt16(UnicodeScalar("-").value)
    private static let slash = UInt16(UnicodeScalar("/").value)
    private static let star = UInt16(UnicodeScalar("*").value)
    private static let newline = UInt16(UnicodeScalar("\n").value)
    private static let backslash = UInt16(UnicodeScalar("\\").value)
    private static let space = UInt16(UnicodeScalar(" ").value)
    private static let tab = UInt16(UnicodeScalar("\t").value)
    private static let cr = UInt16(UnicodeScalar("\r").value)

    private static func trimmedOffset(in nsString: NSString, from start: Int, to end: Int) -> Int {
        var pos = start
        while pos < end {
            let ch = nsString.character(at: pos)
            if ch == space || ch == tab || ch == newline || ch == cr {
                pos += 1
            } else {
                break
            }
        }
        return pos
    }

    /// Scans SQL text splitting on semicolons, respecting strings, identifiers, and comments.
    /// Calls `onStatement` for each statement found. If `cursorPosition` is set, only calls
    /// `onStatement` for the statement containing the cursor and stops.
    /// Return `false` from `onStatement` to stop scanning early.
    private static func scan(
        sql: String,
        cursorPosition: Int?,
        onStatement: (_ trimmedSQL: String, _ offset: Int) -> Bool
    ) {
        let nsQuery = sql as NSString
        let length = nsQuery.length
        guard length > 0 else {
            let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                _ = onStatement(trimmed, 0)
            }
            return
        }

        guard nsQuery.range(of: ";").location != NSNotFound else {
            let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                _ = onStatement(trimmed, trimmedOffset(in: nsQuery, from: 0, to: length))
            }
            return
        }

        var currentStart = 0
        var inString = false
        var stringCharVal: UInt16 = 0
        var inLineComment = false
        var inBlockComment = false
        var i = 0

        while i < length {
            let ch = nsQuery.character(at: i)

            if inLineComment {
                if ch == newline { inLineComment = false }
                i += 1
                continue
            }

            if inBlockComment {
                if ch == star && i + 1 < length && nsQuery.character(at: i + 1) == slash {
                    inBlockComment = false
                    i += 2
                    continue
                }
                i += 1
                continue
            }

            if !inString && ch == dash && i + 1 < length && nsQuery.character(at: i + 1) == dash {
                inLineComment = true
                i += 2
                continue
            }

            if !inString && ch == slash && i + 1 < length && nsQuery.character(at: i + 1) == star {
                inBlockComment = true
                i += 2
                continue
            }

            if inString && ch == backslash && i + 1 < length {
                i += 2
                continue
            }

            if ch == singleQuote || ch == doubleQuote || ch == backtick {
                if !inString {
                    inString = true
                    stringCharVal = ch
                } else if ch == stringCharVal {
                    if i + 1 < length && nsQuery.character(at: i + 1) == stringCharVal {
                        i += 1
                    } else {
                        inString = false
                    }
                }
            }

            if ch == semicolonChar && !inString {
                let stmtEnd = i + 1

                if let cursor = cursorPosition {
                    if cursor >= currentStart && cursor <= stmtEnd {
                        let stmtRange = NSRange(location: currentStart, length: i - currentStart)
                        let stmt = nsQuery.substring(with: stmtRange)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let offset = trimmedOffset(in: nsQuery, from: currentStart, to: i)
                        _ = onStatement(stmt, offset)
                        return
                    }
                } else {
                    let stmtRange = NSRange(location: currentStart, length: i - currentStart)
                    let stmt = nsQuery.substring(with: stmtRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let offset = trimmedOffset(in: nsQuery, from: currentStart, to: i)
                    if !onStatement(stmt, offset) { return }
                }

                currentStart = stmtEnd
            }

            i += 1
        }

        if currentStart < length {
            let stmtRange = NSRange(location: currentStart, length: length - currentStart)
            let stmt = nsQuery.substring(with: stmtRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let offset = trimmedOffset(in: nsQuery, from: currentStart, to: length)
            _ = onStatement(stmt, offset)
        }
    }
}
