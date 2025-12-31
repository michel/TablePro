//
//  SQLFileParser.swift
//  TablePro
//
//  Streaming SQL file parser that splits SQL statements while handling
//  comments, string literals, and escape sequences.
//

import Foundation

/// SQL statement parser that handles comments, strings, and multi-line statements
final class SQLFileParser {

    // MARK: - Parser State

    private enum ParserState {
        case normal
        case inSingleLineComment
        case inMultiLineComment
        case inSingleQuotedString
        case inDoubleQuotedString
        case inBacktickQuotedString
    }

    // MARK: - Public API

    /// Parse SQL file and return async stream of statements with line numbers
    /// - Parameters:
    ///   - url: File URL to parse
    ///   - encoding: Text encoding to use
    /// - Returns: AsyncStream of (statement, lineNumber) tuples
    func parseFile(
        url: URL,
        encoding: String.Encoding
    ) async throws -> AsyncStream<(statement: String, lineNumber: Int)> {

        return AsyncStream { continuation in
            Task {
                do {
                    let fileHandle = try FileHandle(forReadingFrom: url)
                    defer { try? fileHandle.close() }

                    var state: ParserState = .normal
                    var currentStatement = ""
                    var currentLine = 1
                    var statementStartLine = 1
                    var buffer = ""

                    // Read file in chunks
                    let chunkSize = 4096

                    while true {
                        let data = fileHandle.readData(ofLength: chunkSize)
                        if data.isEmpty { break }

                        guard let chunk = String(data: data, encoding: encoding) else {
                            continuation.finish()
                            return
                        }

                        buffer += chunk

                        // Process buffer character by character
                        var index = buffer.startIndex

                        while index < buffer.endIndex {
                            let char = buffer[index]
                            let nextIndex = buffer.index(after: index)
                            let nextChar: Character? = nextIndex < buffer.endIndex ? buffer[nextIndex] : nil

                            // Track line numbers
                            if char == "\n" {
                                currentLine += 1
                            }

                            // State machine transitions
                            switch state {
                            case .normal:
                                if char == "-" && nextChar == "-" {
                                    // Start of single-line comment
                                    state = .inSingleLineComment
                                    index = nextIndex // Skip second -
                                } else if char == "/" && nextChar == "*" {
                                    // Start of multi-line comment
                                    state = .inMultiLineComment
                                    index = nextIndex // Skip *
                                } else if char == "'" {
                                    // Start of single-quoted string
                                    state = .inSingleQuotedString
                                    currentStatement.append(char)
                                } else if char == "\"" {
                                    // Start of double-quoted string
                                    state = .inDoubleQuotedString
                                    currentStatement.append(char)
                                } else if char == "`" {
                                    // Start of backtick-quoted string
                                    state = .inBacktickQuotedString
                                    currentStatement.append(char)
                                } else if char == ";" {
                                    // Statement boundary!
                                    let trimmed = currentStatement.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        continuation.yield((trimmed, statementStartLine))
                                    }
                                    currentStatement = ""
                                    statementStartLine = currentLine
                                } else {
                                    currentStatement.append(char)
                                }

                            case .inSingleLineComment:
                                if char == "\n" {
                                    // End of single-line comment
                                    state = .normal
                                    // Don't append comment to statement
                                }

                            case .inMultiLineComment:
                                if char == "*" && nextChar == "/" {
                                    // End of multi-line comment
                                    state = .normal
                                    index = nextIndex // Skip /
                                }

                            case .inSingleQuotedString:
                                currentStatement.append(char)
                                if char == "\\" && nextChar != nil {
                                    // Escaped character - add both \ and next char
                                    index = nextIndex
                                    currentStatement.append(buffer[index])
                                } else if char == "'" && nextChar == "'" {
                                    // Doubled quote (SQL escape) - add both
                                    index = nextIndex
                                    currentStatement.append(buffer[index])
                                } else if char == "'" {
                                    // End of string
                                    state = .normal
                                }

                            case .inDoubleQuotedString:
                                currentStatement.append(char)
                                if char == "\\" && nextChar != nil {
                                    // Escaped character - add both \ and next char
                                    index = nextIndex
                                    currentStatement.append(buffer[index])
                                } else if char == "\"" {
                                    // End of string
                                    state = .normal
                                }

                            case .inBacktickQuotedString:
                                currentStatement.append(char)
                                if char == "`" {
                                    // End of string
                                    state = .normal
                                }
                            }

                            index = buffer.index(after: index)
                        }

                        // Clear processed buffer
                        buffer = ""
                    }

                    // Add final statement if any
                    let trimmed = currentStatement.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        continuation.yield((trimmed, statementStartLine))
                    }

                    continuation.finish()

                } catch {
                    continuation.finish()
                }
            }
        }
    }

    /// Count total statements in file (requires full file scan)
    /// - Parameters:
    ///   - url: File URL to parse
    ///   - encoding: Text encoding to use
    /// - Returns: Total number of statements
    func countStatements(url: URL, encoding: String.Encoding) async throws -> Int {
        var count = 0

        for try await _ in try await parseFile(url: url, encoding: encoding) {
            count += 1
        }

        return count
    }
}
