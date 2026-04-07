//
//  TableStructureView+Editing.swift
//  TablePro
//
//  Event handlers, undo/redo, and copy/paste for table structure editing
//

import AppKit
import Combine
import os
import SwiftUI
import TableProPluginKit
import UniformTypeIdentifiers

// MARK: - Event Handlers

extension TableStructureView {
    func handleCellEdit(_ row: Int, _ column: Int, _ value: String?) {
        // column parameter is already adjusted for row number column by DataGridView
        guard column >= 0 else { return }

        switch selectedTab {
        case .columns:
            guard row < structureChangeManager.workingColumns.count else { return }
            var col = structureChangeManager.workingColumns[row]
            updateColumn(&col, at: column, with: value ?? "")
            structureChangeManager.updateColumn(id: col.id, with: col)

        case .indexes:
            guard row < structureChangeManager.workingIndexes.count else { return }
            var idx = structureChangeManager.workingIndexes[row]
            updateIndex(&idx, at: column, with: value ?? "")
            structureChangeManager.updateIndex(id: idx.id, with: idx)

        case .foreignKeys:
            guard row < structureChangeManager.workingForeignKeys.count else { return }
            var fk = structureChangeManager.workingForeignKeys[row]
            updateForeignKey(&fk, at: column, with: value ?? "")
            structureChangeManager.updateForeignKey(id: fk.id, with: fk)

        case .ddl:
            break
        case .parts:
            break
        }
    }

    private func updateColumn(_ column: inout EditableColumnDefinition, at index: Int, with value: String) {
        if connection.type == .clickhouse {
            // ClickHouse: Name(0), Type(1), Nullable(2), Default(3), Comment(4) — no Auto Inc
            switch index {
            case 0: column.name = value
            case 1: column.dataType = value
            case 2: column.isNullable = value.uppercased() == "YES" || value == "1"
            case 3: column.defaultValue = value.isEmpty ? nil : value
            case 4: column.comment = value.isEmpty ? nil : value
            default: break
            }
        } else {
            switch index {
            case 0: column.name = value
            case 1: column.dataType = value
            case 2: column.isNullable = value.uppercased() == "YES" || value == "1"
            case 3: column.defaultValue = value.isEmpty ? nil : value
            case 4: column.autoIncrement = value.uppercased() == "YES" || value == "1"
            case 5: column.comment = value.isEmpty ? nil : value
            default: break
            }
        }
    }

    private func updateIndex(_ index: inout EditableIndexDefinition, at colIndex: Int, with value: String) {
        switch colIndex {
        case 0: index.name = value
        case 1: index.columns = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        case 2:
            if let indexType = EditableIndexDefinition.IndexType(rawValue: value.uppercased()) {
                index.type = indexType
            }
        case 3: index.isUnique = value.uppercased() == "YES" || value == "1"
        default: break
        }
    }

    private func updateForeignKey(_ fk: inout EditableForeignKeyDefinition, at index: Int, with value: String) {
        switch index {
        case 0: fk.name = value
        case 1: fk.columns = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        case 2: fk.referencedTable = value
        case 3: fk.referencedColumns = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        case 4:
            if let action = EditableForeignKeyDefinition.ReferentialAction(rawValue: value.uppercased()) {
                fk.onDelete = action
            }
        case 5:
            if let action = EditableForeignKeyDefinition.ReferentialAction(rawValue: value.uppercased()) {
                fk.onUpdate = action
            }
        default: break
        }
    }

    func handleDeleteRows(_ rows: Set<Int>) {
        // Find min/max for smart selection after delete
        let minRow = rows.min() ?? 0
        let maxRow = rows.max() ?? 0

        switch selectedTab {
        case .columns:
            for row in rows.sorted(by: >) {
                guard row < structureChangeManager.workingColumns.count else { continue }
                let column = structureChangeManager.workingColumns[row]
                structureChangeManager.deleteColumn(id: column.id)
            }
        case .indexes:
            for row in rows.sorted(by: >) {
                guard row < structureChangeManager.workingIndexes.count else { continue }
                let index = structureChangeManager.workingIndexes[row]
                structureChangeManager.deleteIndex(id: index.id)
            }
        case .foreignKeys:
            for row in rows.sorted(by: >) {
                guard row < structureChangeManager.workingForeignKeys.count else { continue }
                let fk = structureChangeManager.workingForeignKeys[row]
                structureChangeManager.deleteForeignKey(id: fk.id)
            }
        case .parts:
            selectedRows.removeAll()
            return
        case .ddl:
            selectedRows.removeAll()
            return
        }

        // Smart selection after delete (same as data grid behavior)
        let newCount: Int
        switch selectedTab {
        case .columns:
            newCount = structureChangeManager.workingColumns.count
        case .indexes:
            newCount = structureChangeManager.workingIndexes.count
        case .foreignKeys:
            newCount = structureChangeManager.workingForeignKeys.count
        case .ddl:
            newCount = 0
        case .parts:
            newCount = 0
        }

        // Calculate next row to select
        if newCount > 0 {
            if maxRow < newCount {
                // Select row after the deleted range
                selectedRows = [maxRow]
            } else if minRow > 0 {
                // Deleted at end, select previous row
                selectedRows = [minRow - 1]
            } else {
                // Deleted first row(s), select row 0 if exists
                selectedRows = [0]
            }
        } else {
            // No rows left
            selectedRows.removeAll()
        }
    }

    func addNewRow() {
        switch selectedTab {
        case .columns:
            structureChangeManager.addNewColumn()
        case .indexes:
            structureChangeManager.addNewIndex()
        case .foreignKeys:
            structureChangeManager.addNewForeignKey()
        case .ddl:
            break
        case .parts:
            break
        }
    }

    // MARK: - Undo/Redo

    func handleUndo() {
        guard selectedTab != .ddl else { return }
        structureChangeManager.undo()
    }

    func handleRedo() {
        guard selectedTab != .ddl else { return }
        structureChangeManager.redo()
    }

    // MARK: - Copy/Paste

    // Custom pasteboard type for structure data (to avoid conflicts with data grid)
    static let structurePasteboardType = NSPasteboard.PasteboardType("com.TablePro.structure")

    func handleCopyRows(_ rowIndices: Set<Int>) {
        guard selectedTab != .ddl, selectedTab != .parts, !rowIndices.isEmpty else { return }

        var copiedItems: [Any] = []

        switch selectedTab {
        case .columns:
            for row in rowIndices.sorted() {
                guard row < structureChangeManager.workingColumns.count else { continue }
                let column = structureChangeManager.workingColumns[row]
                copiedItems.append(column)
            }
        case .indexes:
            for row in rowIndices.sorted() {
                guard row < structureChangeManager.workingIndexes.count else { continue }
                let index = structureChangeManager.workingIndexes[row]
                copiedItems.append(index)
            }
        case .foreignKeys:
            for row in rowIndices.sorted() {
                guard row < structureChangeManager.workingForeignKeys.count else { continue }
                let fk = structureChangeManager.workingForeignKeys[row]
                copiedItems.append(fk)
            }
        case .ddl, .parts:
            break
        }

        // Store in pasteboard with both custom JSON type (internal paste) and TSV (external paste)
        guard !copiedItems.isEmpty else { return }

        // Build JSON string for custom pasteboard type
        var jsonString: String?
        if let columns = copiedItems as? [EditableColumnDefinition],
           let encoded = try? JSONEncoder().encode(columns) {
            jsonString = String(data: encoded, encoding: .utf8)
        } else if let indexes = copiedItems as? [EditableIndexDefinition],
                  let encoded = try? JSONEncoder().encode(indexes) {
            jsonString = String(data: encoded, encoding: .utf8)
        } else if let fks = copiedItems as? [EditableForeignKeyDefinition],
                  let encoded = try? JSONEncoder().encode(fks) {
            jsonString = String(data: encoded, encoding: .utf8)
        }

        // Build TSV string for external paste
        let provider = StructureRowProvider(changeManager: structureChangeManager, tab: selectedTab, databaseType: connection.type)
        var lines: [String] = []
        for row in rowIndices.sorted() {
            guard let rowData = provider.row(at: row) else { continue }
            let line = rowData.map { $0 ?? "NULL" }.joined(separator: "\t")
            lines.append(line)
        }
        let tsvString = lines.joined(separator: "\n")

        // Write both types on a single pasteboard item
        let item = NSPasteboardItem()
        if let json = jsonString {
            item.setString(json, forType: Self.structurePasteboardType)
        }
        if !tsvString.isEmpty {
            item.setString(tsvString, forType: .string)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    func handlePaste() {
        guard let data = NSPasteboard.general.data(forType: Self.structurePasteboardType),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        // Try to parse as copied structure items
        let decoder = JSONDecoder()

        switch selectedTab {
        case .columns:
            guard let columns = try? decoder.decode([EditableColumnDefinition].self, from: Data(jsonString.utf8)) else {
                return
            }
            // Create copies with new IDs
            for item in columns {
                let newColumn = EditableColumnDefinition(
                    id: UUID(),
                    name: item.name,
                    dataType: item.dataType,
                    isNullable: item.isNullable,
                    defaultValue: item.defaultValue,
                    autoIncrement: item.autoIncrement,
                    unsigned: item.unsigned,
                    comment: item.comment,
                    collation: item.collation,
                    onUpdate: item.onUpdate,
                    charset: item.charset,
                    extra: item.extra,
                    isPrimaryKey: item.isPrimaryKey
                )
                structureChangeManager.addColumn(newColumn)
            }

        case .indexes:
            guard let indexes = try? decoder.decode([EditableIndexDefinition].self, from: Data(jsonString.utf8)) else {
                return
            }
            for item in indexes {
                let newIndex = EditableIndexDefinition(
                    id: UUID(),
                    name: item.name,
                    columns: item.columns,
                    type: item.type,
                    isUnique: item.isUnique,
                    isPrimary: item.isPrimary,
                    comment: item.comment
                )
                structureChangeManager.addIndex(newIndex)
            }

        case .foreignKeys:
            guard let fks = try? decoder.decode([EditableForeignKeyDefinition].self, from: Data(jsonString.utf8)) else {
                return
            }
            for item in fks {
                let newFK = EditableForeignKeyDefinition(
                    id: UUID(),
                    name: item.name,
                    columns: item.columns,
                    referencedTable: item.referencedTable,
                    referencedColumns: item.referencedColumns,
                    onDelete: item.onDelete,
                    onUpdate: item.onUpdate
                )
                structureChangeManager.addForeignKey(newFK)
            }

        case .ddl:
            break
        case .parts:
            break
        }
    }
}
