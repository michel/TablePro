//
//  ExportService+MQL.swift
//  TablePro
//

import Foundation

extension ExportService {
    func exportToMQL(
        tables: [ExportTableItem],
        config: ExportConfiguration,
        to url: URL
    ) async throws {
        let fileHandle = try createFileHandle(at: url)
        defer { closeFileHandle(fileHandle) }

        let dateFormatter = ISO8601DateFormatter()
        try fileHandle.write(contentsOf: "// TablePro MQL Export\n".toUTF8Data())
        try fileHandle.write(contentsOf: "// Generated: \(dateFormatter.string(from: Date()))\n".toUTF8Data())

        let dbName = tables.first?.databaseName ?? ""
        if !dbName.isEmpty {
            try fileHandle.write(contentsOf: "// Database: \(sanitizeForSQLComment(dbName))\n".toUTF8Data())
        }
        try fileHandle.write(contentsOf: "\n".toUTF8Data())

        let batchSize = config.mqlOptions.batchSize

        for (index, table) in tables.enumerated() {
            try checkCancellation()

            state.currentTableIndex = index + 1
            state.currentTable = table.qualifiedName

            let mqlOpts = table.mqlOptions
            let escapedCollection = escapeJSIdentifier(table.name)
            let collectionAccessor: String
            if escapedCollection.hasPrefix("[") {
                collectionAccessor = "db\(escapedCollection)"
            } else {
                collectionAccessor = "db.\(escapedCollection)"
            }

            try fileHandle.write(contentsOf: "// Collection: \(sanitizeForSQLComment(table.name))\n".toUTF8Data())

            if mqlOpts.includeDrop {
                try fileHandle.write(contentsOf: "\(collectionAccessor).drop();\n".toUTF8Data())
            }

            if mqlOpts.includeData {
                let fetchBatchSize = 5_000
                var offset = 0
                var columns: [String] = []
                var documentBatch: [String] = []

                while true {
                    try checkCancellation()
                    try Task.checkCancellation()

                    let result = try await fetchBatch(for: table, offset: offset, limit: fetchBatchSize)

                    if result.rows.isEmpty { break }

                    if columns.isEmpty {
                        columns = result.columns
                    }

                    for row in result.rows {
                        try checkCancellation()

                        var fields: [String] = []
                        for (colIndex, column) in columns.enumerated() {
                            guard colIndex < row.count else { continue }
                            guard let value = row[colIndex] else { continue }
                            let jsonValue = mqlJsonValue(for: value)
                            fields.append("\"\(escapeJSONString(column))\": \(jsonValue)")
                        }
                        documentBatch.append("  {\(fields.joined(separator: ", "))}")

                        if documentBatch.count >= batchSize {
                            try writeMQLInsertMany(
                                collection: table.name,
                                documents: documentBatch,
                                to: fileHandle
                            )
                            documentBatch.removeAll(keepingCapacity: true)
                        }

                        await incrementProgress()
                    }

                    offset += fetchBatchSize
                }

                if !documentBatch.isEmpty {
                    try writeMQLInsertMany(
                        collection: table.name,
                        documents: documentBatch,
                        to: fileHandle
                    )
                }
            }

            // Indexes after data for performance
            if mqlOpts.includeIndexes {
                try await writeMQLIndexes(
                    collection: table.name,
                    collectionAccessor: collectionAccessor,
                    to: fileHandle
                )
            }

            await finalizeTableProgress()

            if index < tables.count - 1 {
                try fileHandle.write(contentsOf: "\n".toUTF8Data())
            }
        }

        try checkCancellation()
        state.progress = 1.0
    }

    private func writeMQLInsertMany(
        collection: String,
        documents: [String],
        to fileHandle: FileHandle
    ) throws {
        let escapedCollection = escapeJSIdentifier(collection)
        var statement: String
        if escapedCollection.hasPrefix("[") {
            statement = "db\(escapedCollection).insertMany([\n"
        } else {
            statement = "db.\(escapedCollection).insertMany([\n"
        }
        statement += documents.joined(separator: ",\n")
        statement += "\n]);\n"
        try fileHandle.write(contentsOf: statement.toUTF8Data())
    }

    private func writeMQLIndexes(
        collection: String,
        collectionAccessor: String,
        to fileHandle: FileHandle
    ) async throws {
        let ddl = try await driver.fetchTableDDL(table: collection)

        let lines = ddl.components(separatedBy: "\n")
        var indexLines: [String] = []
        var foundHeader = false

        for line in lines {
            if line.hasPrefix("// Collection:") {
                foundHeader = true
                continue
            }
            if foundHeader {
                var processedLine = line
                let escapedForDDL = collection.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let ddlAccessor = "db[\"\(escapedForDDL)\"]"
                if processedLine.hasPrefix(ddlAccessor) {
                    processedLine = collectionAccessor + processedLine.dropFirst(ddlAccessor.count)
                }
                indexLines.append(processedLine)
            }
        }

        let indexContent = indexLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !indexContent.isEmpty {
            try fileHandle.write(contentsOf: "\(indexContent)\n".toUTF8Data())
        }
    }

    private func mqlJsonValue(for value: String) -> String {
        if value == "true" || value == "false" {
            return value
        }
        if value == "null" {
            return "null"
        }
        if Int64(value) != nil {
            return value
        }
        if Double(value) != nil, value.contains(".") {
            return value
        }
        // JSON object or array -- pass through if valid (no unescaped control chars)
        if (value.hasPrefix("{") && value.hasSuffix("}")) ||
            (value.hasPrefix("[") && value.hasSuffix("]")) {
            let hasControlChars = value.utf8.contains(where: { $0 < 0x20 })
            if hasControlChars {
                return "\"\(escapeJSONString(value))\""
            }
            return value
        }
        return "\"\(escapeJSONString(value))\""
    }

    func escapeJSIdentifier(_ name: String) -> String {
        guard let firstChar = name.first,
              !firstChar.isNumber,
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return "[\"\(escapeJSONString(name))\"]"
        }
        return name
    }
}
