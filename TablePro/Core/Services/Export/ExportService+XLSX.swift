//
//  ExportService+XLSX.swift
//  TablePro
//

import AppKit
import Foundation

extension ExportService {
    func exportToXLSX(
        tables: [ExportTableItem],
        config: ExportConfiguration,
        to url: URL
    ) async throws {
        let writer = XLSXWriter()
        let options = config.xlsxOptions

        for (index, table) in tables.enumerated() {
            try checkCancellation()

            state.currentTableIndex = index + 1
            state.currentTable = table.qualifiedName

            let batchSize = 5_000
            var offset = 0
            var columns: [String] = []
            var isFirstBatch = true

            while true {
                try checkCancellation()
                try Task.checkCancellation()

                let result = try await fetchBatch(for: table, offset: offset, limit: batchSize)

                if result.rows.isEmpty { break }

                if isFirstBatch {
                    columns = result.columns
                    writer.beginSheet(
                        name: table.name,
                        columns: columns,
                        includeHeader: options.includeHeaderRow,
                        convertNullToEmpty: options.convertNullToEmpty
                    )
                    isFirstBatch = false
                }

                // Write this batch to the sheet XML and release batch memory
                autoreleasepool {
                    writer.addRows(result.rows, convertNullToEmpty: options.convertNullToEmpty)
                }

                // Update progress for each row in this batch
                for _ in result.rows {
                    await incrementProgress()
                }

                offset += batchSize
            }

            // If we fetched at least one batch, finish the sheet
            if !isFirstBatch {
                writer.finishSheet()
            } else {
                // Table was empty - create an empty sheet with no data
                writer.beginSheet(
                    name: table.name,
                    columns: [],
                    includeHeader: false,
                    convertNullToEmpty: options.convertNullToEmpty
                )
                writer.finishSheet()
            }

            await finalizeTableProgress()
        }

        // Write XLSX on background thread to avoid blocking UI
        try await Task.detached(priority: .userInitiated) {
            try writer.write(to: url)
        }.value
    }
}
