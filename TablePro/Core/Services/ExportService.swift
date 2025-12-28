//
//  ExportService.swift
//  TablePro
//
//  Service responsible for exporting table data to CSV, JSON, and SQL formats.
//  Supports configurable options for each format including compression.
//

import Combine
import Compression
import Foundation

// MARK: - Export Error

/// Errors that can occur during export operations
enum ExportError: LocalizedError {
    case notConnected
    case noTablesSelected
    case exportFailed(String)
    case compressionFailed
    case fileWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to database"
        case .noTablesSelected:
            return "No tables selected for export"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        case .compressionFailed:
            return "Failed to compress data"
        case .fileWriteFailed(let path):
            return "Failed to write file: \(path)"
        }
    }
}

// MARK: - Export Service

/// Service responsible for exporting table data to various formats
@MainActor
final class ExportService: ObservableObject {

    // MARK: - Published State

    @Published var isExporting: Bool = false
    @Published var progress: Double = 0.0
    @Published var currentTable: String = ""
    @Published var currentTableIndex: Int = 0
    @Published var totalTables: Int = 0
    @Published var processedRows: Int = 0
    @Published var totalRows: Int = 0
    @Published var statusMessage: String = ""
    @Published var errorMessage: String?

    // MARK: - Cancellation

    private let isCancelledLock = NSLock()
    private var _isCancelled: Bool = false
    private var isCancelled: Bool {
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
    private let progressUpdateInterval: Int = 1000
    /// Internal counter for processed rows (updated every row)
    private var internalProcessedRows: Int = 0

    // MARK: - Dependencies

    private let driver: DatabaseDriver
    private let databaseType: DatabaseType

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
        isExporting = true
        isCancelled = false
        progress = 0.0
        processedRows = 0
        internalProcessedRows = 0
        totalRows = 0
        totalTables = tables.count
        currentTableIndex = 0
        statusMessage = ""
        errorMessage = nil

        defer {
            isExporting = false
            isCancelled = false
            statusMessage = ""
        }

        // Fetch total row counts for all tables
        totalRows = await fetchTotalRowCount(for: tables)

        do {
            switch config.format {
            case .csv:
                try await exportToCSV(tables: tables, config: config, to: url)
            case .json:
                try await exportToJSON(tables: tables, config: config, to: url)
            case .sql:
                try await exportToSQL(tables: tables, config: config, to: url)
            }
        } catch {
            // Clean up partial file on cancellation or error
            try? FileManager.default.removeItem(at: url)
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Fetch total row count for all tables
    private func fetchTotalRowCount(for tables: [ExportTableItem]) async -> Int {
        var total = 0
        for table in tables {
            let tableRef = qualifiedTableRef(for: table)
            do {
                let result = try await driver.execute(query: "SELECT COUNT(*) FROM \(tableRef)")
                if let countStr = result.rows.first?.first, let count = Int(countStr ?? "0") {
                    total += count
                }
            } catch {
                // If count fails, estimate based on 0 (progress will be less accurate)
            }
        }
        return total
    }

    /// Check if export was cancelled and throw if so
    private func checkCancellation() throws {
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
    private func incrementProgress() async {
        internalProcessedRows += 1

        // Only update UI every N rows
        if internalProcessedRows % progressUpdateInterval == 0 {
            processedRows = internalProcessedRows
            if totalRows > 0 {
                progress = Double(internalProcessedRows) / Double(totalRows)
            }
            // Yield to allow UI to update
            await Task.yield()
        }
    }

    /// Finalize progress for current table (ensures UI shows final count)
    private func finalizeTableProgress() async {
        processedRows = internalProcessedRows
        if totalRows > 0 {
            progress = Double(internalProcessedRows) / Double(totalRows)
        }
        // Yield to allow UI to update
        await Task.yield()
    }

    // MARK: - Helpers

    /// Build fully qualified and quoted table reference (database.table or just table)
    private func qualifiedTableRef(for table: ExportTableItem) -> String {
        if table.databaseName.isEmpty {
            return databaseType.quoteIdentifier(table.name)
        } else {
            let quotedDb = databaseType.quoteIdentifier(table.databaseName)
            let quotedTable = databaseType.quoteIdentifier(table.name)
            return "\(quotedDb).\(quotedTable)"
        }
    }

    // MARK: - CSV Export

    private func exportToCSV(
        tables: [ExportTableItem],
        config: ExportConfiguration,
        to url: URL
    ) async throws {
        // Create file and get handle for streaming writes
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: url)
        defer { try? fileHandle.close() }

        let lineBreak = config.csvOptions.lineBreak.value

        for (index, table) in tables.enumerated() {
            try checkCancellation()

            currentTableIndex = index + 1
            currentTable = table.qualifiedName

            // Add table header comment if multiple tables
            if tables.count > 1 {
                try fileHandle.write(contentsOf: "# Table: \(table.qualifiedName)\n".data(using: .utf8)!)
            }

            // Fetch all data from table
            let tableRef = qualifiedTableRef(for: table)
            let result = try await driver.execute(query: "SELECT * FROM \(tableRef)")

            // Stream CSV content directly to file
            try await writeCSVContentWithProgress(
                columns: result.columns,
                rows: result.rows,
                options: config.csvOptions,
                to: fileHandle
            )

            if index < tables.count - 1 {
                try fileHandle.write(contentsOf: "\(lineBreak)\(lineBreak)".data(using: .utf8)!)
            }
        }

        try checkCancellation()
        progress = 1.0
    }

    private func writeCSVContentWithProgress(
        columns: [String],
        rows: [[String?]],
        options: CSVExportOptions,
        to fileHandle: FileHandle
    ) async throws {
        let delimiter = options.delimiter.actualValue
        let lineBreak = options.lineBreak.value

        // Header row
        if options.includeFieldNames {
            let headerLine = columns
                .map { escapeCSVField($0, options: options) }
                .joined(separator: delimiter)
            try fileHandle.write(contentsOf: (headerLine + lineBreak).data(using: .utf8)!)
        }

        // Data rows with progress tracking - stream directly to file
        for row in rows {
            try checkCancellation()

            let rowLine = row.map { value -> String in
                guard let val = value else {
                    return options.convertNullToEmpty ? "" : "NULL"
                }

                var processed = val

                // Convert line breaks to space
                if options.convertLineBreakToSpace {
                    processed = processed
                        .replacingOccurrences(of: "\r\n", with: " ")
                        .replacingOccurrences(of: "\r", with: " ")
                        .replacingOccurrences(of: "\n", with: " ")
                }

                // Handle decimal format
                if options.decimalFormat == .comma,
                   Double(processed) != nil {
                    processed = processed.replacingOccurrences(of: ".", with: ",")
                }

                return escapeCSVField(processed, options: options)
            }.joined(separator: delimiter)

            // Write row directly to file
            try fileHandle.write(contentsOf: (rowLine + lineBreak).data(using: .utf8)!)

            // Update progress (throttled)
            await incrementProgress()
        }

        // Ensure final count is shown
        await finalizeTableProgress()
    }

    private func escapeCSVField(_ field: String, options: CSVExportOptions) -> String {
        switch options.quoteHandling {
        case .always:
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        case .never:
            return field
        case .asNeeded:
            let needsQuotes = field.contains(options.delimiter.actualValue) ||
                              field.contains("\"") ||
                              field.contains("\n") ||
                              field.contains("\r")
            if needsQuotes {
                let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            return field
        }
    }

    // MARK: - JSON Export

    private func exportToJSON(
        tables: [ExportTableItem],
        config: ExportConfiguration,
        to url: URL
    ) async throws {
        var exportData: [String: [[String: Any]]] = [:]

        for (index, table) in tables.enumerated() {
            try checkCancellation()

            currentTableIndex = index + 1
            currentTable = table.qualifiedName

            let tableRef = qualifiedTableRef(for: table)
            let result = try await driver.execute(query: "SELECT * FROM \(tableRef)")

            var tableData: [[String: Any]] = []
            for row in result.rows {
                try checkCancellation()

                var rowDict: [String: Any] = [:]
                for (colIndex, column) in result.columns.enumerated() {
                    if colIndex < row.count {
                        let value = row[colIndex]
                        if config.jsonOptions.includeNullValues || value != nil {
                            rowDict[column] = value ?? NSNull()
                        }
                    }
                }
                tableData.append(rowDict)

                // Update progress (throttled)
                await incrementProgress()
            }

            // Ensure final count is shown for this table
            await finalizeTableProgress()

            exportData[table.qualifiedName] = tableData
        }

        try checkCancellation()

        let options: JSONSerialization.WritingOptions = config.jsonOptions.prettyPrint
            ? [.prettyPrinted, .sortedKeys]
            : [.sortedKeys]

        let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: options)
        try jsonData.write(to: url)
        progress = 1.0
    }

    // MARK: - SQL Export

    private func exportToSQL(
        tables: [ExportTableItem],
        config: ExportConfiguration,
        to url: URL
    ) async throws {
        // For gzip, write to temp file first then compress
        // For non-gzip, stream directly to destination
        let targetURL: URL
        let tempFileURL: URL?

        if config.sqlOptions.compressWithGzip {
            tempFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".sql")
            targetURL = tempFileURL!
        } else {
            tempFileURL = nil
            targetURL = url
        }

        // Create file and get handle for streaming writes
        FileManager.default.createFile(atPath: targetURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: targetURL)

        do {
            // Add header comment
            let dateFormatter = ISO8601DateFormatter()
            try fileHandle.write(contentsOf: "-- TablePro SQL Export\n".data(using: .utf8)!)
            try fileHandle.write(contentsOf: "-- Generated: \(dateFormatter.string(from: Date()))\n".data(using: .utf8)!)
            try fileHandle.write(contentsOf: "-- Database Type: \(databaseType.rawValue)\n\n".data(using: .utf8)!)

            for (index, table) in tables.enumerated() {
                try checkCancellation()

                currentTableIndex = index + 1
                currentTable = table.qualifiedName

                let sqlOptions = table.sqlOptions
                let tableRef = qualifiedTableRef(for: table)

                try fileHandle.write(contentsOf: "-- --------------------------------------------------------\n".data(using: .utf8)!)
                try fileHandle.write(contentsOf: "-- Table: \(table.qualifiedName)\n".data(using: .utf8)!)
                try fileHandle.write(contentsOf: "-- --------------------------------------------------------\n\n".data(using: .utf8)!)

                // DROP statement
                if sqlOptions.includeDrop {
                    try fileHandle.write(contentsOf: "DROP TABLE IF EXISTS \(tableRef);\n\n".data(using: .utf8)!)
                }

                // CREATE TABLE (structure)
                if sqlOptions.includeStructure {
                    let ddl = try await driver.fetchTableDDL(table: tableRef)
                    try fileHandle.write(contentsOf: ddl.data(using: .utf8)!)
                    if !ddl.hasSuffix(";") {
                        try fileHandle.write(contentsOf: ";".data(using: .utf8)!)
                    }
                    try fileHandle.write(contentsOf: "\n\n".data(using: .utf8)!)
                }

                // INSERT statements (data) - stream directly to file
                if sqlOptions.includeData {
                    let result = try await driver.execute(query: "SELECT * FROM \(tableRef)")

                    if !result.rows.isEmpty {
                        try await writeInsertStatementsWithProgress(
                            table: table,
                            columns: result.columns,
                            rows: result.rows,
                            to: fileHandle
                        )
                        try fileHandle.write(contentsOf: "\n".data(using: .utf8)!)
                    }
                }
            }

            try fileHandle.close()
        } catch {
            try? fileHandle.close()
            if let tempURL = tempFileURL {
                try? FileManager.default.removeItem(at: tempURL)
            }
            throw error
        }

        try checkCancellation()

        // Handle gzip compression
        if config.sqlOptions.compressWithGzip, let tempURL = tempFileURL {
            statusMessage = "Compressing..."
            await Task.yield()

            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            try await compressFileToFile(source: tempURL, destination: url)
        }

        progress = 1.0
    }

    private func writeInsertStatementsWithProgress(
        table: ExportTableItem,
        columns: [String],
        rows: [[String?]],
        to fileHandle: FileHandle
    ) async throws {
        let tableRef = qualifiedTableRef(for: table)
        let quotedColumns = columns
            .map { databaseType.quoteIdentifier($0) }
            .joined(separator: ", ")

        for row in rows {
            try checkCancellation()

            let values = row.map { value -> String in
                guard let val = value else { return "NULL" }
                // Escape single quotes by doubling them
                let escaped = val.replacingOccurrences(of: "'", with: "''")
                return "'\(escaped)'"
            }.joined(separator: ", ")

            let statement = "INSERT INTO \(tableRef) (\(quotedColumns)) VALUES (\(values));\n"
            try fileHandle.write(contentsOf: statement.data(using: .utf8)!)

            // Update progress (throttled)
            await incrementProgress()
        }

        // Ensure final count is shown
        await finalizeTableProgress()
    }

    // MARK: - Compression

    private func compressFileToFile(source: URL, destination: URL) async throws {
        // Run compression on background thread to avoid blocking main thread
        try await Task.detached(priority: .userInitiated) {
            // Use gzip to compress the file
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
            process.arguments = ["-c", source.path]

            let outputFile = try FileHandle(forWritingTo: {
                FileManager.default.createFile(atPath: destination.path, contents: nil)
                return destination
            }())
            process.standardOutput = outputFile

            try process.run()
            process.waitUntilExit()
            try outputFile.close()

            guard process.terminationStatus == 0 else {
                throw ExportError.compressionFailed
            }
        }.value
    }
}
