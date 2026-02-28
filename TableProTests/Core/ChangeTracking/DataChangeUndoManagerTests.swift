//
//  DataChangeUndoManagerTests.swift
//  TableProTests
//
//  Tests for DataChangeUndoManager
//

import Foundation
@testable import TablePro
import Testing

@Suite("Data Change Undo Manager")
struct DataChangeUndoManagerTests {
    private func makeCellEditAction(row: Int = 0, col: Int = 0) -> UndoAction {
        .cellEdit(rowIndex: row, columnIndex: col, columnName: "col\(col)", previousValue: "old", newValue: "new")
    }

    // MARK: - Initial State Tests

    @Test("Fresh instance has canUndo == false")
    func initialCanUndoFalse() {
        let manager = DataChangeUndoManager()
        #expect(manager.canUndo == false)
    }

    @Test("Fresh instance has canRedo == false")
    func initialCanRedoFalse() {
        let manager = DataChangeUndoManager()
        #expect(manager.canRedo == false)
    }

    @Test("Fresh instance has undoCount == 0")
    func initialUndoCountZero() {
        let manager = DataChangeUndoManager()
        #expect(manager.undoCount == 0)
    }

    @Test("Fresh instance has redoCount == 0")
    func initialRedoCountZero() {
        let manager = DataChangeUndoManager()
        #expect(manager.redoCount == 0)
    }

    // MARK: - Push Tests

    @Test("Push adds action to undo stack")
    func pushAddsToUndoStack() {
        let manager = DataChangeUndoManager()
        manager.push(makeCellEditAction())
        #expect(manager.canUndo == true)
        #expect(manager.undoCount == 1)
    }

    // MARK: - Pop Tests

    @Test("Pop undo returns last pushed action (LIFO)")
    func popUndoReturnsLastPushedAction() {
        let manager = DataChangeUndoManager()
        let actionA = makeCellEditAction(row: 0)
        let actionB = makeCellEditAction(row: 1)
        manager.push(actionA)
        manager.push(actionB)

        let first = manager.popUndo()
        if case .cellEdit(let rowIndex, _, _, _, _) = first {
            #expect(rowIndex == 1)
        } else {
            Issue.record("Expected cellEdit action")
        }

        let second = manager.popUndo()
        if case .cellEdit(let rowIndex, _, _, _, _) = second {
            #expect(rowIndex == 0)
        } else {
            Issue.record("Expected cellEdit action")
        }
    }

    @Test("Pop undo returns nil when stack is empty")
    func popUndoReturnsNilWhenEmpty() {
        let manager = DataChangeUndoManager()
        #expect(manager.popUndo() == nil)
    }

    @Test("Pop redo returns nil when stack is empty")
    func popRedoReturnsNilWhenEmpty() {
        let manager = DataChangeUndoManager()
        #expect(manager.popRedo() == nil)
    }

    // MARK: - Move Tests

    @Test("moveToRedo adds action to redo stack")
    func moveToRedoAddsToRedoStack() {
        let manager = DataChangeUndoManager()
        manager.moveToRedo(makeCellEditAction())
        #expect(manager.canRedo == true)
        #expect(manager.redoCount == 1)
    }

    @Test("moveToUndo adds action to undo stack")
    func moveToUndoAddsToUndoStack() {
        let manager = DataChangeUndoManager()
        manager.moveToUndo(makeCellEditAction())
        #expect(manager.canUndo == true)
        #expect(manager.undoCount == 1)
    }

    // MARK: - Clear Tests

    @Test("clearUndo empties undo stack only, preserves redo")
    func clearUndoEmptiesUndoOnly() {
        let manager = DataChangeUndoManager()
        manager.push(makeCellEditAction())
        manager.moveToRedo(makeCellEditAction(row: 1))

        manager.clearUndo()

        #expect(manager.canUndo == false)
        #expect(manager.canRedo == true)
    }

    @Test("clearRedo empties redo stack only, preserves undo")
    func clearRedoEmptiesRedoOnly() {
        let manager = DataChangeUndoManager()
        manager.push(makeCellEditAction())
        manager.moveToRedo(makeCellEditAction(row: 1))

        manager.clearRedo()

        #expect(manager.canUndo == true)
        #expect(manager.canRedo == false)
    }

    @Test("clearAll empties both stacks")
    func clearAllEmptiesBoth() {
        let manager = DataChangeUndoManager()
        manager.push(makeCellEditAction())
        manager.moveToRedo(makeCellEditAction(row: 1))

        manager.clearAll()

        #expect(manager.undoCount == 0)
        #expect(manager.redoCount == 0)
    }

    // MARK: - Trimming Tests

    @Test("Undo stack trims to 100 when 101 actions pushed")
    func stackTrimmingAt101Pushes() {
        let manager = DataChangeUndoManager()
        for i in 0 ..< 101 {
            manager.push(makeCellEditAction(row: i))
        }
        #expect(manager.undoCount == 100)
    }

    @Test("Redo stack also trims at max depth")
    func redoStackAlsoTrimsAtMaxDepth() {
        let manager = DataChangeUndoManager()
        for i in 0 ..< 101 {
            manager.moveToRedo(makeCellEditAction(row: i))
        }
        #expect(manager.redoCount == 100)
    }

    // MARK: - Order & Fidelity Tests

    @Test("LIFO order is preserved across multiple pops")
    func lifoOrderPreserved() {
        let manager = DataChangeUndoManager()
        manager.push(makeCellEditAction(row: 0))
        manager.push(makeCellEditAction(row: 1))
        manager.push(makeCellEditAction(row: 2))

        if case .cellEdit(let row, _, _, _, _) = manager.popUndo() {
            #expect(row == 2)
        } else {
            Issue.record("Expected cellEdit action")
        }

        if case .cellEdit(let row, _, _, _, _) = manager.popUndo() {
            #expect(row == 1)
        } else {
            Issue.record("Expected cellEdit action")
        }

        if case .cellEdit(let row, _, _, _, _) = manager.popUndo() {
            #expect(row == 0)
        } else {
            Issue.record("Expected cellEdit action")
        }
    }

    @Test("moveToRedo preserves action fidelity through round-trip")
    func moveToRedoPreservesActionFidelity() {
        let manager = DataChangeUndoManager()
        let action = UndoAction.cellEdit(
            rowIndex: 5,
            columnIndex: 3,
            columnName: "email",
            previousValue: "old@test.com",
            newValue: "new@test.com"
        )

        manager.push(action)
        guard let popped = manager.popUndo() else {
            Issue.record("Expected non-nil undo action")
            return
        }

        manager.moveToRedo(popped)
        let restored = manager.popRedo()

        if case .cellEdit(let rowIndex, let columnIndex, let columnName, let previousValue, let newValue) = restored {
            #expect(rowIndex == 5)
            #expect(columnIndex == 3)
            #expect(columnName == "email")
            #expect(previousValue == "old@test.com")
            #expect(newValue == "new@test.com")
        } else {
            Issue.record("Expected cellEdit action")
        }
    }

    // MARK: - Mixed Operations Test

    @Test("Mixed operations maintain correct counts")
    func mixedOperationsMaintainCorrectCounts() {
        let manager = DataChangeUndoManager()
        manager.push(makeCellEditAction(row: 0))
        manager.push(makeCellEditAction(row: 1))
        manager.push(makeCellEditAction(row: 2))

        guard let action1 = manager.popUndo() else {
            Issue.record("Expected non-nil undo action")
            return
        }
        manager.moveToRedo(action1)

        guard let action2 = manager.popUndo() else {
            Issue.record("Expected non-nil undo action")
            return
        }
        manager.moveToRedo(action2)

        #expect(manager.undoCount == 1)
        #expect(manager.redoCount == 2)
    }
}
