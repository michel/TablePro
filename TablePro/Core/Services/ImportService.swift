//
//  ImportService.swift
//  TablePro
//
//  Service responsible for importing SQL files with transaction support
//  and foreign key handling.
//

import Combine
import Foundation

// MARK: - Import Service

/// Service responsible for importing SQL files
@MainActor
final class ImportService: ObservableObject {

    // MARK: - Published State

    @Published var isImporting: Bool = false
    @Published var progress: Double = 0.0
    @Published var currentStatement: String = ""
    @Published var currentStatementIndex: Int = 0
    @Published var totalStatements: Int = 0
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
            defer { isCancelledLock.unlock() }
            _isCancelled = newValue
        }
    }

    func cancelImport() {
        isCancelled = true
    }

    // MARK: - Dependencies

    private let connection: DatabaseConnection
    private let parser = SQLFileParser()

    // MARK: - Initialization

    init(connection: DatabaseConnection) {
        self.connection = connection
    }

    // MARK: - Public API

    /// Import SQL file
    /// - Parameters:
    ///   - url: File URL to import
    ///   - config: Import configuration
    /// - Returns: Import result with execution summary
    func importSQL(
        from url: URL,
        config: ImportConfiguration
    ) async throws -> ImportResult {
        isImporting = true
        isCancelled = false
        progress = 0.0
        currentStatementIndex = 0
        errorMessage = nil

        defer {
            isImporting = false
        }

        // 1. Decompress .gz if needed
        let fileURL = try await decompressIfNeeded(url)
        let needsCleanup = fileURL != url
        defer {
            if needsCleanup {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }

        // 2. Count statements for progress
        statusMessage = "Analyzing file..."
        totalStatements = try await parser.countStatements(url: fileURL, encoding: config.encoding)
        statusMessage = ""

        // Check if file is empty
        guard totalStatements > 0 else {
            throw ImportError.fileReadFailed("File contains no SQL statements")
        }

        // 3. Get database driver
        guard let driver = DatabaseManager.shared.activeDriver else {
            throw DatabaseError.notConnected
        }

        let startTime = Date()
        var executedCount = 0
        var failedStatement: String?
        var failedLine: Int?

        do {
            // 4. Disable FK checks (if enabled) - BEFORE transaction
            if config.disableForeignKeyChecks {
                let fkDisableStmts = fkDisableStatements(for: connection.type)
                for stmt in fkDisableStmts {
                    _ = try await driver.execute(query: stmt)
                }
            }

            // 5. Begin transaction (if enabled)
            if config.wrapInTransaction {
                _ = try await driver.execute(query: "BEGIN")
            }

            // 6. Parse and execute statements
            // NOTE:
            // This call may re-parse the file after a prior pass that counted
            // the total number of statements for progress reporting. For large
            // files this can roughly double the I/O and parsing overhead.
            //
            // This is currently an intentional tradeoff in favor of providing
            // an accurate, determinate progress value (executedCount /
            // totalStatements) to the UI. If import performance for very large
            // files becomes an issue, consider:
            //   - Removing the initial counting pass and using an indeterminate
            //     progress indicator instead, or
            //   - Parsing once and caching the statements, at the cost of
            //     additional memory usage.
            let stream = try await parser.parseFile(url: fileURL, encoding: config.encoding)

            for try await (statement, lineNumber) in stream {
                try checkCancellation()

                currentStatement = String(statement.prefix(50))
                currentStatementIndex = executedCount + 1

                let statementStartTime = Date()

                do {
                    _ = try await driver.execute(query: statement)

                    let executionTime = Date().timeIntervalSince(statementStartTime)

                    // Record to history
                    QueryHistoryManager.shared.recordQuery(
                        query: statement,
                        connectionId: connection.id,
                        databaseName: connection.database ?? "",
                        executionTime: executionTime,
                        rowCount: 0,
                        wasSuccessful: true,
                        errorMessage: nil
                    )

                    executedCount += 1
                    progress = Double(executedCount) / Double(totalStatements)

                } catch {
                    // Statement execution failed
                    failedStatement = statement
                    failedLine = lineNumber

                    // Record failed query to history
                    QueryHistoryManager.shared.recordQuery(
                        query: statement,
                        connectionId: connection.id,
                        databaseName: connection.database ?? "",
                        executionTime: 0,
                        rowCount: 0,
                        wasSuccessful: false,
                        errorMessage: error.localizedDescription
                    )

                    throw ImportError.importFailed(
                        statement: statement,
                        line: lineNumber,
                        error: error.localizedDescription
                    )
                }
            }

            // 7. Commit transaction (if enabled)
            if config.wrapInTransaction {
                _ = try await driver.execute(query: "COMMIT")
            }

            // 8. Re-enable FK checks (if enabled) - AFTER transaction
            if config.disableForeignKeyChecks {
                let fkEnableStmts = fkEnableStatements(for: connection.type)
                for stmt in fkEnableStmts {
                    _ = try await driver.execute(query: stmt)
                }
            }

        } catch {
            // Rollback on error
            if config.wrapInTransaction {
                try? await driver.execute(query: "ROLLBACK")
            }

            // Re-enable FK checks on error
            if config.disableForeignKeyChecks {
                let fkEnableStmts = fkEnableStatements(for: connection.type)
                for stmt in fkEnableStmts {
                    try? await driver.execute(query: stmt)
                }
            }

            throw error
        }

        let executionTime = Date().timeIntervalSince(startTime)

        return ImportResult(
            totalStatements: totalStatements,
            executedStatements: executedCount,
            failedStatement: failedStatement,
            failedLine: failedLine,
            executionTime: executionTime
        )
    }

    // MARK: - Private Helpers

    /// Returns a filesystem path string for the given URL, using the
    /// preferred `URL.path()` API on macOS 13+ and falling back to
    /// the legacy `path` property on earlier versions.
    private func fileSystemPath(for url: URL) -> String {
        if #available(macOS 13.0, *) {
            return url.path()
        } else {
            return url.path
        }
    }

    private func decompressIfNeeded(_ url: URL) async throws -> URL {
        guard url.pathExtension == "gz" else { return url }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sql")

        // Derive the filesystem path once and pass it into the detached task.
        let filePath = fileSystemPath(for: url)

        return try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
            process.arguments = ["-c", filePath]

            let fileManager = FileManager.default
            guard fileManager.createFile(atPath: tempURL.path, contents: nil, attributes: nil) else {
                throw ImportError.decompressFailed
            }
            let outputFile = try FileHandle(forWritingTo: tempURL)
            defer { try? outputFile.close() }

            process.standardOutput = outputFile

            let errorPipe = Pipe()
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw ImportError.decompressFailed
            }

            return tempURL
        }.value
    }

    private func checkCancellation() throws {
        if isCancelled {
            throw ImportError.cancelled
        }
    }

    private func fkDisableStatements(for dbType: DatabaseType) -> [String] {
        switch dbType {
        case .mysql, .mariadb:
            return ["SET FOREIGN_KEY_CHECKS=0"]
        case .postgresql:
            // PostgreSQL doesn't support globally disabling non-deferrable FKs.
            return []
        case .sqlite:
            return ["PRAGMA foreign_keys = OFF"]
        }
    }

    private func fkEnableStatements(for dbType: DatabaseType) -> [String] {
        switch dbType {
        case .mysql, .mariadb:
            return ["SET FOREIGN_KEY_CHECKS=1"]
        case .postgresql:
            return []
        case .sqlite:
            return ["PRAGMA foreign_keys = ON"]
        }
    }
}
