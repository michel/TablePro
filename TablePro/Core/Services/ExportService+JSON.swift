//
//  ExportService+JSON.swift
//  TablePro
//

import Foundation

extension ExportService {
    func exportToJSON(
        tables: [ExportTableItem],
        config: ExportConfiguration,
        to url: URL
    ) async throws {
        // Stream JSON directly to file to minimize memory usage
        let fileHandle = try createFileHandle(at: url)
        defer { closeFileHandle(fileHandle) }

        let prettyPrint = config.jsonOptions.prettyPrint
        let indent = prettyPrint ? "  " : ""
        let newline = prettyPrint ? "\n" : ""

        // Opening brace
        try fileHandle.write(contentsOf: "{\(newline)".toUTF8Data())

        for (tableIndex, table) in tables.enumerated() {
            try checkCancellation()

            state.currentTableIndex = tableIndex + 1
            state.currentTable = table.qualifiedName

            // Write table key and opening bracket
            let escapedTableName = escapeJSONString(table.qualifiedName)
            try fileHandle.write(contentsOf: "\(indent)\"\(escapedTableName)\": [\(newline)".toUTF8Data())

            let batchSize = 1_000
            var offset = 0
            var hasWrittenRow = false
            var columns: [String]?

            batchLoop: while true {
                try checkCancellation()
                try Task.checkCancellation()

                let result = try await fetchBatch(for: table, offset: offset, limit: batchSize)

                if result.rows.isEmpty {
                    break batchLoop
                }

                if columns == nil {
                    columns = result.columns
                }

                for row in result.rows {
                    try checkCancellation()

                    // Buffer entire row into a String, then write once (SVC-10)
                    let rowPrefix = prettyPrint ? "\(indent)\(indent)" : ""
                    var rowString = ""

                    // Comma/newline before every row except the first
                    if hasWrittenRow {
                        rowString += ",\(newline)"
                    }

                    // Row prefix and opening brace
                    rowString += rowPrefix
                    rowString += "{"

                    if let columns = columns {
                        var isFirstField = true
                        for (colIndex, column) in columns.enumerated() {
                            if colIndex < row.count {
                                let value = row[colIndex]
                                if config.jsonOptions.includeNullValues || value != nil {
                                    if !isFirstField {
                                        rowString += ", "
                                    }
                                    isFirstField = false

                                    let escapedKey = escapeJSONString(column)
                                    let jsonValue = formatJSONValue(
                                        value,
                                        preserveAsString: config.jsonOptions.preserveAllAsStrings
                                    )
                                    rowString += "\"\(escapedKey)\": \(jsonValue)"
                                }
                            }
                        }
                    }

                    // Close row object
                    rowString += "}"

                    // Single write per row instead of per field
                    try fileHandle.write(contentsOf: rowString.toUTF8Data())

                    hasWrittenRow = true

                    // Update progress (throttled)
                    await incrementProgress()
                }

                offset += result.rows.count
            }

            // Ensure final count is shown for this table
            await finalizeTableProgress()

            // Close array
            if hasWrittenRow {
                try fileHandle.write(contentsOf: newline.toUTF8Data())
            }
            let tableSuffix = tableIndex < tables.count - 1 ? ",\(newline)" : newline
            try fileHandle.write(contentsOf: "\(indent)]\(tableSuffix)".toUTF8Data())
        }

        // Closing brace
        try fileHandle.write(contentsOf: "}".toUTF8Data())

        try checkCancellation()
        state.progress = 1.0
    }

    private func formatJSONValue(_ value: String?, preserveAsString: Bool) -> String {
        guard let val = value else { return "null" }

        // If preserving all as strings, skip type detection
        if preserveAsString {
            return "\"\(escapeJSONString(val))\""
        }

        // Try to detect numbers and booleans
        // Note: Large integers (> 2^53-1) may lose precision in JavaScript consumers
        if let intVal = Int(val) {
            return String(intVal)
        }
        if let doubleVal = Double(val), !val.contains("e") && !val.contains("E") {
            // Avoid scientific notation issues
            let jsMaxSafeInteger = 9_007_199_254_740_991.0 // 2^53 - 1, JavaScript's Number.MAX_SAFE_INTEGER

            if doubleVal.truncatingRemainder(dividingBy: 1) == 0 && !val.contains(".") {
                // For integral values, only convert to Int when within both Int and JS safe integer bounds
                if abs(doubleVal) <= jsMaxSafeInteger,
                   doubleVal >= Double(Int.min),
                   doubleVal <= Double(Int.max) {
                    return String(Int(doubleVal))
                } else {
                    // Preserve original integral representation to avoid scientific notation / precision changes
                    return val
                }
            }
            return String(doubleVal)
        }
        if val.lowercased() == "true" || val.lowercased() == "false" {
            return val.lowercased()
        }

        // String value - escape and quote
        return "\"\(escapeJSONString(val))\""
    }
}
