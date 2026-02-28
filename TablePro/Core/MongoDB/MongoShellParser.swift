//
//  MongoShellParser.swift
//  TablePro
//
//  Parses MongoDB Shell syntax into structured operations.
//  Supports: db.collection.find/findOne/aggregate/insertOne/updateOne/deleteOne etc.
//

import Foundation
import os

/// A parsed MongoDB shell operation ready for execution
enum MongoOperation {
    case find(collection: String, filter: String, options: MongoFindOptions)
    case findOne(collection: String, filter: String)
    case aggregate(collection: String, pipeline: String)
    case countDocuments(collection: String, filter: String)
    case insertOne(collection: String, document: String)
    case insertMany(collection: String, documents: String)
    case updateOne(collection: String, filter: String, update: String)
    case updateMany(collection: String, filter: String, update: String)
    case replaceOne(collection: String, filter: String, replacement: String)
    case deleteOne(collection: String, filter: String)
    case deleteMany(collection: String, filter: String)
    case createIndex(collection: String, keys: String, options: String?)
    case dropIndex(collection: String, indexName: String)
    case drop(collection: String)
    case runCommand(command: String)
    case listCollections
    case listDatabases
    case ping
}

/// Options for a find operation parsed from chained methods
struct MongoFindOptions {
    var sort: String?
    var projection: String?
    var skip: Int?
    var limit: Int?
}

/// Error from parsing MongoDB Shell syntax
enum MongoShellParseError: Error, LocalizedError {
    case invalidSyntax(String)
    case unsupportedMethod(String)
    case invalidJson(String)
    case missingArgument(String)

    var errorDescription: String? {
        switch self {
        case .invalidSyntax(let msg):
            return String(localized: "Invalid MongoDB syntax: \(msg)")
        case .unsupportedMethod(let method):
            return String(localized: "Unsupported MongoDB method: \(method)")
        case .invalidJson(let msg):
            return String(localized: "Invalid JSON: \(msg)")
        case .missingArgument(let msg):
            return String(localized: "Missing argument: \(msg)")
        }
    }
}

struct MongoShellParser {
    private static let logger = Logger(subsystem: "com.TablePro", category: "MongoShellParser")

    // MARK: - Public API

    /// Parse a MongoDB Shell expression into a MongoOperation
    static func parse(_ input: String) throws -> MongoOperation {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            throw MongoShellParseError.invalidSyntax("Empty query")
        }

        // "show dbs" / "show databases"
        if trimmed.lowercased().hasPrefix("show db") || trimmed.lowercased().hasPrefix("show databases") {
            return .listDatabases
        }

        // "show collections" / "show tables"
        if trimmed.lowercased().hasPrefix("show collection") || trimmed.lowercased().hasPrefix("show tables") {
            return .listCollections
        }

        // Raw JSON command: { ... }
        if trimmed.hasPrefix("{") {
            return .runCommand(command: trimmed)
        }

        // db.runCommand({...}) / db.adminCommand({...})
        if trimmed.hasPrefix("db.runCommand(") || trimmed.hasPrefix("db.adminCommand(") {
            guard let argStart = trimmed.firstIndex(of: "(") else {
                throw MongoShellParseError.invalidSyntax("Missing opening parenthesis")
            }
            let arg = try extractParenthesizedArg(from: trimmed, startingAt: argStart)
            return .runCommand(command: arg)
        }

        // db.collection.method(args) pattern
        guard trimmed.hasPrefix("db.") else {
            throw MongoShellParseError.invalidSyntax("Query must start with 'db.' or be a JSON command")
        }

        return try parseDbExpression(trimmed)
    }

    // MARK: - Private Parsing

    private static func parseDbExpression(_ input: String) throws -> MongoOperation {
        // Remove "db." prefix
        let afterDb = String(input.dropFirst(3))

        // Find the collection name (everything before the first ".")
        guard let dotIndex = afterDb.firstIndex(of: ".") else {
            // Just "db.collectionName" -- treat as find all
            let collection = afterDb.trimmingCharacters(in: .whitespacesAndNewlines)
            return .find(collection: collection, filter: "{}", options: MongoFindOptions())
        }

        let collection = String(afterDb[afterDb.startIndex..<dotIndex])
        let remainder = String(afterDb[afterDb.index(after: dotIndex)...])

        return try parseMethodChain(collection: collection, chain: remainder)
    }

    private static func parseMethodChain(collection: String, chain: String) throws -> MongoOperation {
        guard let parenIndex = chain.firstIndex(of: "(") else {
            throw MongoShellParseError.invalidSyntax("Expected method call with parentheses")
        }

        let methodName = String(chain[chain.startIndex..<parenIndex])

        let argAndRest = try extractParenthesizedArgAndRemainder(from: chain, startingAt: parenIndex)
        let arg = argAndRest.arg
        let remainder = argAndRest.remainder

        var operation: MongoOperation

        switch methodName {
        case "find":
            let (filter, projection) = try parseFindArgs(arg)
            var options = MongoFindOptions()
            options.projection = projection
            operation = .find(collection: collection, filter: filter, options: options)

        case "findOne":
            let filter = arg.isEmpty ? "{}" : arg
            operation = .findOne(collection: collection, filter: filter)

        case "aggregate":
            let pipeline = arg.isEmpty ? "[]" : arg
            operation = .aggregate(collection: collection, pipeline: pipeline)

        case "countDocuments", "count":
            let filter = arg.isEmpty ? "{}" : arg
            operation = .countDocuments(collection: collection, filter: filter)

        case "insertOne":
            guard !arg.isEmpty else {
                throw MongoShellParseError.missingArgument("insertOne requires a document")
            }
            operation = .insertOne(collection: collection, document: arg)

        case "insertMany":
            guard !arg.isEmpty else {
                throw MongoShellParseError.missingArgument("insertMany requires an array of documents")
            }
            operation = .insertMany(collection: collection, documents: arg)

        case "updateOne":
            let (filter, update) = try parseTwoArgs(arg, method: "updateOne")
            operation = .updateOne(collection: collection, filter: filter, update: update)

        case "updateMany":
            let (filter, update) = try parseTwoArgs(arg, method: "updateMany")
            operation = .updateMany(collection: collection, filter: filter, update: update)

        case "replaceOne":
            let (filter, replacement) = try parseTwoArgs(arg, method: "replaceOne")
            operation = .replaceOne(collection: collection, filter: filter, replacement: replacement)

        case "deleteOne":
            let filter = arg.isEmpty ? "{}" : arg
            operation = .deleteOne(collection: collection, filter: filter)

        case "deleteMany":
            let filter = arg.isEmpty ? "{}" : arg
            operation = .deleteMany(collection: collection, filter: filter)

        case "createIndex":
            let (keys, options) = try parseTwoArgsOptional(arg)
            operation = .createIndex(collection: collection, keys: keys, options: options)

        case "dropIndex":
            operation = .dropIndex(collection: collection, indexName: arg)

        case "drop":
            operation = .drop(collection: collection)

        default:
            throw MongoShellParseError.unsupportedMethod(methodName)
        }

        // Parse chained methods (.sort(), .limit(), .skip(), .projection())
        if !remainder.isEmpty, case .find(let coll, let filter, var opts) = operation {
            opts = try parseChainedOptions(remainder, options: opts)
            operation = .find(collection: coll, filter: filter, options: opts)
        }

        return operation
    }

    /// Parse chained find options: .sort({...}).limit(N).skip(N)
    private static func parseChainedOptions(_ chain: String, options: MongoFindOptions) throws -> MongoFindOptions {
        var opts = options
        var remaining = chain.trimmingCharacters(in: .whitespacesAndNewlines)

        while remaining.hasPrefix(".") {
            remaining = String(remaining.dropFirst())

            guard let parenIndex = remaining.firstIndex(of: "(") else { break }
            let method = String(remaining[remaining.startIndex..<parenIndex])

            let argAndRest = try extractParenthesizedArgAndRemainder(from: remaining, startingAt: parenIndex)
            let arg = argAndRest.arg
            remaining = argAndRest.remainder.trimmingCharacters(in: .whitespacesAndNewlines)

            switch method {
            case "sort":
                opts.sort = arg
            case "limit":
                opts.limit = Int(arg.trimmingCharacters(in: .whitespaces))
            case "skip":
                opts.skip = Int(arg.trimmingCharacters(in: .whitespaces))
            case "projection":
                opts.projection = arg
            default:
                break
            }
        }

        return opts
    }

    // MARK: - Argument Extraction Helpers

    /// Extract content inside balanced parentheses starting at the given index
    private static func extractParenthesizedArg(from str: String, startingAt openParen: String.Index) throws -> String {
        let result = try extractParenthesizedArgAndRemainder(from: str, startingAt: openParen)
        return result.arg
    }

    /// Extract content inside balanced parentheses and return both the arg and the remainder
    private static func extractParenthesizedArgAndRemainder(
        from str: String,
        startingAt openParen: String.Index
    ) throws -> (arg: String, remainder: String) {
        var depth = 0
        var inString = false
        var escapeNext = false
        var stringChar: Character = "\""
        var closeParen: String.Index?

        for i in str.indices[openParen...] {
            let ch = str[i]

            if escapeNext {
                escapeNext = false
                continue
            }

            if ch == "\\" {
                escapeNext = true
                continue
            }

            if inString {
                if ch == stringChar {
                    inString = false
                }
                continue
            }

            if ch == "\"" || ch == "'" {
                inString = true
                stringChar = ch
                continue
            }

            if ch == "(" { depth += 1 }
            if ch == ")" {
                depth -= 1
                if depth == 0 {
                    closeParen = i
                    break
                }
            }
        }

        guard let close = closeParen else {
            throw MongoShellParseError.invalidSyntax("Unmatched parenthesis")
        }

        let argStart = str.index(after: openParen)
        let arg = String(str[argStart..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
        let remainderStart = str.index(after: close)
        let remainder = String(str[remainderStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

        return (arg, remainder)
    }

    /// Parse find() arguments: (filter) or (filter, projection)
    private static func parseFindArgs(_ args: String) throws -> (filter: String, projection: String?) {
        if args.isEmpty { return ("{}", nil) }

        let parts = try splitTopLevelArgs(args)
        let filter = parts.isEmpty ? "{}" : parts[0]
        let projection = parts.count > 1 ? parts[1] : nil
        return (filter, projection)
    }

    /// Parse two required arguments separated by comma at the top level
    private static func parseTwoArgs(_ args: String, method: String) throws -> (String, String) {
        let parts = try splitTopLevelArgs(args)
        guard parts.count >= 2 else {
            throw MongoShellParseError.missingArgument("\(method) requires 2 arguments")
        }
        return (parts[0], parts[1])
    }

    /// Parse two arguments where the second is optional
    private static func parseTwoArgsOptional(_ args: String) throws -> (String, String?) {
        let parts = try splitTopLevelArgs(args)
        guard !parts.isEmpty else {
            throw MongoShellParseError.missingArgument("Expected at least one argument")
        }
        return (parts[0], parts.count > 1 ? parts[1] : nil)
    }

    /// Split arguments at top-level commas (respecting nested braces/brackets/strings)
    private static func splitTopLevelArgs(_ input: String) throws -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var inString = false
        var escapeNext = false
        var stringChar: Character = "\""

        for ch in input {
            if escapeNext {
                current.append(ch)
                escapeNext = false
                continue
            }

            if ch == "\\" {
                current.append(ch)
                escapeNext = true
                continue
            }

            if inString {
                current.append(ch)
                if ch == stringChar {
                    inString = false
                }
                continue
            }

            if ch == "\"" || ch == "'" {
                current.append(ch)
                inString = true
                stringChar = ch
                continue
            }

            if ch == "{" || ch == "[" || ch == "(" { depth += 1 }
            if ch == "}" || ch == "]" || ch == ")" { depth -= 1 }

            if ch == "," && depth == 0 {
                parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                continue
            }

            current.append(ch)
        }

        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(trimmed)
        }

        return parts
    }
}
