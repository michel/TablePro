//
//  ExportService+CSV.swift
//  TablePro
//

import Foundation

extension ExportService {
    func exportToCSV(
        tables: [ExportTableItem],
        config: ExportConfiguration,
        to url: URL
    ) async throws {
        // Create file and get handle for streaming writes
        let fileHandle = try createFileHandle(at: url)
        defer { closeFileHandle(fileHandle) }

        let lineBreak = config.csvOptions.lineBreak.value

        for (index, table) in tables.enumerated() {
            try checkCancellation()

            state.currentTableIndex = index + 1
            state.currentTable = table.qualifiedName

            // Add table header comment if multiple tables
            // Sanitize name to prevent newlines from breaking the comment line
            if tables.count > 1 {
                let sanitizedName = sanitizeForSQLComment(table.qualifiedName)
                try fileHandle.write(contentsOf: "# Table: \(sanitizedName)\n".toUTF8Data())
            }

            let batchSize = 10_000
            var offset = 0
            var isFirstBatch = true

            while true {
                try checkCancellation()
                try Task.checkCancellation()

                let result = try await fetchBatch(for: table, offset: offset, limit: batchSize)

                // No more rows to process
                if result.rows.isEmpty {
                    break
                }

                // Stream CSV content for this batch directly to file
                // Only include headers on the first batch to avoid duplication
                var batchOptions = config.csvOptions
                if !isFirstBatch {
                    batchOptions.includeFieldNames = false
                }

                try await writeCSVContentWithProgress(
                    columns: result.columns,
                    rows: result.rows,
                    options: batchOptions,
                    to: fileHandle
                )

                isFirstBatch = false
                offset += batchSize
            }
            if index < tables.count - 1 {
                try fileHandle.write(contentsOf: "\(lineBreak)\(lineBreak)".toUTF8Data())
            }
        }

        try checkCancellation()
        state.progress = 1.0
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
            try fileHandle.write(contentsOf: (headerLine + lineBreak).toUTF8Data())
        }

        // Data rows with progress tracking - stream directly to file
        for row in rows {
            try checkCancellation()

            let rowLine = row.map { value -> String in
                guard let val = value else {
                    return options.convertNullToEmpty ? "" : "NULL"
                }

                var processed = val

                // Check for line breaks BEFORE converting them (for quote detection)
                let hadLineBreaks = val.contains("\n") || val.contains("\r")

                // Convert line breaks to space
                if options.convertLineBreakToSpace {
                    processed = processed
                        .replacingOccurrences(of: "\r\n", with: " ")
                        .replacingOccurrences(of: "\r", with: " ")
                        .replacingOccurrences(of: "\n", with: " ")
                }

                // Handle decimal format
                if options.decimalFormat == .comma {
                    let range = NSRange(processed.startIndex..., in: processed)
                    if Self.decimalFormatRegex.firstMatch(in: processed, range: range) != nil {
                        processed = processed.replacingOccurrences(of: ".", with: ",")
                    }
                }

                return escapeCSVField(processed, options: options, originalHadLineBreaks: hadLineBreaks)
            }.joined(separator: delimiter)

            // Write row directly to file
            try fileHandle.write(contentsOf: (rowLine + lineBreak).toUTF8Data())

            // Update progress (throttled)
            await incrementProgress()
        }

        // Ensure final count is shown
        await finalizeTableProgress()
    }

    private func escapeCSVField(_ field: String, options: CSVExportOptions, originalHadLineBreaks: Bool = false) -> String {
        var processed = field

        // Sanitize formula-like prefixes to prevent CSV formula injection
        // Values starting with these characters can be executed as formulas in Excel/LibreOffice
        if options.sanitizeFormulas {
            let dangerousPrefixes: [Character] = ["=", "+", "-", "@", "\t", "\r"]
            if let first = processed.first, dangerousPrefixes.contains(first) {
                // Prefix with single quote - Excel/LibreOffice treats this as text
                processed = "'" + processed
            }
        }

        switch options.quoteHandling {
        case .always:
            let escaped = processed.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        case .never:
            return processed
        case .asNeeded:
            // Check current content for special characters, OR if original had line breaks
            // (important when convertLineBreakToSpace is enabled - original line breaks
            // mean the field should still be quoted even after conversion to spaces)
            let needsQuotes = processed.contains(options.delimiter.actualValue) ||
                processed.contains("\"") ||
                processed.contains("\n") ||
                processed.contains("\r") ||
                originalHadLineBreaks
            if needsQuotes {
                let escaped = processed.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            return processed
        }
    }
}
