//
//  DataChange.swift
//  OpenTable
//
//  Models for tracking data changes
//

import Combine
import Foundation

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

    init(rowIndex: Int, columnIndex: Int, columnName: String, oldValue: String?, newValue: String?)
    {
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
    var rowIndex: Int
    let type: ChangeType
    var cellChanges: [CellChange]
    let originalRow: [String?]?

    init(
        rowIndex: Int, type: ChangeType, cellChanges: [CellChange] = [],
        originalRow: [String?]? = nil
    ) {
        self.id = UUID()
        self.rowIndex = rowIndex
        self.type = type
        self.cellChanges = cellChanges
        self.originalRow = originalRow
    }
}

/// Manager for tracking and applying data changes
/// @MainActor ensures thread-safe access to most properties - critical for avoiding EXC_BAD_ACCESS
/// when multiple queries complete simultaneously (e.g., rapid sorting over SSH tunnel)

/// Represents an action that can be undone
enum UndoAction {
    case cellEdit(rowIndex: Int, columnIndex: Int, columnName: String, previousValue: String?, newValue: String?)
    case rowInsertion(rowIndex: Int)
    case rowDeletion(rowIndex: Int, originalRow: [String?])
    /// Batch deletion of multiple rows (for undo as a single action)
    case batchRowDeletion(rows: [(rowIndex: Int, originalRow: [String?])])
    /// Batch insertion undo - when user deletes multiple inserted rows at once
    case batchRowInsertion(rowIndices: [Int], rowValues: [[String?]])
}

@MainActor
final class DataChangeManager: ObservableObject {
    @Published var changes: [RowChange] = []
    @Published var hasChanges: Bool = false
    @Published var reloadVersion: Int = 0  // Incremented to trigger table reload

    var tableName: String = ""
    var primaryKeyColumn: String?
    var databaseType: DatabaseType = .mysql  // For database-specific SQL generation

    // Simple storage with explicit deep copy to avoid memory corruption
    private var _columnsStorage: [String] = []
    var columns: [String] {
        get {
            return _columnsStorage
        }
        set {
            // Create explicit deep copy to ensure independence
            _columnsStorage = newValue.map { String($0) }
        }
    }

    // MARK: - Cached Lookups for O(1) Performance

    /// Set of row indices that are marked for deletion - O(1) lookup
    private var deletedRowIndices: Set<Int> = []
    
    /// Set of row indices that are newly inserted - O(1) lookup
    private(set) var insertedRowIndices: Set<Int> = []

    /// Set of "rowIndex-colIndex" strings for modified cells - O(1) lookup
    private var modifiedCells: Set<String> = []
    
    /// Lazy storage for inserted row values - avoids creating CellChange objects until needed
    /// Maps rowIndex -> column values array for newly inserted rows
    /// This dramatically improves add row performance for tables with many columns
    private var insertedRowData: [Int: [String?]] = [:]
    
    /// Undo stack for reversing changes (LIFO)
    private var undoStack: [UndoAction] = []
    
    /// Redo stack for re-applying undone changes (LIFO)
    private var redoStack: [UndoAction] = []

    /// Helper to create a cache key for modified cells
    private func cellKey(rowIndex: Int, columnIndex: Int) -> String {
        "\(rowIndex)-\(columnIndex)"
    }

    /// Clear all changes (called after successful save)
    func clearChanges() {
        changes.removeAll()
        deletedRowIndices.removeAll()
        insertedRowIndices.removeAll()
        modifiedCells.removeAll()
        undoStack.removeAll()  // Clear undo stack too
        hasChanges = false
        reloadVersion += 1  // Trigger table reload
    }

    /// Atomically configure the manager for a new table
    /// This batches all updates and only triggers @Published changes at the end
    /// to prevent race conditions where SwiftUI reads properties mid-update
    func configureForTable(
        tableName: String, columns: [String], primaryKeyColumn: String?,
        databaseType: DatabaseType = .mysql
    ) {
        // First, update non-published properties (no SwiftUI notifications)
        self.tableName = tableName
        self.columns = columns  // Uses deep copy setter to avoid memory corruption
        self.primaryKeyColumn = primaryKeyColumn
        self.databaseType = databaseType

        // Clear caches
        deletedRowIndices.removeAll()
        insertedRowIndices.removeAll()
        modifiedCells.removeAll()

        // Now update @Published properties - triggers ONE view update
        changes.removeAll()
        hasChanges = false
        reloadVersion += 1
    }

    /// Rebuilds the caches from the changes array (used after complex modifications)
    private func rebuildCaches() {
        deletedRowIndices.removeAll()
        insertedRowIndices.removeAll()
        modifiedCells.removeAll()

        for change in changes {
            if change.type == .delete {
                deletedRowIndices.insert(change.rowIndex)
            } else if change.type == .insert {
                insertedRowIndices.insert(change.rowIndex)
            } else if change.type == .update {
                for cellChange in change.cellChanges {
                    modifiedCells.insert(
                        cellKey(rowIndex: change.rowIndex, columnIndex: cellChange.columnIndex))
                }
            }
        }
    }

    // MARK: - Change Tracking

    func recordCellChange(
        rowIndex: Int, columnIndex: Int, columnName: String, oldValue: String?, newValue: String?,
        originalRow: [String?]? = nil
    ) {
        guard oldValue != newValue else { return }

        let cellChange = CellChange(
            rowIndex: rowIndex,
            columnIndex: columnIndex,
            columnName: columnName,
            oldValue: oldValue,
            newValue: newValue
        )

        let key = cellKey(rowIndex: rowIndex, columnIndex: columnIndex)

        // Check if this is an edit to an INSERTED row
        // If so, update the INSERT record's cell values instead of creating UPDATE
        if let insertIndex = changes.firstIndex(where: {
            $0.rowIndex == rowIndex && $0.type == .insert
        }) {
            // Update or add cell change in the INSERT record
            if let cellIndex = changes[insertIndex].cellChanges.firstIndex(where: {
                $0.columnIndex == columnIndex
            }) {
                // Update existing cell in INSERT
                changes[insertIndex].cellChanges[cellIndex] = CellChange(
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    columnName: columnName,
                    oldValue: nil,  // INSERT doesn't have oldValue
                    newValue: newValue
                )
            } else {
                // Add new cell to INSERT
                changes[insertIndex].cellChanges.append(CellChange(
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    columnName: columnName,
                    oldValue: nil,
                    newValue: newValue
                ))
            }
            // Push undo action for inserted row cell edit
            pushUndo(.cellEdit(rowIndex: rowIndex, columnIndex: columnIndex, columnName: columnName, previousValue: oldValue, newValue: newValue))
            hasChanges = !changes.isEmpty
            return
        }

        // Find existing UPDATE row change or create new one
        if let existingIndex = changes.firstIndex(where: {
            $0.rowIndex == rowIndex && $0.type == .update
        }) {
            // Check if this column was already changed
            if let cellIndex = changes[existingIndex].cellChanges.firstIndex(where: {
                $0.columnIndex == columnIndex
            }) {
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
            let rowChange = RowChange(
                rowIndex: rowIndex, type: .update, cellChanges: [cellChange],
                originalRow: originalRow)
            changes.append(rowChange)
            modifiedCells.insert(key)  // Add to cache
        }

        // Push undo action for cell edit
        pushUndo(.cellEdit(rowIndex: rowIndex, columnIndex: columnIndex, columnName: columnName, previousValue: oldValue, newValue: newValue))
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
        pushUndo(.rowDeletion(rowIndex: rowIndex, originalRow: originalRow))  // Push undo action
        hasChanges = true
        reloadVersion += 1  // Trigger table reload to show red background
    }
    
    /// Record multiple row deletions as a single undo action
    /// - Parameter rows: Array of (rowIndex, originalRow) tuples, sorted by row index descending
    func recordBatchRowDeletion(rows: [(rowIndex: Int, originalRow: [String?])]) {
        guard rows.count > 1 else {
            // Single row, use normal method
            if let row = rows.first {
                recordRowDeletion(rowIndex: row.rowIndex, originalRow: row.originalRow)
            }
            return
        }
        
        // Collect data for batch undo before modifying state
        var batchData: [(rowIndex: Int, originalRow: [String?])] = []
        
        for (rowIndex, originalRow) in rows {
            // Remove any pending updates for this row
            changes.removeAll { $0.rowIndex == rowIndex && $0.type == .update }
            
            // Clear modified cells cache for this row
            modifiedCells = modifiedCells.filter { !$0.hasPrefix("\(rowIndex)-") }
            
            let rowChange = RowChange(rowIndex: rowIndex, type: .delete, originalRow: originalRow)
            changes.append(rowChange)
            deletedRowIndices.insert(rowIndex)
            
            batchData.append((rowIndex: rowIndex, originalRow: originalRow))
        }
        
        // Push a single batch undo action
        pushUndo(.batchRowDeletion(rows: batchData))
        hasChanges = true
        reloadVersion += 1
    }

    func recordRowInsertion(rowIndex: Int, values: [String?]) {
        let cellChanges = values.enumerated().map { index, value in
            CellChange(
                rowIndex: rowIndex, columnIndex: index, columnName: columns[safe: index] ?? "",
                oldValue: nil, newValue: value)
        }
        let rowChange = RowChange(rowIndex: rowIndex, type: .insert, cellChanges: cellChanges)
        changes.append(rowChange)
        insertedRowIndices.insert(rowIndex)  // Add to cache
        pushUndo(.rowInsertion(rowIndex: rowIndex))  // Push undo action
        hasChanges = true
    }

    /// Undo a pending row deletion
    func undoRowDeletion(rowIndex: Int) {
        // SAFETY: Only process if this row is actually marked as deleted
        guard deletedRowIndices.contains(rowIndex) else {
            print("⚠️ undoRowDeletion called for row \(rowIndex) but it's not in deletedRowIndices")
            return
        }
        
        changes.removeAll { $0.rowIndex == rowIndex && $0.type == .delete }
        deletedRowIndices.remove(rowIndex)
        hasChanges = !changes.isEmpty
        reloadVersion += 1  // Trigger table reload to remove red background
    }
    
    /// Undo a pending row insertion
    func undoRowInsertion(rowIndex: Int) {
        // SAFETY: Only process if this row is actually marked as inserted
        guard insertedRowIndices.contains(rowIndex) else {
            print("⚠️ undoRowInsertion: row \(rowIndex) not in insertedRowIndices")
            return
        }
        
        // Remove the INSERT change from the changes array
        changes.removeAll { $0.rowIndex == rowIndex && $0.type == .insert }
        insertedRowIndices.remove(rowIndex)
        
        // Shift down indices for rows after the removed row
        var shiftedInsertedIndices = Set<Int>()
        for idx in insertedRowIndices {
            if idx > rowIndex {
                shiftedInsertedIndices.insert(idx - 1)
            } else {
                shiftedInsertedIndices.insert(idx)
            }
        }
        insertedRowIndices = shiftedInsertedIndices
        
        // Also update row indices in changes array for all changes after this row
        for i in 0..<changes.count {
            if changes[i].rowIndex > rowIndex {
                changes[i].rowIndex -= 1
            }
        }
        
        hasChanges = !changes.isEmpty
    }
    
    /// Undo multiple row insertions at once (for batch deletion)
    /// This is more efficient than calling undoRowInsertion multiple times
    /// - Parameter rowIndices: Array of row indices to undo, MUST be sorted in descending order
    func undoBatchRowInsertion(rowIndices: [Int]) {
        guard !rowIndices.isEmpty else { return }
        
        // Verify all rows are inserted
        let validRows = rowIndices.filter { insertedRowIndices.contains($0) }
        
        if validRows.count != rowIndices.count {
            let invalidRows = Set(rowIndices).subtracting(validRows)
            print("⚠️ undoBatchRowInsertion: rows \(invalidRows) not in insertedRowIndices")
        }
        
        guard !validRows.isEmpty else { return }
        
        // Collect row values BEFORE removing changes (for undo/redo)
        var rowValues: [[String?]] = []
        for rowIndex in validRows {
            if let insertChange = changes.first(where: { $0.rowIndex == rowIndex && $0.type == .insert }) {
                let values = insertChange.cellChanges.sorted { $0.columnIndex < $1.columnIndex }
                    .map { $0.newValue }
                rowValues.append(values)
            } else {
                rowValues.append(Array(repeating: nil, count: columns.count))
            }
        }
        
        // Remove all INSERT changes for these rows
        for rowIndex in validRows {
            changes.removeAll { $0.rowIndex == rowIndex && $0.type == .insert }
            insertedRowIndices.remove(rowIndex)
        }
        
        // Push undo action so user can undo this deletion
        pushUndo(.batchRowInsertion(rowIndices: validRows, rowValues: rowValues))
        
        // Shift indices for all remaining rows
        for deletedIndex in validRows.reversed() {
            var shiftedIndices = Set<Int>()
            for idx in insertedRowIndices {
                if idx > deletedIndex {
                    shiftedIndices.insert(idx - 1)
                } else {
                    shiftedIndices.insert(idx)
                }
            }
            insertedRowIndices = shiftedIndices
            
            for i in 0..<changes.count {
                if changes[i].rowIndex > deletedIndex {
                    changes[i].rowIndex -= 1
                }
            }
        }
        
        hasChanges = !changes.isEmpty
    }

    // MARK: - Undo Stack Management
    
    /// Push an undo action onto the stack
    func pushUndo(_ action: UndoAction) {
        undoStack.append(action)
    }
    
    /// Pop the last undo action from the stack
    func popUndo() -> UndoAction? {
        undoStack.popLast()
    }
    
    /// Clear the undo stack (called after save or discard)
    func clearUndoStack() {
        undoStack.removeAll()
    }
    
    /// Clear the redo stack (called when new changes are made)
    func clearRedoStack() {
        redoStack.removeAll()
    }
    
    /// Check if there are any undo actions available
    var canUndo: Bool {
        !undoStack.isEmpty
    }
    
    /// Check if there are any redo actions available
    var canRedo: Bool {
        !redoStack.isEmpty
    }
    
    /// Undo the last change and return details needed to update the UI
    /// Returns: (action, needsRowRemoval, needsRowRestore, restoreRow)
    func undoLastChange() -> (action: UndoAction, needsRowRemoval: Bool, needsRowRestore: Bool, restoreRow: [String?]?)? {
        guard let action = popUndo() else { return nil }
        
        // Push to redo stack so we can redo this action
        redoStack.append(action)
        
        switch action {
        case .cellEdit(let rowIndex, let columnIndex, let columnName, let previousValue, _):
            // Find and revert the cell change
            if let changeIndex = changes.firstIndex(where: {
                $0.rowIndex == rowIndex && ($0.type == .update || $0.type == .insert)
            }) {
                if let cellIndex = changes[changeIndex].cellChanges.firstIndex(where: {
                    $0.columnIndex == columnIndex
                }) {
                    // For updates, restore the original value
                    if changes[changeIndex].type == .update {
                        let originalValue = changes[changeIndex].cellChanges[cellIndex].oldValue
                        if previousValue == originalValue {
                            // Value is back to original, remove the cell change
                            changes[changeIndex].cellChanges.remove(at: cellIndex)
                            modifiedCells.remove(cellKey(rowIndex: rowIndex, columnIndex: columnIndex))
                            if changes[changeIndex].cellChanges.isEmpty {
                                changes.remove(at: changeIndex)
                            }
                        } else {
                            // Update cell change with previous value
                            let originalOldValue = changes[changeIndex].cellChanges[cellIndex].oldValue
                            changes[changeIndex].cellChanges[cellIndex] = CellChange(
                                rowIndex: rowIndex,
                                columnIndex: columnIndex,
                                columnName: columnName,
                                oldValue: originalOldValue,
                                newValue: previousValue
                            )
                        }
                    } else if changes[changeIndex].type == .insert {
                        // For inserts, just update the cell value
                        changes[changeIndex].cellChanges[cellIndex] = CellChange(
                            rowIndex: rowIndex,
                            columnIndex: columnIndex,
                            columnName: columnName,
                            oldValue: nil,
                            newValue: previousValue
                        )
                    }
                }
            }
            hasChanges = !changes.isEmpty
            reloadVersion += 1
            return (action, false, false, nil)
            
        case .rowInsertion(let rowIndex):
            // Undo the insertion by removing the row
            undoRowInsertion(rowIndex: rowIndex)
            return (action, true, false, nil)
            
        case .rowDeletion(let rowIndex, let originalRow):
            // Undo the deletion by restoring the row
            undoRowDeletion(rowIndex: rowIndex)
            return (action, false, true, originalRow)
            
        case .batchRowDeletion(let rows):
            // Undo all deletions in the batch (restore all rows)
            // Process in reverse order to maintain correct indices
            for (rowIndex, _) in rows.reversed() {
                undoRowDeletion(rowIndex: rowIndex)
            }
            return (action, false, true, nil)
            
        case .batchRowInsertion(let rowIndices, let rowValues):
            // Undo the deletion of inserted rows - restore them as INSERT changes
            // Process in reverse order (ascending) to maintain correct indices when re-inserting
            for (index, rowIndex) in rowIndices.enumerated().reversed() {
                guard index < rowValues.count else { continue }
                let values = rowValues[index]
                
                // Re-create INSERT change
                let cellChanges = values.enumerated().map { colIndex, value in
                    CellChange(
                        rowIndex: rowIndex,
                        columnIndex: colIndex,
                        columnName: columns[safe: colIndex] ?? "",
                        oldValue: nil,
                        newValue: value
                    )
                }
                let rowChange = RowChange(rowIndex: rowIndex, type: .insert, cellChanges: cellChanges)
                changes.append(rowChange)
                insertedRowIndices.insert(rowIndex)
            }
            
            hasChanges = !changes.isEmpty
            reloadVersion += 1
            // Return true for needsRowInsert so MainContentView knows to restore to resultRows
            return (action, true, false, nil)
        }
    }
    
    /// Redo the last undone change and return details needed to update the UI
    /// Returns: (action, needsRowInsert, needsRowDelete)
    func redoLastChange() -> (action: UndoAction, needsRowInsert: Bool, needsRowDelete: Bool)? {
        guard !redoStack.isEmpty else { return nil }
        let action = redoStack.removeLast()
        
        // Push back to undo stack so we can undo again
        undoStack.append(action)
        
        switch action {
        case .cellEdit(let rowIndex, let columnIndex, let columnName, let previousValue, let newValue):
            // Re-apply the cell edit (previousValue becomes oldValue for the new edit)
            recordCellChange(rowIndex: rowIndex, columnIndex: columnIndex, columnName: columnName, oldValue: previousValue, newValue: newValue)
            // Remove the extra undo action that recordCellChange pushed
            _ = undoStack.popLast()
            reloadVersion += 1
            return (action, false, false)
            
        case .rowInsertion(let rowIndex):
            // Re-apply the row insertion - we need to restore the full INSERT change
            // Note: We don't have the original cell values in the UndoAction,
            // so we need the caller (MainContentView) to provide them when re-inserting the row
            // For now, just mark as inserted and let the caller handle cell values
            insertedRowIndices.insert(rowIndex)
            
            // Create empty INSERT change - caller should update with actual values
            // The row should already exist in resultRows from the redo handler in MainContentView
            let cellChanges = columns.enumerated().map { index, columnName in
                CellChange(
                    rowIndex: rowIndex,
                    columnIndex: index,
                    columnName: columnName,
                    oldValue: nil,
                    newValue: nil  // Will be updated by caller
                )
            }
            let rowChange = RowChange(rowIndex: rowIndex, type: .insert, cellChanges: cellChanges)
            changes.append(rowChange)
            
            hasChanges = true
            reloadVersion += 1
            return (action, true, false)
            
        case .rowDeletion(let rowIndex, let originalRow):
            // Re-apply the deletion
            recordRowDeletion(rowIndex: rowIndex, originalRow: originalRow)
            // Remove the extra undo action that recordRowDeletion pushed
            _ = undoStack.popLast()
            return (action, false, true)
            
        case .batchRowDeletion(let rows):
            // Re-apply all deletions in the batch
            for (rowIndex, originalRow) in rows {
                recordRowDeletion(rowIndex: rowIndex, originalRow: originalRow)
                // Remove the extra undo action
                _ = undoStack.popLast()
            }
            return (action, false, true)
            
        case .batchRowInsertion(let rowIndices, _):
            // Redo the deletion of inserted rows - remove them again
            // This is called when user: delete inserted rows -> undo -> redo
            // We need to remove the rows from changes and insertedRowIndices again
            for rowIndex in rowIndices {
                changes.removeAll { $0.rowIndex == rowIndex && $0.type == .insert }
                insertedRowIndices.remove(rowIndex)
            }
            hasChanges = !changes.isEmpty
            reloadVersion += 1
            // Return true for needsRowInsert to signal MainContentView to remove from resultRows
            // (We repurpose this flag since the logic is similar - rows need to be removed)
            return (action, true, false)
        }
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
                // SAFETY: Verify the row is still marked as inserted
                guard insertedRowIndices.contains(change.rowIndex) else {
                    print("⚠️ Skipping INSERT for row \(change.rowIndex) - not in insertedRowIndices")
                    continue
                }
                if let sql = generateInsertSQL(for: change) {
                    statements.append(sql)
                }
            case .delete:
                // SAFETY: Verify the row is still marked as deleted
                guard deletedRowIndices.contains(change.rowIndex) else {
                    print("⚠️ Skipping DELETE for row \(change.rowIndex) - not in deletedRowIndices")
                    continue
                }
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
            "CURRENT_TIME",
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
            return "\(databaseType.quoteIdentifier(cellChange.columnName)) = \(value)"
        }.joined(separator: ", ")

        // Use primary key for WHERE clause
        var whereClause = "1=1"  // Fallback - dangerous but necessary without PK

        if let pkColumn = primaryKeyColumn,
            let pkColumnIndex = columns.firstIndex(of: pkColumn)
        {
            // Try to get PK value from originalRow first
            if let originalRow = change.originalRow, pkColumnIndex < originalRow.count {
                let pkValue =
                    originalRow[pkColumnIndex].map { "'\(escapeSQLString($0))'" } ?? "NULL"
                whereClause = "\(databaseType.quoteIdentifier(pkColumn)) = \(pkValue)"
            }
            // Otherwise try from cellChanges (if PK column was edited)
            else if let pkChange = change.cellChanges.first(where: { $0.columnName == pkColumn }) {
                let pkValue = pkChange.oldValue.map { "'\(escapeSQLString($0))'" } ?? "NULL"
                whereClause = "\(databaseType.quoteIdentifier(pkColumn)) = \(pkValue)"
            }
        }

        return
            "UPDATE \(databaseType.quoteIdentifier(tableName)) SET \(setClauses) WHERE \(whereClause)"
    }

    private func generateInsertSQL(for change: RowChange) -> String? {
        guard !change.cellChanges.isEmpty else { return nil }

        // Filter out DEFAULT columns - let DB handle them
        let nonDefaultChanges = change.cellChanges.filter { 
            $0.newValue != "__DEFAULT__" 
        }
        
        // If all columns are DEFAULT, don't generate INSERT
        // (user hasn't modified anything - just added empty row)
        guard !nonDefaultChanges.isEmpty else { return nil }
        
        let columnNames = nonDefaultChanges.map { 
            databaseType.quoteIdentifier($0.columnName) 
        }.joined(separator: ", ")
        
        let values = nonDefaultChanges.map { cellChange -> String in
            if let newValue = cellChange.newValue {
                // Check if it's a SQL function expression
                if isSQLFunctionExpression(newValue) {
                    return newValue.trimmingCharacters(in: .whitespaces).uppercased()
                }
                return "'\(escapeSQLString(newValue))'"
            }
            return "NULL"
        }.joined(separator: ", ")

        return
            "INSERT INTO \(databaseType.quoteIdentifier(tableName)) (\(columnNames)) VALUES (\(values))"
    }

    private func generateDeleteSQL(for change: RowChange) -> String? {
        guard let pkColumn = primaryKeyColumn,
            let originalRow = change.originalRow,
            let pkIndex = columns.firstIndex(of: pkColumn),
            pkIndex < originalRow.count
        else {
            return nil
        }

        let pkValue = originalRow[pkIndex].map { "'\(escapeSQLString($0))'" } ?? "NULL"
        return
            "DELETE FROM \(databaseType.quoteIdentifier(tableName)) WHERE \(databaseType.quoteIdentifier(pkColumn)) = \(pkValue)"
    }

    private func escapeSQLString(_ str: String) -> String {
        // Escape characters that can break SQL strings
        var result = str
        result = result.replacingOccurrences(of: "\\", with: "\\\\")  // Backslash first
        result = result.replacingOccurrences(of: "'", with: "''")  // Single quote
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
                    originals.append(
                        (
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
        insertedRowIndices.removeAll()  // Clear cache
        modifiedCells.removeAll()  // Clear cache
        hasChanges = false
        reloadVersion += 1  // Trigger table reload
    }

    // MARK: - Per-Tab State Management

    /// Save current state to a TabPendingChanges struct for storage in a tab
    func saveState() -> TabPendingChanges {
        var state = TabPendingChanges()
        state.changes = changes
        state.deletedRowIndices = deletedRowIndices
        state.insertedRowIndices = insertedRowIndices
        state.modifiedCells = modifiedCells
        state.primaryKeyColumn = primaryKeyColumn
        state.columns = columns
        return state
    }

    /// Restore state from a TabPendingChanges struct
    func restoreState(from state: TabPendingChanges, tableName: String) {
        self.tableName = tableName
        self.changes = state.changes
        self.deletedRowIndices = state.deletedRowIndices
        self.insertedRowIndices = state.insertedRowIndices
        self.modifiedCells = state.modifiedCells
        self.primaryKeyColumn = state.primaryKeyColumn
        self.columns = state.columns
        self.hasChanges = !state.changes.isEmpty
    }

    /// O(1) lookup for deleted rows using cached Set
    func isRowDeleted(_ rowIndex: Int) -> Bool {
        deletedRowIndices.contains(rowIndex)
    }
    
    /// O(1) lookup for inserted rows using cached Set
    func isRowInserted(_ rowIndex: Int) -> Bool {
        insertedRowIndices.contains(rowIndex)
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
