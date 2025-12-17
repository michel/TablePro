//
//  SQLContextAnalyzer.swift
//  OpenTable
//
//  Analyzes SQL query text to determine cursor context for autocomplete
//

import Foundation

/// Type of SQL clause the cursor is in
enum SQLClauseType {
    case select         // In SELECT list
    case from           // After FROM
    case join           // After JOIN
    case on             // After ON (join condition)
    case where_         // After WHERE
    case and            // After AND/OR
    case groupBy        // After GROUP BY
    case orderBy        // After ORDER BY
    case having         // After HAVING
    case set            // After SET (UPDATE)
    case into           // After INTO (INSERT)
    case values         // After VALUES
    case insertColumns  // Column list in INSERT
    case unknown        // Unknown or start of query
}

/// Represents a table reference with optional alias
struct TableReference: Equatable, Sendable {
    let tableName: String
    let alias: String?
    
    /// Returns the identifier that should be used to reference this table
    var identifier: String {
        alias ?? tableName
    }
}

/// Result of context analysis
struct SQLContext {
    let clauseType: SQLClauseType
    let prefix: String              // Current word being typed
    let prefixRange: Range<Int>     // Range of prefix in original text
    let dotPrefix: String?          // Table/alias before dot (e.g., "u" in "u.name")
    let tableReferences: [TableReference]  // All tables in scope
    let isInsideString: Bool        // Inside a string literal
    let isInsideComment: Bool       // Inside a comment
}

/// Analyzes SQL query to determine completion context
final class SQLContextAnalyzer {
    
    // MARK: - Main Analysis
    
    /// Analyze the query at the given cursor position
    func analyze(query: String, cursorPosition: Int) -> SQLContext {
        let safePosition = min(cursorPosition, query.count)
        let textBeforeCursor = String(query.prefix(safePosition))
        
        // Check if inside string or comment
        if isInsideString(textBeforeCursor) {
            return SQLContext(
                clauseType: .unknown,
                prefix: "",
                prefixRange: safePosition..<safePosition,
                dotPrefix: nil,
                tableReferences: [],
                isInsideString: true,
                isInsideComment: false
            )
        }
        
        if isInsideComment(textBeforeCursor) {
            return SQLContext(
                clauseType: .unknown,
                prefix: "",
                prefixRange: safePosition..<safePosition,
                dotPrefix: nil,
                tableReferences: [],
                isInsideString: false,
                isInsideComment: true
            )
        }
        
        // Extract prefix and dot prefix
        let (prefix, prefixStart, dotPrefix) = extractPrefix(from: textBeforeCursor)
        
        // Find all table references in the query
        let tableReferences = extractTableReferences(from: query)
        
        // Determine clause type
        let clauseType = determineClauseType(textBeforeCursor: textBeforeCursor, dotPrefix: dotPrefix)
        
        return SQLContext(
            clauseType: clauseType,
            prefix: prefix,
            prefixRange: prefixStart..<safePosition,
            dotPrefix: dotPrefix,
            tableReferences: tableReferences,
            isInsideString: false,
            isInsideComment: false
        )
    }
    
    // MARK: - Helper Methods
    
    /// Check if cursor is inside a string literal
    private func isInsideString(_ text: String) -> Bool {
        var inSingleQuote = false
        var inDoubleQuote = false
        var prevChar: Character = "\0"
        
        for char in text {
            if char == "'" && prevChar != "\\" && !inDoubleQuote {
                inSingleQuote.toggle()
            } else if char == "\"" && prevChar != "\\" && !inSingleQuote {
                inDoubleQuote.toggle()
            }
            prevChar = char
        }
        
        return inSingleQuote || inDoubleQuote
    }
    
    /// Check if cursor is inside a comment
    private func isInsideComment(_ text: String) -> Bool {
        // Check for line comment
        if let lastNewline = text.lastIndex(of: "\n") {
            let lineStart = text.index(after: lastNewline)
            let currentLine = String(text[lineStart...])
            if currentLine.contains("--") {
                let dashIndex = currentLine.range(of: "--")!.lowerBound
                // Check if -- is before current position in line
                if currentLine[..<dashIndex].trimmingCharacters(in: .whitespaces).isEmpty ||
                   !currentLine[..<dashIndex].contains("'") {
                    return true
                }
            }
        } else if text.contains("--") {
            // First line and contains --
            if let range = text.range(of: "--") {
                let before = text[..<range.lowerBound]
                // Not inside a string before --
                if !isInsideString(String(before)) {
                    return true
                }
            }
        }
        
        // Check for block comment
        let openCount = text.components(separatedBy: "/*").count - 1
        let closeCount = text.components(separatedBy: "*/").count - 1
        return openCount > closeCount
    }
    
    /// Extract the current word prefix and any dot prefix (table.column)
    private func extractPrefix(from text: String) -> (prefix: String, start: Int, dotPrefix: String?) {
        guard !text.isEmpty else {
            return ("", 0, nil)
        }
        
        // Find start of current identifier
        var prefixStart = text.count
        var foundDot = false
        var dotPosition = -1
        
        // Scan backwards to find start of identifier
        let chars = Array(text)
        for i in stride(from: chars.count - 1, through: 0, by: -1) {
            let char = chars[i]
            
            if char == "." && !foundDot {
                foundDot = true
                dotPosition = i
                continue
            }
            
            if char.isLetter || char.isNumber || char == "_" || char == "`" {
                prefixStart = i
            } else if foundDot && (char.isLetter || char.isNumber || char == "_" || char == "`") {
                prefixStart = i
            } else {
                break
            }
        }
        
        let prefix: String
        let dotPrefix: String?
        
        if foundDot && dotPosition > prefixStart {
            // Has dot prefix like "users.na" or "u.na"
            let beforeDot = String(text[text.index(text.startIndex, offsetBy: prefixStart)..<text.index(text.startIndex, offsetBy: dotPosition)])
            let afterDot = String(text[text.index(text.startIndex, offsetBy: dotPosition + 1)...])
            
            dotPrefix = beforeDot.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            prefix = afterDot
            return (prefix, dotPosition + 1, dotPrefix)
        } else {
            // No dot, just a regular prefix
            prefix = String(text[text.index(text.startIndex, offsetBy: prefixStart)...])
            dotPrefix = nil
            return (prefix, prefixStart, nil)
        }
    }
    
    /// Extract all table references (table names and aliases) from the query
    private func extractTableReferences(from query: String) -> [TableReference] {
        var references: [TableReference] = []
        
        // SQL keywords that should NOT be treated as table names
        let sqlKeywords: Set<String> = [
            "LEFT", "RIGHT", "INNER", "OUTER", "FULL", "CROSS", "NATURAL",
            "JOIN", "ON", "AND", "OR", "WHERE", "SELECT", "FROM", "AS"
        ]
        
        // Pattern for FROM/JOIN table references with optional alias
        // Updated to handle: LEFT JOIN table, INNER JOIN table, etc.
        let patterns = [
            // FROM table [AS] alias
            "(?i)\\bFROM\\s+[`\"']?([\\w]+)[`\"']?(?:\\s+(?:AS\\s+)?[`\"']?([\\w]+)[`\"']?)?",
            // All types of JOINs: (LEFT|RIGHT|INNER|OUTER|CROSS|FULL)? (OUTER)? JOIN table [AS] alias
            "(?i)(?:LEFT|RIGHT|INNER|OUTER|CROSS|FULL)?\\s*(?:OUTER)?\\s*JOIN\\s+[`\"']?([\\w]+)[`\"']?(?:\\s+(?:AS\\s+)?[`\"']?([\\w]+)[`\"']?)?",
            // UPDATE table [AS] alias
            "(?i)\\bUPDATE\\s+[`\"']?([\\w]+)[`\"']?(?:\\s+(?:AS\\s+)?[`\"']?([\\w]+)[`\"']?)?"
        ]
        
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            
            let range = NSRange(query.startIndex..., in: query)
            regex.enumerateMatches(in: query, range: range) { match, _, _ in
                guard let match = match else { return }
                
                // Group 1: table name
                if let tableRange = Range(match.range(at: 1), in: query) {
                    let tableName = String(query[tableRange])
                    
                    // Skip SQL keywords
                    guard !sqlKeywords.contains(tableName.uppercased()) else { return }
                    
                    // Group 2: alias (optional)
                    var alias: String? = nil
                    if match.numberOfRanges > 2, let aliasRange = Range(match.range(at: 2), in: query) {
                        let aliasCandidate = String(query[aliasRange])
                        // Skip SQL keywords as aliases
                        if !sqlKeywords.contains(aliasCandidate.uppercased()) {
                            alias = aliasCandidate
                        }
                    }
                    
                    // Don't add duplicates
                    let ref = TableReference(tableName: tableName, alias: alias)
                    if !references.contains(ref) {
                        references.append(ref)
                    }
                }
            }
        }
        
        return references
    }
    
    /// Determine the clause type based on text before cursor
    private func determineClauseType(textBeforeCursor: String, dotPrefix: String?) -> SQLClauseType {
        // If we have a dot prefix, we're looking for columns
        if dotPrefix != nil {
            return .select // Column context
        }
        
        let upper = textBeforeCursor.uppercased()
        
        // Remove string literals and comments for analysis
        let cleaned = removeStringsAndComments(from: upper)
        
        // Find the last keyword to determine context
        // ORDER MATTERS: More specific patterns must come before general ones
        let clausePatterns: [(pattern: String, clause: SQLClauseType)] = [
            ("\\bVALUES\\s*\\([^)]*$", .values),
            ("\\bINSERT\\s+INTO\\s+\\w+\\s*\\([^)]*$", .insertColumns),
            ("\\bINTO\\s+\\w*$", .into),
            ("\\bSET\\s+[^;]*$", .set),
            ("\\bHAVING\\s+[^;]*$", .having),
            ("\\bORDER\\s+BY\\s+[^;]*$", .orderBy),
            ("\\bGROUP\\s+BY\\s+[^;]*$", .groupBy),
            ("\\b(AND|OR)\\s+\\w*$", .and),
            ("\\bWHERE\\s+[^;]*$", .where_),
            ("\\bON\\s+[^;]*$", .on),
            // JOIN: match various JOIN types followed by table [alias] - must come before FROM
            ("(?:LEFT|RIGHT|INNER|OUTER|FULL|CROSS)?\\s*(?:OUTER)?\\s*JOIN\\s+[`\"']?\\w+[`\"']?(?:\\s+(?:AS\\s+)?\\w+)?\\s*$", .join),
            ("\\bJOIN\\s+[`\"']?\\w*[`\"']?\\s*$", .join),
            // FROM: match "FROM table" or "FROM table " (with or without trailing space) - NOT followed by WHERE/ORDER/etc.
            ("\\bFROM\\s+[`\"']?\\w+[`\"']?(?:\\s+(?:AS\\s+)?\\w+)?\\s*$", .from),
            ("\\bFROM\\s+\\w*$", .from),
            // SELECT comes last as it's the most general
            ("\\bSELECT\\s+[^;]*$", .select),
        ]
        
        for (pattern, clause) in clausePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) != nil {
                return clause
            }
        }
        
        return .unknown
    }
    
    /// Remove string literals and comments for cleaner analysis
    private func removeStringsAndComments(from text: String) -> String {
        var result = text
        
        // Remove single-quoted strings
        if let regex = try? NSRegularExpression(pattern: "'[^']*'") {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "''")
        }
        
        // Remove double-quoted strings
        if let regex = try? NSRegularExpression(pattern: "\"[^\"]*\"") {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "\"\"")
        }
        
        // Remove block comments
        if let regex = try? NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/") {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        
        // Remove line comments
        if let regex = try? NSRegularExpression(pattern: "--[^\n]*") {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        
        return result
    }
}
