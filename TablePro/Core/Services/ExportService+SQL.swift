//
//  ExportService+SQL.swift
//  TablePro
//

import Foundation
import os

extension ExportService {
    func exportToSQL(
        tables: [ExportTableItem],
        config: ExportConfiguration,
        to url: URL
    ) async throws {
        // For gzip, write to temp file first then compress
        // For non-gzip, stream directly to destination
        let targetURL: URL
        let tempFileURL: URL?

        if config.sqlOptions.compressWithGzip {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".sql")
            tempFileURL = tempURL
            targetURL = tempURL
        } else {
            tempFileURL = nil
            targetURL = url
        }

        // Create file and get handle for streaming writes
        let fileHandle = try createFileHandle(at: targetURL)

        do {
            // Add header comment
            let dateFormatter = ISO8601DateFormatter()
            try fileHandle.write(contentsOf: "-- TablePro SQL Export\n".toUTF8Data())
            try fileHandle.write(contentsOf: "-- Generated: \(dateFormatter.string(from: Date()))\n".toUTF8Data())
            try fileHandle.write(contentsOf: "-- Database Type: \(databaseType.rawValue)\n\n".toUTF8Data())

            // Collect and emit dependent sequences and enum types (PostgreSQL) in batch
            var emittedSequenceNames: Set<String> = []
            var emittedTypeNames: Set<String> = []
            let structureTableNames = tables.filter { $0.sqlOptions.includeStructure }.map(\.name)

            var allSequences: [String: [(name: String, ddl: String)]] = [:]
            do {
                allSequences = try await driver.fetchAllDependentSequences(forTables: structureTableNames)
            } catch {
                Self.logger.warning("Failed to fetch dependent sequences: \(error.localizedDescription)")
            }

            var allEnumTypes: [String: [(name: String, labels: [String])]] = [:]
            do {
                allEnumTypes = try await driver.fetchAllDependentTypes(forTables: structureTableNames)
            } catch {
                Self.logger.warning("Failed to fetch dependent enum types: \(error.localizedDescription)")
            }

            for table in tables where table.sqlOptions.includeStructure {
                let sequences = allSequences[table.name] ?? []
                for seq in sequences where !emittedSequenceNames.contains(seq.name) {
                    emittedSequenceNames.insert(seq.name)
                    let quotedName = "\"\(seq.name.replacingOccurrences(of: "\"", with: "\"\""))\""
                    try fileHandle.write(contentsOf: "DROP SEQUENCE IF EXISTS \(quotedName) CASCADE;\n".toUTF8Data())
                    try fileHandle.write(contentsOf: "\(seq.ddl)\n\n".toUTF8Data())
                }

                let enumTypes = allEnumTypes[table.name] ?? []
                for enumType in enumTypes where !emittedTypeNames.contains(enumType.name) {
                    emittedTypeNames.insert(enumType.name)
                    let quotedName = "\"\(enumType.name.replacingOccurrences(of: "\"", with: "\"\""))\""
                    try fileHandle.write(contentsOf: "DROP TYPE IF EXISTS \(quotedName) CASCADE;\n".toUTF8Data())
                    let quotedLabels = enumType.labels.map { "'\(SQLEscaping.escapeStringLiteral($0, databaseType: databaseType))'" }
                    try fileHandle.write(contentsOf: "CREATE TYPE \(quotedName) AS ENUM (\(quotedLabels.joined(separator: ", ")));\n\n".toUTF8Data())
                }
            }

            for (index, table) in tables.enumerated() {
                try checkCancellation()

                state.currentTableIndex = index + 1
                state.currentTable = table.qualifiedName

                let sqlOptions = table.sqlOptions
                let tableRef = databaseType.quoteIdentifier(table.name)

                let sanitizedName = sanitizeForSQLComment(table.name)
                try fileHandle.write(contentsOf: "-- --------------------------------------------------------\n".toUTF8Data())
                try fileHandle.write(contentsOf: "-- Table: \(sanitizedName)\n".toUTF8Data())
                try fileHandle.write(contentsOf: "-- --------------------------------------------------------\n\n".toUTF8Data())

                // DROP statement
                if sqlOptions.includeDrop {
                    try fileHandle.write(contentsOf: "DROP TABLE IF EXISTS \(tableRef);\n\n".toUTF8Data())
                }

                // CREATE TABLE (structure)
                if sqlOptions.includeStructure {
                    do {
                        let ddl = try await driver.fetchTableDDL(table: table.name)
                        try fileHandle.write(contentsOf: ddl.toUTF8Data())
                        if !ddl.hasSuffix(";") {
                            try fileHandle.write(contentsOf: ";".toUTF8Data())
                        }
                        try fileHandle.write(contentsOf: "\n\n".toUTF8Data())
                    } catch {
                        // Track the failure for user notification
                        ddlFailures.append(sanitizedName)

                        // Use sanitizedName (already defined above) for safe comment output
                        let ddlWarning = "Warning: failed to fetch DDL for table \(sanitizedName): \(error)"
                        Self.logger.warning("Failed to fetch DDL for table \(sanitizedName): \(error)")
                        try fileHandle.write(contentsOf: "-- \(sanitizeForSQLComment(ddlWarning))\n\n".toUTF8Data())
                    }
                }

                // INSERT statements (data) - stream directly to file in batches
                if sqlOptions.includeData {
                    let batchSize = config.sqlOptions.batchSize
                    var offset = 0
                    var wroteAnyRows = false

                    while true {
                        try checkCancellation()
                        try Task.checkCancellation()

                        let query: String
                        switch databaseType {
                        case .oracle:
                            query = "SELECT * FROM \(tableRef) ORDER BY 1 OFFSET \(offset) ROWS FETCH NEXT \(batchSize) ROWS ONLY"
                        case .mssql:
                            query = "SELECT * FROM \(tableRef) ORDER BY (SELECT NULL) OFFSET \(offset) ROWS FETCH NEXT \(batchSize) ROWS ONLY"
                        default:
                            query = "SELECT * FROM \(tableRef) LIMIT \(batchSize) OFFSET \(offset)"
                        }
                        let result = try await driver.execute(query: query)

                        if result.rows.isEmpty {
                            break
                        }

                        try await writeInsertStatementsWithProgress(
                            table: table,
                            columns: result.columns,
                            rows: result.rows,
                            batchSize: batchSize,
                            to: fileHandle
                        )

                        wroteAnyRows = true
                        offset += batchSize
                    }

                    if wroteAnyRows {
                        try fileHandle.write(contentsOf: "\n".toUTF8Data())
                    }
                }
            }

            try fileHandle.close()
        } catch {
            closeFileHandle(fileHandle)
            if let tempURL = tempFileURL {
                try? FileManager.default.removeItem(at: tempURL)
            }
            throw error
        }

        // Handle gzip compression
        if config.sqlOptions.compressWithGzip, let tempURL = tempFileURL {
            state.statusMessage = "Compressing..."
            await Task.yield()

            do {
                defer {
                    // Always remove the temporary file, regardless of success or failure
                    try? FileManager.default.removeItem(at: tempURL)
                }

                try await compressFileToFile(source: tempURL, destination: url)
            } catch {
                // Remove the (possibly partially written) destination file on compression failure
                try? FileManager.default.removeItem(at: url)
                throw error
            }
        }

        // Surface DDL failures to user as a warning
        if !ddlFailures.isEmpty {
            let failedTables = ddlFailures.joined(separator: ", ")
            state.warningMessage = "Export completed with warnings: Could not fetch table structure for: \(failedTables)"
        }

        state.progress = 1.0
    }

    private func writeInsertStatementsWithProgress(
        table: ExportTableItem,
        columns: [String],
        rows: [[String?]],
        batchSize: Int,
        to fileHandle: FileHandle
    ) async throws {
        // Use unqualified table name for INSERT statements (schema-agnostic export)
        let tableRef = databaseType.quoteIdentifier(table.name)
        let quotedColumns = columns
            .map { databaseType.quoteIdentifier($0) }
            .joined(separator: ", ")

        let insertPrefix = "INSERT INTO \(tableRef) (\(quotedColumns)) VALUES\n"

        // Effective batch size (<=1 means no batching, one row per INSERT)
        let effectiveBatchSize = batchSize <= 1 ? 1 : batchSize
        var valuesBatch: [String] = []
        valuesBatch.reserveCapacity(effectiveBatchSize)

        for row in rows {
            try checkCancellation()

            let values = row.map { value -> String in
                guard let val = value else { return "NULL" }
                // Use proper SQL escaping to prevent injection (handles backslashes, quotes, etc.)
                let escaped = SQLEscaping.escapeStringLiteral(val, databaseType: databaseType)
                return "'\(escaped)'"
            }.joined(separator: ", ")

            valuesBatch.append("  (\(values))")

            // Write batch when full
            if valuesBatch.count >= effectiveBatchSize {
                let statement = insertPrefix + valuesBatch.joined(separator: ",\n") + ";\n\n"
                try fileHandle.write(contentsOf: statement.toUTF8Data())
                valuesBatch.removeAll(keepingCapacity: true)
            }

            // Update progress (throttled)
            await incrementProgress()
        }

        // Write remaining rows in final batch
        if !valuesBatch.isEmpty {
            let statement = insertPrefix + valuesBatch.joined(separator: ",\n") + ";\n\n"
            try fileHandle.write(contentsOf: statement.toUTF8Data())
        }

        // Ensure final count is shown
        await finalizeTableProgress()
    }
}
