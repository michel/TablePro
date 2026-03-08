//
//  ExportService.swift
//  TablePro
//
//  Service responsible for exporting table data to CSV, JSON, and SQL formats.
//  Supports configurable options for each format including compression.
//

import Foundation
import Observation
import os

// MARK: - Export Error

/// Errors that can occur during export operations
enum ExportError: LocalizedError {
    case notConnected
    case noTablesSelected
    case exportFailed(String)
    case compressionFailed
    case fileWriteFailed(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return String(localized: "Not connected to database")
        case .noTablesSelected:
            return String(localized: "No tables selected for export")
        case .exportFailed(let message):
            return String(localized: "Export failed: \(message)")
        case .compressionFailed:
            return String(localized: "Failed to compress data")
        case .fileWriteFailed(let path):
            return String(localized: "Failed to write file: \(path)")
        case .encodingFailed:
            return String(localized: "Failed to encode content as UTF-8")
        }
    }
}

// MARK: - String Extension for Safe Encoding

internal extension String {
    /// Safely encode string to UTF-8 data, throwing if encoding fails
    func toUTF8Data() throws -> Data {
        guard let data = self.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }
        return data
    }
}

// MARK: - Export State

/// Consolidated state struct to minimize @Published update overhead.
/// A single @Published property avoids N separate objectWillChange notifications per batch iteration.
struct ExportState {
    var isExporting: Bool = false
    var progress: Double = 0.0
    var currentTable: String = ""
    var currentTableIndex: Int = 0
    var totalTables: Int = 0
    var processedRows: Int = 0
    var totalRows: Int = 0
    var statusMessage: String = ""
    var errorMessage: String?
    var warningMessage: String?
}

// MARK: - Export Service

/// Service responsible for exporting table data to various formats
@MainActor @Observable
final class ExportService {
    static let logger = Logger(subsystem: "com.TablePro", category: "ExportService")
    // swiftlint:disable:next force_try
    static let decimalFormatRegex = try! NSRegularExpression(pattern: #"^[+-]?\d+\.\d+$"#)
    // MARK: - Published State

    var state = ExportState()

    // MARK: - DDL Failure Tracking

    /// Tables that failed DDL fetch during SQL export
    var ddlFailures: [String] = []

    // MARK: - Cancellation

    private let isCancelledLock = NSLock()
    private var _isCancelled: Bool = false
    var isCancelled: Bool {
        get {
            isCancelledLock.lock()
            defer { isCancelledLock.unlock() }
            return _isCancelled
        }
        set {
            isCancelledLock.lock()
            _isCancelled = newValue
            isCancelledLock.unlock()
        }
    }

    // MARK: - Progress Throttling

    /// Number of rows to process before updating UI
    let progressUpdateInterval: Int = 1_000
    /// Internal counter for processed rows (updated every row)
    var internalProcessedRows: Int = 0

    // MARK: - Dependencies

    let driver: DatabaseDriver
    let databaseType: DatabaseType

    // MARK: - Initialization

    init(driver: DatabaseDriver, databaseType: DatabaseType) {
        self.driver = driver
        self.databaseType = databaseType
    }

    // MARK: - Public API

    /// Cancel the current export operation
    func cancelExport() {
        isCancelled = true
    }

    /// Export selected tables to the specified URL
    /// - Parameters:
    ///   - tables: Array of table items to export (with SQL options for SQL format)
    ///   - config: Export configuration with format and options
    ///   - url: Destination file URL
    func export(
        tables: [ExportTableItem],
        config: ExportConfiguration,
        to url: URL
    ) async throws {
        guard !tables.isEmpty else {
            throw ExportError.noTablesSelected
        }

        // Reset state
        state = ExportState(isExporting: true, totalTables: tables.count)
        isCancelled = false
        internalProcessedRows = 0
        ddlFailures = []

        defer {
            state.isExporting = false
            isCancelled = false
            state.statusMessage = ""
        }

        // Fetch total row counts for all tables
        state.totalRows = await fetchTotalRowCount(for: tables)

        do {
            switch config.format {
            case .csv:
                try await exportToCSV(tables: tables, config: config, to: url)
            case .json:
                try await exportToJSON(tables: tables, config: config, to: url)
            case .sql:
                try await exportToSQL(tables: tables, config: config, to: url)
            case .xlsx:
                try await exportToXLSX(tables: tables, config: config, to: url)
            case .mql:
                try await exportToMQL(tables: tables, config: config, to: url)
            }
        } catch {
            // Clean up partial file on cancellation or error
            try? FileManager.default.removeItem(at: url)
            state.errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Fetch total row count for all tables.
    /// - Returns: The total row count across all tables. Any failures are logged but do not affect the returned value.
    /// - Note: When row count fails for some tables, the statusMessage is updated to inform the user that progress is estimated.
    private func fetchTotalRowCount(for tables: [ExportTableItem]) async -> Int {
        guard !tables.isEmpty else { return 0 }

        var total = 0
        var failedCount = 0

        if databaseType == .mongodb || databaseType == .redis {
            for table in tables {
                do {
                    if let count = try await driver.fetchApproximateRowCount(table: table.name) {
                        total += count
                    }
                } catch {
                    failedCount += 1
                    Self.logger.warning("Failed to get approximate row count for \(table.qualifiedName): \(error.localizedDescription)")
                }
            }
            if failedCount > 0 {
                Self.logger.warning("\(failedCount) table(s) failed row count - progress indicator may be inaccurate")
                state.statusMessage = "Progress estimated (\(failedCount) table\(failedCount > 1 ? "s" : "") could not be counted)"
            }
            return total
        }

        // Batch all COUNT(*) into a single UNION ALL query per chunk
        let chunkSize = 50

        for chunkStart in stride(from: 0, to: tables.count, by: chunkSize) {
            let end = min(chunkStart + chunkSize, tables.count)
            let batch = tables[chunkStart ..< end]

            let unionParts = batch.map { "SELECT COUNT(*) AS c FROM \(qualifiedTableRef(for: $0))" }
            let batchQuery = unionParts.joined(separator: " UNION ALL ")

            do {
                let result = try await driver.execute(query: batchQuery)
                for row in result.rows {
                    if let countStr = row.first, let count = Int(countStr ?? "0") {
                        total += count
                    }
                }
            } catch {
                for table in batch {
                    do {
                        let tableRef = qualifiedTableRef(for: table)
                        let result = try await driver.execute(query: "SELECT COUNT(*) FROM \(tableRef)")
                        if let countStr = result.rows.first?.first, let count = Int(countStr ?? "0") {
                            total += count
                        }
                    } catch {
                        failedCount += 1
                        Self.logger.warning("Failed to get row count for \(table.qualifiedName): \(error.localizedDescription)")
                    }
                }
            }
        }

        if failedCount > 0 {
            Self.logger.warning("\(failedCount) table(s) failed row count - progress indicator may be inaccurate")
            state.statusMessage = "Progress estimated (\(failedCount) table\(failedCount > 1 ? "s" : "") could not be counted)"
        }
        return total
    }

    /// Check if export was cancelled and throw if so
    func checkCancellation() throws {
        if isCancelled {
            throw NSError(
                domain: "ExportService",
                code: NSUserCancelledError,
                userInfo: [NSLocalizedDescriptionKey: "Export cancelled"]
            )
        }
    }

    /// Increment processed rows with throttled UI updates
    /// Only updates @Published properties every `progressUpdateInterval` rows
    /// Uses Task.yield() to allow UI to refresh
    func incrementProgress() async {
        internalProcessedRows += 1

        // Only update UI every N rows
        if internalProcessedRows % progressUpdateInterval == 0 {
            state.processedRows = internalProcessedRows
            if state.totalRows > 0 {
                state.progress = Double(internalProcessedRows) / Double(state.totalRows)
            }
            // Yield to allow UI to update
            await Task.yield()
        }
    }

    /// Finalize progress for current table (ensures UI shows final count)
    func finalizeTableProgress() async {
        state.processedRows = internalProcessedRows
        if state.totalRows > 0 {
            state.progress = Double(internalProcessedRows) / Double(state.totalRows)
        }
        // Yield to allow UI to update
        await Task.yield()
    }

    // MARK: - Helpers

    /// Build fully qualified and quoted table reference (database.table or just table)
    func qualifiedTableRef(for table: ExportTableItem) -> String {
        if table.databaseName.isEmpty {
            return databaseType.quoteIdentifier(table.name)
        } else {
            let quotedDb = databaseType.quoteIdentifier(table.databaseName)
            let quotedTable = databaseType.quoteIdentifier(table.name)
            return "\(quotedDb).\(quotedTable)"
        }
    }

    func fetchAllQuery(for table: ExportTableItem) -> String {
        switch databaseType {
        case .mongodb:
            let escaped = escapeJSIdentifier(table.name)
            if escaped.hasPrefix("[") {
                return "db\(escaped).find({})"
            }
            return "db.\(escaped).find({})"
        case .redis:
            return "SCAN 0 MATCH \"*\" COUNT 10000"
        default:
            return "SELECT * FROM \(qualifiedTableRef(for: table))"
        }
    }

    func fetchBatch(for table: ExportTableItem, offset: Int, limit: Int) async throws -> QueryResult {
        let query = fetchAllQuery(for: table)
        return try await driver.fetchRows(query: query, offset: offset, limit: limit)
    }

    /// Sanitize a name for use in SQL comments to prevent comment injection
    ///
    /// Removes characters that could break out of or nest SQL comments:
    /// - Newlines (could start new SQL statements)
    /// - Comment sequences (/* */ --)
    ///
    /// Logs a warning when the name is modified.
    func sanitizeForSQLComment(_ name: String) -> String {
        var result = name
        // Replace newlines with spaces
        result = result.replacingOccurrences(of: "\n", with: " ")
        result = result.replacingOccurrences(of: "\r", with: " ")
        // Remove comment sequences (both opening and closing)
        result = result.replacingOccurrences(of: "/*", with: "")
        result = result.replacingOccurrences(of: "*/", with: "")
        result = result.replacingOccurrences(of: "--", with: "")

        // Log when sanitization modifies the name
        if result != name {
            Self.logger.warning("Table name '\(name)' was sanitized to '\(result)' for SQL comment safety")
        }

        return result
    }

    // MARK: - File Helpers

    /// Create a file at the given URL and return a FileHandle for writing
    func createFileHandle(at url: URL) throws -> FileHandle {
        guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil) else {
            throw ExportError.fileWriteFailed(url.path(percentEncoded: false))
        }
        return try FileHandle(forWritingTo: url)
    }

    /// Close a file handle with error logging instead of silent suppression
    ///
    /// Used in defer blocks where we can't throw but want visibility into failures.
    func closeFileHandle(_ handle: FileHandle) {
        do {
            try handle.close()
        } catch {
            Self.logger.warning("Failed to close export file handle: \(error.localizedDescription)")
        }
    }

    func escapeJSONString(_ string: String) -> String {
        var utf8Result = [UInt8]()
        utf8Result.reserveCapacity(string.utf8.count)

        for byte in string.utf8 {
            switch byte {
            case 0x22: // "
                utf8Result.append(0x5C) // backslash
                utf8Result.append(0x22)
            case 0x5C: // backslash
                utf8Result.append(0x5C)
                utf8Result.append(0x5C)
            case 0x0A: // \n
                utf8Result.append(0x5C)
                utf8Result.append(0x6E) // n
            case 0x0D: // \r
                utf8Result.append(0x5C)
                utf8Result.append(0x72) // r
            case 0x09: // \t
                utf8Result.append(0x5C)
                utf8Result.append(0x74) // t
            case 0x08: // backspace
                utf8Result.append(0x5C)
                utf8Result.append(0x62) // b
            case 0x0C: // form feed
                utf8Result.append(0x5C)
                utf8Result.append(0x66) // f
            case 0x00...0x1F:
                // Other control characters: emit \uXXXX
                let hex = String(format: "\\u%04X", byte)
                utf8Result.append(contentsOf: hex.utf8)
            default:
                utf8Result.append(byte)
            }
        }

        return String(bytes: utf8Result, encoding: .utf8) ?? string
    }

    // MARK: - Compression

    func compressFileToFile(source: URL, destination: URL) async throws {
        // Run compression on background thread to avoid blocking main thread
        try await Task.detached(priority: .userInitiated) {
            // Pre-flight check: verify gzip is available
            let gzipPath = "/usr/bin/gzip"
            guard FileManager.default.isExecutableFile(atPath: gzipPath) else {
                throw ExportError.exportFailed(
                    "Compression unavailable: gzip not found at \(gzipPath). " +
                        "Please install gzip or disable compression in export options."
                )
            }

            // Create output file
            guard FileManager.default.createFile(atPath: destination.path(percentEncoded: false), contents: nil) else {
                throw ExportError.fileWriteFailed(destination.path(percentEncoded: false))
            }

            // Use gzip to compress the file
            let process = Process()
            process.executableURL = URL(fileURLWithPath: gzipPath)

            // Derive a sanitized, non-encoded filesystem path for the source
            let sanitizedSourcePath = source.standardizedFileURL.path(percentEncoded: false)

            // Basic validation to avoid passing obviously malformed paths to the process
            if sanitizedSourcePath.contains("\0") ||
                sanitizedSourcePath.contains(where: { $0.isNewline }) {
                throw ExportError.exportFailed("Invalid source path for compression")
            }

            process.arguments = ["-c", sanitizedSourcePath]
            let outputFile = try FileHandle(forWritingTo: destination)
            defer {
                try? outputFile.close()
            }
            process.standardOutput = outputFile

            // Capture stderr to provide detailed error messages on failure
            let errorPipe = Pipe()
            process.standardError = errorPipe

            // Safe: already inside Task.detached, so waitUntilExit() won't block MainActor
            try process.run()
            process.waitUntilExit()

            let status = process.terminationStatus
            guard status == 0 else {
                // Explicitly close the file handle before throwing to ensure
                // the destination file can be deleted in the error handler
                try? outputFile.close()

                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                let message: String
                if errorString.isEmpty {
                    message = "Compression failed with exit status \(status)"
                } else {
                    message = "Compression failed with exit status \(status): \(errorString)"
                }

                throw ExportError.exportFailed(message)
            }
        }.value
    }
}
