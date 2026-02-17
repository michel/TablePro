//
//  StructureUndoManagerTests.swift
//  TableProTests
//
//  Tests for S-01: Undo/Redo must be functional in StructureChangeManager
//

import Foundation
import Testing
@testable import TablePro

// MARK: - StructureUndoManager Unit Tests

@Suite("Structure Undo Manager")
struct StructureUndoManagerTests {

    // MARK: - Helpers

    private func makeColumn(
        name: String = "email",
        dataType: String = "VARCHAR(255)"
    ) -> EditableColumnDefinition {
        EditableColumnDefinition(
            id: UUID(),
            name: name,
            dataType: dataType,
            isNullable: true,
            defaultValue: nil,
            autoIncrement: false,
            unsigned: false,
            comment: nil,
            collation: nil,
            onUpdate: nil,
            charset: nil,
            extra: nil,
            isPrimaryKey: false
        )
    }

    private func makeIndex(
        name: String = "idx_email",
        columns: [String] = ["email"]
    ) -> EditableIndexDefinition {
        EditableIndexDefinition(
            id: UUID(),
            name: name,
            columns: columns,
            type: .btree,
            isUnique: false,
            isPrimary: false,
            comment: nil
        )
    }

    private func makeFK(
        name: String = "fk_role",
        columns: [String] = ["role_id"],
        refTable: String = "roles",
        refColumns: [String] = ["id"]
    ) -> EditableForeignKeyDefinition {
        EditableForeignKeyDefinition(
            id: UUID(),
            name: name,
            columns: columns,
            referencedTable: refTable,
            referencedColumns: refColumns,
            onDelete: .cascade,
            onUpdate: .noAction
        )
    }

    // MARK: - Basic Push/Pop Tests

    @Test("Push and undo returns the action")
    func pushAndUndo() {
        let manager = StructureUndoManager()
        let col = makeColumn()
        manager.push(.columnAdd(column: col))

        #expect(manager.canUndo == true)
        let action = manager.undo()
        #expect(action != nil)
    }

    @Test("Undo on empty stack returns nil")
    func undoEmpty() {
        let manager = StructureUndoManager()
        #expect(manager.canUndo == false)
        #expect(manager.undo() == nil)
    }

    @Test("Redo on empty stack returns nil")
    func redoEmpty() {
        let manager = StructureUndoManager()
        #expect(manager.canRedo == false)
        #expect(manager.redo() == nil)
    }

    @Test("Undo moves action to redo stack")
    func undoMovesToRedo() {
        let manager = StructureUndoManager()
        let col = makeColumn()
        manager.push(.columnAdd(column: col))

        _ = manager.undo()
        #expect(manager.canUndo == false)
        #expect(manager.canRedo == true)
    }

    @Test("Redo moves action back to undo stack")
    func redoMovesBack() {
        let manager = StructureUndoManager()
        let col = makeColumn()
        manager.push(.columnAdd(column: col))

        _ = manager.undo()
        _ = manager.redo()
        #expect(manager.canUndo == true)
        #expect(manager.canRedo == false)
    }

    @Test("New action clears redo stack")
    func newActionClearsRedo() {
        let manager = StructureUndoManager()
        let col1 = makeColumn(name: "a")
        let col2 = makeColumn(name: "b")

        manager.push(.columnAdd(column: col1))
        _ = manager.undo()
        #expect(manager.canRedo == true)

        manager.push(.columnAdd(column: col2))
        #expect(manager.canRedo == false)
    }

    @Test("Max stack size is enforced")
    func maxStackSize() {
        let manager = StructureUndoManager()
        for i in 0..<150 {
            let col = makeColumn(name: "col_\(i)")
            manager.push(.columnAdd(column: col))
        }

        // Should be capped at 100
        var count = 0
        while manager.undo() != nil {
            count += 1
        }
        #expect(count == 100)
    }

    @Test("clearAll empties both stacks")
    func clearAll() {
        let manager = StructureUndoManager()
        let col = makeColumn()
        manager.push(.columnAdd(column: col))
        manager.push(.columnDelete(column: col))
        _ = manager.undo()

        manager.clearAll()
        #expect(manager.canUndo == false)
        #expect(manager.canRedo == false)
    }
}

// MARK: - StructureChangeManager Undo Integration Tests

@Suite("Structure Change Manager Undo/Redo Integration")
struct StructureChangeManagerUndoTests {

    // MARK: - Helpers

    @MainActor private func makeManager() -> StructureChangeManager {
        let manager = StructureChangeManager()
        return manager
    }

    @MainActor private func loadSampleSchema(_ manager: StructureChangeManager) {
        let columns: [ColumnInfo] = [
            ColumnInfo(name: "id", dataType: "INT", isNullable: false, isPrimaryKey: true,
                       defaultValue: nil, extra: nil, charset: nil, collation: nil, comment: nil),
            ColumnInfo(name: "name", dataType: "VARCHAR(255)", isNullable: true, isPrimaryKey: false,
                       defaultValue: nil, extra: nil, charset: nil, collation: nil, comment: nil),
            ColumnInfo(name: "email", dataType: "VARCHAR(255)", isNullable: true, isPrimaryKey: false,
                       defaultValue: nil, extra: nil, charset: nil, collation: nil, comment: nil)
        ]
        let indexes: [IndexInfo] = [
            IndexInfo(name: "PRIMARY", columns: ["id"], isUnique: true, isPrimary: true,
                      type: "BTREE")
        ]
        manager.loadSchema(
            tableName: "users",
            columns: columns,
            indexes: indexes,
            foreignKeys: [],
            primaryKey: ["id"],
            databaseType: .mysql
        )
    }

    // MARK: - Column Undo Tests

    @Test("Undo column edit reverts to previous value")
    @MainActor func undoColumnEdit() {
        let manager = makeManager()
        loadSampleSchema(manager)

        // Edit the "name" column
        let nameCol = manager.workingColumns[1]
        var modified = nameCol
        modified.dataType = "TEXT"
        manager.updateColumn(id: nameCol.id, with: modified)

        #expect(manager.workingColumns[1].dataType == "TEXT")
        #expect(manager.hasChanges == true)
        #expect(manager.canUndo == true)

        // Undo should revert
        manager.undo()
        #expect(manager.workingColumns[1].dataType == "VARCHAR(255)")
        #expect(manager.hasChanges == false)
    }

    @Test("Redo column edit re-applies the change")
    @MainActor func redoColumnEdit() {
        let manager = makeManager()
        loadSampleSchema(manager)

        let nameCol = manager.workingColumns[1]
        var modified = nameCol
        modified.dataType = "TEXT"
        manager.updateColumn(id: nameCol.id, with: modified)

        manager.undo()
        #expect(manager.workingColumns[1].dataType == "VARCHAR(255)")

        manager.redo()
        #expect(manager.workingColumns[1].dataType == "TEXT")
        #expect(manager.hasChanges == true)
    }

    @Test("Undo add column removes it")
    @MainActor func undoAddColumn() {
        let manager = makeManager()
        loadSampleSchema(manager)

        let initialCount = manager.workingColumns.count
        manager.addNewColumn()
        #expect(manager.workingColumns.count == initialCount + 1)
        #expect(manager.canUndo == true)

        manager.undo()
        #expect(manager.workingColumns.count == initialCount)
    }

    @Test("Undo delete column restores it")
    @MainActor func undoDeleteColumn() {
        let manager = makeManager()
        loadSampleSchema(manager)

        let emailCol = manager.workingColumns[2]
        manager.deleteColumn(id: emailCol.id)
        #expect(manager.hasChanges == true)
        #expect(manager.canUndo == true)

        manager.undo()
        // Column should be restored (no longer marked as deleted)
        let change = manager.pendingChanges[.column(emailCol.id)]
        #expect(change == nil) // No pending change = restored to original
        #expect(manager.hasChanges == false)
    }

    @Test("Multiple undo operations work in sequence")
    @MainActor func multipleUndos() {
        let manager = makeManager()
        loadSampleSchema(manager)

        // Edit 1: change name type
        let nameCol = manager.workingColumns[1]
        var mod1 = nameCol
        mod1.dataType = "TEXT"
        manager.updateColumn(id: nameCol.id, with: mod1)

        // Edit 2: change email type
        let emailCol = manager.workingColumns[2]
        var mod2 = emailCol
        mod2.dataType = "TEXT"
        manager.updateColumn(id: emailCol.id, with: mod2)

        // Undo edit 2
        manager.undo()
        #expect(manager.workingColumns[2].dataType == "VARCHAR(255)")
        #expect(manager.workingColumns[1].dataType == "TEXT") // edit 1 still applied

        // Undo edit 1
        manager.undo()
        #expect(manager.workingColumns[1].dataType == "VARCHAR(255)")
        #expect(manager.hasChanges == false)
    }

    // MARK: - Index Undo Tests

    @Test("Undo add index removes it")
    @MainActor func undoAddIndex() {
        let manager = makeManager()
        loadSampleSchema(manager)

        let initialCount = manager.workingIndexes.count
        manager.addNewIndex()
        #expect(manager.workingIndexes.count == initialCount + 1)
        #expect(manager.canUndo == true)

        manager.undo()
        #expect(manager.workingIndexes.count == initialCount)
    }

    @Test("Undo delete index restores it")
    @MainActor func undoDeleteIndex() {
        let manager = makeManager()
        loadSampleSchema(manager)

        let primaryIndex = manager.workingIndexes[0]
        manager.deleteIndex(id: primaryIndex.id)
        #expect(manager.hasChanges == true)

        manager.undo()
        let change = manager.pendingChanges[.index(primaryIndex.id)]
        #expect(change == nil)
        #expect(manager.hasChanges == false)
    }

    // MARK: - Foreign Key Undo Tests

    @Test("Undo add foreign key removes it")
    @MainActor func undoAddForeignKey() {
        let manager = makeManager()
        loadSampleSchema(manager)

        let initialCount = manager.workingForeignKeys.count
        manager.addNewForeignKey()
        #expect(manager.workingForeignKeys.count == initialCount + 1)

        manager.undo()
        #expect(manager.workingForeignKeys.count == initialCount)
    }

    // MARK: - Duplicate Row Bug Tests

    @Test("Undo delete of existing column does NOT duplicate the row")
    @MainActor func undoDeleteExistingColumnNoDuplicate() {
        let manager = makeManager()
        loadSampleSchema(manager)

        let initialCount = manager.workingColumns.count  // 3
        let emailCol = manager.workingColumns[2]

        // Delete existing column (kept in workingColumns for strikethrough)
        manager.deleteColumn(id: emailCol.id)
        #expect(manager.workingColumns.count == initialCount) // Still 3 (strikethrough)
        #expect(manager.hasChanges == true)

        // Undo should NOT append a duplicate
        manager.undo()
        #expect(manager.workingColumns.count == initialCount) // Still 3, not 4!
        #expect(manager.hasChanges == false)
    }

    @Test("Undo two sequential deletes of existing columns restores both without duplicates")
    @MainActor func undoTwoDeletesNoDuplicates() {
        let manager = makeManager()
        loadSampleSchema(manager)

        let initialCount = manager.workingColumns.count  // 3
        let nameCol = manager.workingColumns[1]
        let emailCol = manager.workingColumns[2]

        // Delete two existing columns
        manager.deleteColumn(id: nameCol.id)
        manager.deleteColumn(id: emailCol.id)
        #expect(manager.workingColumns.count == initialCount) // Still 3 (both kept for strikethrough)

        // Undo delete of email
        manager.undo()
        #expect(manager.workingColumns.count == initialCount) // Still 3
        // email should no longer be marked as deleted
        #expect(manager.pendingChanges[.column(emailCol.id)] == nil)
        // name should still be marked as deleted
        #expect(manager.pendingChanges[.column(nameCol.id)] != nil)

        // Undo delete of name
        manager.undo()
        #expect(manager.workingColumns.count == initialCount) // Still 3
        #expect(manager.pendingChanges[.column(nameCol.id)] == nil)
        #expect(manager.hasChanges == false)
    }

    @Test("Undo delete of NEW column re-adds it")
    @MainActor func undoDeleteNewColumnReAdds() {
        let manager = makeManager()
        loadSampleSchema(manager)

        let initialCount = manager.workingColumns.count  // 3

        // Add a new column
        manager.addNewColumn()
        #expect(manager.workingColumns.count == initialCount + 1)
        let newCol = manager.workingColumns.last!

        // Delete the new column (physically removes it)
        manager.deleteColumn(id: newCol.id)
        #expect(manager.workingColumns.count == initialCount) // Removed

        // Undo should re-add the new column
        manager.undo()
        #expect(manager.workingColumns.count == initialCount + 1)
        #expect(manager.workingColumns.contains(where: { $0.id == newCol.id }))
    }

    // MARK: - Discard Clears Undo

    @Test("Discard changes clears undo stack")
    @MainActor func discardClearsUndo() {
        let manager = makeManager()
        loadSampleSchema(manager)

        manager.addNewColumn()
        #expect(manager.canUndo == true)

        manager.discardChanges()
        #expect(manager.canUndo == false)
        #expect(manager.canRedo == false)
    }
}
