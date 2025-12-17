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
    
    var tableName: String = ""
    var primaryKeyColumn: String?
    var columns: [String] = []
    
    // MARK: - Change Tracking
    
    func recordCellChange(rowIndex: Int, columnIndex: Int, columnName: String, oldValue: String?, newValue: String?) {
        guard oldValue != newValue else { return }
        
        let cellChange = CellChange(
            rowIndex: rowIndex,
            columnIndex: columnIndex,
            columnName: columnName,
            oldValue: oldValue,
            newValue: newValue
        )
        
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
                    if changes[existingIndex].cellChanges.isEmpty {
                        changes.remove(at: existingIndex)
                    }
                }
            } else {
                changes[existingIndex].cellChanges.append(cellChange)
            }
        } else {
            let rowChange = RowChange(rowIndex: rowIndex, type: .update, cellChanges: [cellChange])
            changes.append(rowChange)
        }
        
        hasChanges = !changes.isEmpty
    }
    
    func recordRowDeletion(rowIndex: Int, originalRow: [String?]) {
        // Remove any pending updates for this row
        changes.removeAll { $0.rowIndex == rowIndex && $0.type == .update }
        
        let rowChange = RowChange(rowIndex: rowIndex, type: .delete, originalRow: originalRow)
        changes.append(rowChange)
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
    
    private func generateUpdateSQL(for change: RowChange) -> String? {
        guard !change.cellChanges.isEmpty else { return nil }
        
        let setClauses = change.cellChanges.map { cellChange -> String in
            let value = cellChange.newValue.map { "'\(escapeSQLString($0))'" } ?? "NULL"
            return "`\(cellChange.columnName)` = \(value)"
        }.joined(separator: ", ")
        
        // Use primary key for WHERE clause if available
        var whereClause = "1=1" // Fallback - dangerous but necessary without PK
        if let pkColumn = primaryKeyColumn,
           let pkChange = change.cellChanges.first(where: { $0.columnName == pkColumn }) {
            let pkValue = pkChange.oldValue.map { "'\(escapeSQLString($0))'" } ?? "NULL"
            whereClause = "`\(pkColumn)` = \(pkValue)"
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
        str.replacingOccurrences(of: "'", with: "''")
    }
    
    // MARK: - Actions
    
    func discardChanges() {
        changes.removeAll()
        hasChanges = false
    }
    
    func isRowDeleted(_ rowIndex: Int) -> Bool {
        changes.contains { $0.rowIndex == rowIndex && $0.type == .delete }
    }
    
    func isCellModified(rowIndex: Int, columnIndex: Int) -> Bool {
        changes.contains { rowChange in
            rowChange.rowIndex == rowIndex &&
            rowChange.type == .update &&
            rowChange.cellChanges.contains { $0.columnIndex == columnIndex }
        }
    }
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
