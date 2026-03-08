//
//  ImportModels.swift
//  TablePro
//
//  Data models for SQL import functionality.
//

import Foundation

// MARK: - Import Configuration

/// Configuration for SQL import operation
struct ImportConfiguration {
    var encoding: String.Encoding = .utf8
    var wrapInTransaction: Bool = true
    var disableForeignKeyChecks: Bool = true
}

// MARK: - Import Encoding Options

/// Available text encodings for import
enum ImportEncoding: String, CaseIterable, Identifiable {
    case utf8 = "UTF-8"
    case utf16 = "UTF-16"
    case latin1 = "Latin1"
    case ascii = "ASCII"

    var id: String { rawValue }

    var encoding: String.Encoding {
        switch self {
        case .utf8:
            return .utf8
        case .utf16:
            return .utf16
        case .latin1:
            return .isoLatin1
        case .ascii:
            return .ascii
        }
    }
}

// MARK: - Import Error

/// Errors that can occur during import operations
enum ImportError: LocalizedError {
    case fileNotFound
    case fileReadFailed(String)
    case decompressFailed
    case parseStatementFailed(line: Int, reason: String)
    case importFailed(statement: String, line: Int, error: String)
    case cancelled
    case invalidEncoding
    case rollbackFailed(String)
    case foreignKeyCleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return String(localized: "File not found")
        case .fileReadFailed(let message):
            return String(localized: "Failed to read file: \(message)")
        case .decompressFailed:
            return String(localized: "Failed to decompress .gz file")
        case .parseStatementFailed(let line, let reason):
            return String(localized: "Failed to parse statement at line \(line): \(reason)")
        case .importFailed(_, let line, let error):
            return String(localized: "Import failed at line \(line): \(error)")
        case .cancelled:
            return String(localized: "Import cancelled by user")
        case .invalidEncoding:
            return String(localized: "Invalid file encoding. Try a different encoding option.")
        case .rollbackFailed(let message):
            return String(localized: "CRITICAL: Transaction rollback failed - database may be in inconsistent state: \(message)")
        case .foreignKeyCleanupFailed(let message):
            return String(localized: "WARNING: Failed to re-enable foreign key checks: \(message). Please manually verify FK constraints are enabled.")
        }
    }
}

// MARK: - Import Result

/// Result of import operation
struct ImportResult {
    let totalStatements: Int
    let executedStatements: Int
    let failedStatement: String?
    let failedLine: Int?
    let executionTime: TimeInterval
}
