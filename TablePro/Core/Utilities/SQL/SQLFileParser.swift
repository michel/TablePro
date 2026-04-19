//
//  SQLFileParser.swift
//  TablePro
//
//  Streaming SQL file parser that splits SQL statements while handling
//  comments, string literals, escape sequences, MySQL conditional comments,
//  DELIMITER commands, and hash comments.
//
//  Uses NSString character(at:) for O(1) random access.

import Foundation
import os

final class SQLFileParser: Sendable {
    private static let logger = Logger(subsystem: "com.TablePro", category: "SQLFileParser")

    // MARK: - Parser State

    private enum ParserState {
        case normal
        case inSingleLineComment
        case inMultiLineComment
        case inSingleQuotedString
        case inDoubleQuotedString
        case inBacktickQuotedString
    }

    // MARK: - Unicode Constants

    private static let kSemicolon: unichar = 0x3B
    private static let kSingleQuote: unichar = 0x27
    private static let kDoubleQuote: unichar = 0x22
    private static let kBacktick: unichar = 0x60
    private static let kBackslash: unichar = 0x5C
    private static let kDash: unichar = 0x2D
    private static let kSlash: unichar = 0x2F
    private static let kStar: unichar = 0x2A
    private static let kHash: unichar = 0x23
    private static let kExclamation: unichar = 0x21
    private static let kNewline: unichar = 0x0A
    private static let kSpace: unichar = 0x20
    private static let kTab: unichar = 0x09
    private static let kCarriageReturn: unichar = 0x0D

    // State-aware chunk boundary deferral. Characters that need lookahead
    // in the current state must not be processed without nextChar available.
    nonisolated private static func needsLookahead(
        _ char: unichar, state: ParserState, delimiter: NSString, isSingleCharDelimiter: Bool
    ) -> Bool {
        switch state {
        case .normal:
            var result = char == kDash || char == kSlash || char == kBackslash || char == kStar
                || char == kSingleQuote || char == kDoubleQuote || char == kBacktick
            if !isSingleCharDelimiter && char == delimiter.character(at: 0) {
                result = true
            }
            return result
        case .inSingleQuotedString:
            return char == kSingleQuote || char == kBackslash
        case .inDoubleQuotedString:
            return char == kDoubleQuote || char == kBackslash
        case .inBacktickQuotedString:
            return char == kBacktick
        case .inMultiLineComment:
            return char == kStar
        case .inSingleLineComment:
            return false
        }
    }

    nonisolated private static func isWhitespace(_ char: unichar) -> Bool {
        char == kSpace || char == kTab || char == kNewline || char == kCarriageReturn
    }

    private static func markContent(
        _ hasContent: Bool, _ startLine: Int, _ currentLine: Int
    ) -> (Bool, Int) {
        hasContent ? (true, startLine) : (true, currentLine)
    }

    private static func appendChar(_ char: unichar, to string: NSMutableString?) {
        guard let string else { return }
        var c = char
        CFStringAppendCharacters(string as CFMutableString, &c, 1)
    }

    // MARK: - Delimiter Matching

    private static func matchesDelimiter(
        at position: Int, delimiter: NSString, in buffer: NSString, bufLen: Int
    ) -> Bool {
        let delimLen = delimiter.length
        guard position + delimLen <= bufLen else { return false }
        for j in 0..<delimLen {
            if buffer.character(at: position + j) != delimiter.character(at: j) {
                return false
            }
        }
        return true
    }

    private static let delimiterPrefix = "DELIMITER "
    private static let delimiterPrefixLength = 10

    private static func extractDelimiterChange(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.uppercased().hasPrefix(delimiterPrefix) else { return nil }
        let newDelim = String(trimmed.dropFirst(delimiterPrefixLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return newDelim.isEmpty ? nil : newDelim
    }

    // MARK: - Mutable Parser Context

    private struct ParserContext {
        var state: ParserState = .normal
        let currentStatement: NSMutableString?
        var hasStatementContent = false
        var currentLine = 1
        var statementStartLine = 1
        var isConditionalComment = false
        var currentDelimiter: NSString = ";" as NSString
        var isSingleCharDelimiter = true
    }

    private static func trimmedStatement(_ ctx: ParserContext) -> String {
        (ctx.currentStatement as NSString?)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func resetStatement(_ ctx: inout ParserContext) {
        ctx.currentStatement?.setString("")
        ctx.hasStatementContent = false
    }

    // MARK: - Normal State Processing

    private static func processDelimiterChange(_ ctx: inout ParserContext, char: unichar) {
        guard char == kNewline && ctx.hasStatementContent else { return }
        let text = trimmedStatement(ctx)
        if let newDelim = extractDelimiterChange(text) {
            ctx.currentDelimiter = newDelim as NSString
            ctx.isSingleCharDelimiter = ctx.currentDelimiter.length == 1
                && ctx.currentDelimiter.character(at: 0) == kSemicolon
            resetStatement(&ctx)
        }
    }

    private static func processNormalChar(
        _ ctx: inout ParserContext,
        char: unichar,
        nextChar: unichar?,
        i: inout Int,
        nsBuffer: NSString,
        bufLen: Int,
        continuation: AsyncThrowingStream<(statement: String, lineNumber: Int), Error>.Continuation
    ) -> Bool {
        processDelimiterChange(&ctx, char: char)

        if char == kDash && nextChar == kDash {
            ctx.state = .inSingleLineComment
            i += 2
            return true
        }

        if char == kHash {
            ctx.state = .inSingleLineComment
            return false
        }

        if char == kSlash, let next = nextChar, next == kStar {
            let thirdChar: unichar? = (i + 2 < bufLen)
                ? nsBuffer.character(at: i + 2) : nil
            ctx.isConditionalComment = thirdChar == kExclamation
            ctx.state = .inMultiLineComment
            if ctx.isConditionalComment {
                (ctx.hasStatementContent, ctx.statementStartLine) = markContent(
                    ctx.hasStatementContent, ctx.statementStartLine, ctx.currentLine)
                appendChar(char, to: ctx.currentStatement)
                appendChar(next, to: ctx.currentStatement)
            }
            i += 2
            return true
        }

        if let advanced = processQuoteOpen(&ctx, char: char, nextChar: nextChar) {
            if advanced { i += 2 }
            return advanced
        }

        if ctx.isSingleCharDelimiter && char == kSemicolon {
            yieldAndReset(&ctx, continuation: continuation)
            return false
        }

        if !ctx.isSingleCharDelimiter
            && matchesDelimiter(at: i, delimiter: ctx.currentDelimiter, in: nsBuffer, bufLen: bufLen)
        {
            yieldAndReset(&ctx, continuation: continuation)
            i += ctx.currentDelimiter.length
            return true
        }

        if !ctx.hasStatementContent && !isWhitespace(char) {
            ctx.statementStartLine = ctx.currentLine
            ctx.hasStatementContent = true
        }
        appendChar(char, to: ctx.currentStatement)
        return false
    }

    private static func processQuoteOpen(
        _ ctx: inout ParserContext,
        char: unichar,
        nextChar: unichar?
    ) -> Bool? {
        let quoteMapping: [(unichar, ParserState)] = [
            (kSingleQuote, .inSingleQuotedString),
            (kDoubleQuote, .inDoubleQuotedString),
            (kBacktick, .inBacktickQuotedString)
        ]
        for (quoteChar, targetState) in quoteMapping {
            guard char == quoteChar else { continue }
            if let next = nextChar, next == quoteChar {
                (ctx.hasStatementContent, ctx.statementStartLine) = markContent(
                    ctx.hasStatementContent, ctx.statementStartLine, ctx.currentLine)
                appendChar(char, to: ctx.currentStatement)
                appendChar(next, to: ctx.currentStatement)
                return true
            }
            ctx.state = targetState
            (ctx.hasStatementContent, ctx.statementStartLine) = markContent(
                ctx.hasStatementContent, ctx.statementStartLine, ctx.currentLine)
            appendChar(char, to: ctx.currentStatement)
            return false
        }
        return nil
    }

    private static func yieldAndReset(
        _ ctx: inout ParserContext,
        continuation: AsyncThrowingStream<(statement: String, lineNumber: Int), Error>.Continuation
    ) {
        if ctx.hasStatementContent {
            let text = trimmedStatement(ctx)
            continuation.yield((text, ctx.statementStartLine))
        }
        resetStatement(&ctx)
    }

    // MARK: - Comment State Processing

    private static func processMultiLineComment(
        _ ctx: inout ParserContext,
        char: unichar,
        nextChar: unichar?,
        i: inout Int
    ) -> Bool {
        if ctx.isConditionalComment {
            appendChar(char, to: ctx.currentStatement)
        }
        if char == kStar, let next = nextChar, next == kSlash {
            if ctx.isConditionalComment {
                appendChar(next, to: ctx.currentStatement)
            }
            ctx.state = .normal
            ctx.isConditionalComment = false
            i += 2
            return true
        }
        return false
    }

    // MARK: - Quoted String State Processing

    private static func processQuotedString(
        _ ctx: inout ParserContext,
        char: unichar,
        nextChar: unichar?,
        quoteChar: unichar,
        supportsBackslashEscape: Bool = true,
        i: inout Int
    ) -> Bool {
        appendChar(char, to: ctx.currentStatement)
        if supportsBackslashEscape && char == kBackslash, let next = nextChar {
            appendChar(next, to: ctx.currentStatement)
            if next == kNewline { ctx.currentLine += 1 }
            i += 2
            return true
        }
        if char == quoteChar, let next = nextChar, next == quoteChar {
            appendChar(next, to: ctx.currentStatement)
            i += 2
            return true
        }
        if char == quoteChar {
            ctx.state = .normal
        }
        return false
    }

    // MARK: - Public API

    func parseFile(
        url: URL,
        encoding: String.Encoding,
        countOnly: Bool = false
    ) -> AsyncThrowingStream<(statement: String, lineNumber: Int), Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let fileHandle = try FileHandle(forReadingFrom: url)
                    defer {
                        do {
                            try fileHandle.close()
                        } catch {
                            Self.logger.warning("Failed to close file handle for \(url.path): \(error)")
                        }
                    }

                    var ctx = ParserContext(currentStatement: countOnly ? nil : NSMutableString())
                    let nsBuffer = NSMutableString()
                    let chunkSize = 65_536

                    while true {
                        guard !Task.isCancelled else {
                            continuation.finish()
                            return
                        }
                        let data = fileHandle.readData(ofLength: chunkSize)
                        if data.isEmpty { break }

                        guard let chunk = String(data: data, encoding: encoding) else {
                            Self.logger.error("Failed to decode chunk with encoding \(encoding.description)")
                            continuation.finish(throwing: DecompressionError.fileReadFailed(
                                "Failed to decode file with \(encoding.description) encoding"
                            ))
                            return
                        }

                        nsBuffer.append(chunk)
                        let bufLen = nsBuffer.length
                        var i = 0

                        while i < bufLen {
                            let char = nsBuffer.character(at: i)
                            let nextChar: unichar? = (i + 1 < bufLen) ? nsBuffer.character(at: i + 1) : nil

                            if nextChar == nil && Self.needsLookahead(
                                char, state: ctx.state,
                                delimiter: ctx.currentDelimiter,
                                isSingleCharDelimiter: ctx.isSingleCharDelimiter
                            ) {
                                break
                            }

                            if char == Self.kNewline { ctx.currentLine += 1 }
                            var didManuallyAdvance = false

                            switch ctx.state {
                            case .normal:
                                didManuallyAdvance = Self.processNormalChar(
                                    &ctx, char: char, nextChar: nextChar,
                                    i: &i, nsBuffer: nsBuffer, bufLen: bufLen,
                                    continuation: continuation)

                            case .inSingleLineComment:
                                if char == Self.kNewline {
                                    ctx.state = .normal
                                }

                            case .inMultiLineComment:
                                didManuallyAdvance = Self.processMultiLineComment(
                                    &ctx, char: char, nextChar: nextChar, i: &i)

                            case .inSingleQuotedString:
                                didManuallyAdvance = Self.processQuotedString(
                                    &ctx, char: char, nextChar: nextChar,
                                    quoteChar: Self.kSingleQuote, i: &i)

                            case .inDoubleQuotedString:
                                didManuallyAdvance = Self.processQuotedString(
                                    &ctx, char: char, nextChar: nextChar,
                                    quoteChar: Self.kDoubleQuote, i: &i)

                            case .inBacktickQuotedString:
                                didManuallyAdvance = Self.processQuotedString(
                                    &ctx, char: char, nextChar: nextChar,
                                    quoteChar: Self.kBacktick,
                                    supportsBackslashEscape: false, i: &i)
                            }

                            if !didManuallyAdvance {
                                i += 1
                            }
                        }

                        if i < bufLen {
                            nsBuffer.deleteCharacters(in: NSRange(location: 0, length: i))
                        } else {
                            nsBuffer.setString("")
                        }
                    }

                    if ctx.hasStatementContent {
                        let text = Self.trimmedStatement(ctx)
                        if Self.extractDelimiterChange(text) == nil {
                            continuation.yield((text, ctx.statementStartLine))
                        }
                    }

                    continuation.finish()
                } catch {
                    Self.logger.error("SQL file parsing failed: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func countStatements(url: URL, encoding: String.Encoding) async throws -> Int {
        var count = 0

        for try await _ in parseFile(url: url, encoding: encoding, countOnly: true) {
            try Task.checkCancellation()
            count += 1
        }

        return count
    }
}
