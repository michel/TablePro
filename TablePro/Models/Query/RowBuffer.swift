//
//  RowBuffer.swift
//  TablePro
//

import Foundation
import os
import TableProPluginKit

/// Reference-type wrapper for large result data.
/// When QueryTab (a struct) is copied via CoW, only this 8-byte reference is copied
/// instead of duplicating potentially large result arrays.
final class RowBuffer {
    var rows: [[String?]]
    var columns: [String]
    var columnTypes: [ColumnType]
    var columnDefaults: [String: String?]
    var columnForeignKeys: [String: ForeignKeyInfo]
    var columnEnumValues: [String: [String]]
    var columnNullable: [String: Bool]

    init(
        rows: [[String?]] = [],
        columns: [String] = [],
        columnTypes: [ColumnType] = [],
        columnDefaults: [String: String?] = [:],
        columnForeignKeys: [String: ForeignKeyInfo] = [:],
        columnEnumValues: [String: [String]] = [:],
        columnNullable: [String: Bool] = [:]
    ) {
        self.rows = rows
        self.columns = columns
        self.columnTypes = columnTypes
        self.columnDefaults = columnDefaults
        self.columnForeignKeys = columnForeignKeys
        self.columnEnumValues = columnEnumValues
        self.columnNullable = columnNullable
    }

    /// Create a deep copy of this buffer (used when explicit data duplication is needed)
    func copy() -> RowBuffer {
        RowBuffer(
            rows: rows,
            columns: columns,
            columnTypes: columnTypes,
            columnDefaults: columnDefaults,
            columnForeignKeys: columnForeignKeys,
            columnEnumValues: columnEnumValues,
            columnNullable: columnNullable
        )
    }

    /// Whether this buffer's row data has been evicted to save memory
    private(set) var isEvicted: Bool = false

    /// Evict row data to free memory. Column metadata is preserved.
    func evict() {
        guard !isEvicted else { return }
        rows = []
        isEvicted = true
    }

    /// Restore row data after eviction
    func restore(rows newRows: [[String?]]) {
        self.rows = newRows
        isEvicted = false
    }

    deinit {
        #if DEBUG
        Logger(subsystem: "com.TablePro", category: "RowBuffer")
            .debug("RowBuffer deallocated — columns: \(self.columns.count), evicted: \(self.isEvicted)")
        #endif
    }
}
