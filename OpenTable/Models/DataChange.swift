//
//  DataChange.swift
//  OpenTable
//
//  Models for tracking data changes
//

import Foundation
import Combine

/// Represents a type of data change
enum ChangeType: Equatable {
    case update
    case insert
    case delete
}

/// Represents a single cell change
struct CellChange: Identifiable, Equatable {
    let id: UUID
    let rowIndex: Int
    let columnIndex: Int
    let columnName: String
    let oldValue: String?
    let newValue: String?
    
    init(rowIndex: Int, columnIndex: Int, columnName: String, oldValue: String?, newValue: String?) {
        self.id = UUID()
        self.rowIndex = rowIndex
        self.columnIndex = columnIndex
        self.columnName = columnName
        self.oldValue = oldValue
        self.newValue = newValue
    }
}

/// Represents a row-level change
struct RowChange: Identifiable, Equatable {
    let id: UUID
    let rowIndex: Int
    let type: ChangeType
    var cellChanges: [CellChange]
    let originalRow: [String?]?
    
    init(rowIndex: Int, type: ChangeType, cellChanges: [CellChange] = [], originalRow: [String?]? = nil) {
        self.id = UUID()
        self.rowIndex = rowIndex
        self.type = type
        self.cellChanges = cellChanges
        self.originalRow = originalRow
    }
}

/// Manager for tracking and applying data changes
final class DataChangeManager: ObservableObject {
    @Published var changes: [RowChange] = []
    @Published var hasChanges: Bool = false
    @Published var reloadVersion: Int = 0  // Incremented to trigger table reload
    
    var tableName: String = ""
    var primaryKeyColumn: String?
    var columns: [String] = []
    
    // MARK: - Cached Lookups for O(1) Performance
    
    /// Set of row indices that are marked for deletion - O(1) lookup
    private var deletedRowIndices: Set<Int> = []
    
    /// Set of "rowIndex-colIndex" strings for modified cells - O(1) lookup
    private var modifiedCells: Set<String> = []
    
    /// Helper to create a cache key for modified cells
    private func cellKey(rowIndex: Int, columnIndex: Int) -> String {
        "\(rowIndex)-\(columnIndex)"
    }
    
    /// Clear all changes (called after successful save)
    func clearChanges() {
        changes.removeAll()
        deletedRowIndices.removeAll()
        modifiedCells.removeAll()
        hasChanges = false
        reloadVersion += 1  // Trigger table reload
    }
    
    /// Rebuilds the caches from the changes array (used after complex modifications)
    private func rebuildCaches() {
        deletedRowIndices.removeAll()
        modifiedCells.removeAll()
        
        for change in changes {
            if change.type == .delete {
                deletedRowIndices.insert(change.rowIndex)
            } else if change.type == .update {
                for cellChange in change.cellChanges {
                    modifiedCells.insert(cellKey(rowIndex: change.rowIndex, columnIndex: cellChange.columnIndex))
                }
            }
        }
    }
    
    // MARK: - Change Tracking
    
    func recordCellChange(rowIndex: Int, columnIndex: Int, columnName: String, oldValue: String?, newValue: String?, originalRow: [String?]? = nil) {
        guard oldValue != newValue else { return }
        
        let cellChange = CellChange(
            rowIndex: rowIndex,
            columnIndex: columnIndex,
            columnName: columnName,
            oldValue: oldValue,
            newValue: newValue
        )
        
        let key = cellKey(rowIndex: rowIndex, columnIndex: columnIndex)
        
        // Find existing row change or create new one
        if let existingIndex = changes.firstIndex(where: { $0.rowIndex == rowIndex && $0.type == .update }) {
            // Check if this column was already changed
            if let cellIndex = changes[existingIndex].cellChanges.firstIndex(where: { $0.columnIndex == columnIndex }) {
                // Update existing cell change, keeping original oldValue
                let originalOldValue = changes[existingIndex].cellChanges[cellIndex].oldValue
                changes[existingIndex].cellChanges[cellIndex] = CellChange(
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    columnName: columnName,
                    oldValue: originalOldValue,
                    newValue: newValue
                )
                
                // If value is back to original, remove the change
                if originalOldValue == newValue {
                    changes[existingIndex].cellChanges.remove(at: cellIndex)
                    modifiedCells.remove(key)  // Remove from cache
                    if changes[existingIndex].cellChanges.isEmpty {
                        changes.remove(at: existingIndex)
                    }
                }
            } else {
                changes[existingIndex].cellChanges.append(cellChange)
                modifiedCells.insert(key)  // Add to cache
            }
        } else {
            // Create new RowChange with originalRow for WHERE clause PK lookup
            let rowChange = RowChange(rowIndex: rowIndex, type: .update, cellChanges: [cellChange], originalRow: originalRow)
            changes.append(rowChange)
            modifiedCells.insert(key)  // Add to cache
        }
        
        hasChanges = !changes.isEmpty
    }
    
    func recordRowDeletion(rowIndex: Int, originalRow: [String?]) {
        // Remove any pending updates for this row
        changes.removeAll { $0.rowIndex == rowIndex && $0.type == .update }
        
        // Clear modified cells cache for this row
        modifiedCells = modifiedCells.filter { !$0.hasPrefix("\(rowIndex)-") }
        
        let rowChange = RowChange(rowIndex: rowIndex, type: .delete, originalRow: originalRow)
        changes.append(rowChange)
        deletedRowIndices.insert(rowIndex)  // Add to cache
        hasChanges = true
    }
    
    func recordRowInsertion(rowIndex: Int, values: [String?]) {
        let cellChanges = values.enumerated().map { index, value in
            CellChange(rowIndex: rowIndex, columnIndex: index, columnName: columns[safe: index] ?? "", oldValue: nil, newValue: value)
        }
        let rowChange = RowChange(rowIndex: rowIndex, type: .insert, cellChanges: cellChanges)
        changes.append(rowChange)
        hasChanges = true
    }
    
    /// Undo a pending row deletion
    func undoRowDeletion(rowIndex: Int) {
        changes.removeAll { $0.rowIndex == rowIndex && $0.type == .delete }
        deletedRowIndices.remove(rowIndex)
        hasChanges = !changes.isEmpty
    }
    
    // MARK: - SQL Generation
    
    func generateSQL() -> [String] {
        var statements: [String] = []
        
        for change in changes {
            switch change.type {
            case .update:
                if let sql = generateUpdateSQL(for: change) {
                    statements.append(sql)
                }
            case .insert:
                if let sql = generateInsertSQL(for: change) {
                    statements.append(sql)
                }
            case .delete:
                if let sql = generateDeleteSQL(for: change) {
                    statements.append(sql)
                }
            }
        }
        
        return statements
    }
    
    /// Check if a string is a SQL function expression that should not be quoted
    private func isSQLFunctionExpression(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces).uppercased()
        
        // Common SQL functions for datetime/timestamps
        let sqlFunctions = [
            "NOW()",
            "CURRENT_TIMESTAMP()",
            "CURRENT_TIMESTAMP",
            "CURDATE()",
            "CURTIME()",
            "UTC_TIMESTAMP()",
            "UTC_DATE()",
            "UTC_TIME()",
            "LOCALTIME()",
            "LOCALTIME",
            "LOCALTIMESTAMP()",
            "LOCALTIMESTAMP",
            "SYSDATE()",
            "UNIX_TIMESTAMP()",
            "CURRENT_DATE()",
            "CURRENT_DATE",
            "CURRENT_TIME()",
            "CURRENT_TIME"
        ]
        
        return sqlFunctions.contains(trimmed)
    }
    
    private func generateUpdateSQL(for change: RowChange) -> String? {
        guard !change.cellChanges.isEmpty else { return nil }
        
        let setClauses = change.cellChanges.map { cellChange -> String in
            let value: String
            if cellChange.newValue == "__DEFAULT__" {
                value = "DEFAULT"  // SQL DEFAULT keyword
            } else if let newValue = cellChange.newValue {
                // Check if it's a SQL function expression
                if isSQLFunctionExpression(newValue) {
                    value = newValue.trimmingCharacters(in: .whitespaces).uppercased()
                } else {
                    value = "'\(escapeSQLString(newValue))'"
                }
            } else {
                value = "NULL"
            }
            return "`\(cellChange.columnName)` = \(value)"
        }.joined(separator: ", ")
        
        // Use primary key for WHERE clause
        var whereClause = "1=1" // Fallback - dangerous but necessary without PK
        
        if let pkColumn = primaryKeyColumn,
           let pkColumnIndex = columns.firstIndex(of: pkColumn) {
            // Try to get PK value from originalRow first
            if let originalRow = change.originalRow, pkColumnIndex < originalRow.count {
                let pkValue = originalRow[pkColumnIndex].map { "'\(escapeSQLString($0))'" } ?? "NULL"
                whereClause = "`\(pkColumn)` = \(pkValue)"
            }
            // Otherwise try from cellChanges (if PK column was edited)
            else if let pkChange = change.cellChanges.first(where: { $0.columnName == pkColumn }) {
                let pkValue = pkChange.oldValue.map { "'\(escapeSQLString($0))'" } ?? "NULL"
                whereClause = "`\(pkColumn)` = \(pkValue)"
            }
        }
        
        return "UPDATE `\(tableName)` SET \(setClauses) WHERE \(whereClause)"
    }
    
    private func generateInsertSQL(for change: RowChange) -> String? {
        guard !change.cellChanges.isEmpty else { return nil }
        
        let columnNames = change.cellChanges.map { "`\($0.columnName)`" }.joined(separator: ", ")
        let values = change.cellChanges.map { cellChange -> String in
            cellChange.newValue.map { "'\(escapeSQLString($0))'" } ?? "NULL"
        }.joined(separator: ", ")
        
        return "INSERT INTO `\(tableName)` (\(columnNames)) VALUES (\(values))"
    }
    
    private func generateDeleteSQL(for change: RowChange) -> String? {
        guard let pkColumn = primaryKeyColumn,
              let originalRow = change.originalRow,
              let pkIndex = columns.firstIndex(of: pkColumn),
              pkIndex < originalRow.count else {
            return nil
        }
        
        let pkValue = originalRow[pkIndex].map { "'\(escapeSQLString($0))'" } ?? "NULL"
        return "DELETE FROM `\(tableName)` WHERE `\(pkColumn)` = \(pkValue)"
    }
    
    private func escapeSQLString(_ str: String) -> String {
        // Escape characters that can break SQL strings
        var result = str
        result = result.replacingOccurrences(of: "\\", with: "\\\\")  // Backslash first
        result = result.replacingOccurrences(of: "'", with: "''")    // Single quote
        result = result.replacingOccurrences(of: "\n", with: "\\n")  // Newline
        result = result.replacingOccurrences(of: "\r", with: "\\r")  // Carriage return
        result = result.replacingOccurrences(of: "\t", with: "\\t")  // Tab
        result = result.replacingOccurrences(of: "\0", with: "\\0")  // Null byte
        return result
    }
    
    // MARK: - Actions
    
    /// Returns all original cell values that need to be restored
    /// Format: [(rowIndex, columnIndex, originalValue)]
    func getOriginalValues() -> [(rowIndex: Int, columnIndex: Int, value: String?)] {
        var originals: [(rowIndex: Int, columnIndex: Int, value: String?)] = []
        
        for change in changes {
            if change.type == .update {
                for cellChange in change.cellChanges {
                    originals.append((
                        rowIndex: change.rowIndex,
                        columnIndex: cellChange.columnIndex,
                        value: cellChange.oldValue
                    ))
                }
            }
        }
        
        return originals
    }
    
    func discardChanges() {
        changes.removeAll()
        deletedRowIndices.removeAll()  // Clear cache
        modifiedCells.removeAll()       // Clear cache
        hasChanges = false
        reloadVersion += 1  // Trigger table reload
    }
    
    /// O(1) lookup for deleted rows using cached Set
    func isRowDeleted(_ rowIndex: Int) -> Bool {
        deletedRowIndices.contains(rowIndex)
    }
    
    /// O(1) lookup for modified cells using cached Set
    func isCellModified(rowIndex: Int, columnIndex: Int) -> Bool {
        modifiedCells.contains(cellKey(rowIndex: rowIndex, columnIndex: columnIndex))
    }
    
    /// Returns a Set of column indices that are modified for a given row
    /// Used for efficient batch lookup in TableRowView
    func getModifiedColumnsForRow(_ rowIndex: Int) -> Set<Int> {
        var result: Set<Int> = []
        let prefix = "\(rowIndex)-"
        for key in modifiedCells {
            if key.hasPrefix(prefix) {
                if let colIndex = Int(key.dropFirst(prefix.count)) {
                    result.insert(colIndex)
                }
            }
        }
        return result
    }
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
