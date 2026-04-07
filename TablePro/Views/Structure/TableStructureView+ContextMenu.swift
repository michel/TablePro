//
//  TableStructureView+ContextMenu.swift
//  TablePro
//
//  Context menu support for table structure rows
//

import AppKit
import Combine
import os
import SwiftUI
import TableProPluginKit
import UniformTypeIdentifiers

// MARK: - Structure Context Menu

extension TableStructureView {
    func makeEmptySpaceMenu() -> NSMenu? {
        guard selectedTab != .ddl, selectedTab != .parts else { return nil }
        guard connection.type.supportsSchemaEditing else { return nil }

        let menu = NSMenu()
        let label: String
        switch selectedTab {
        case .columns: label = String(localized: "Add Column")
        case .indexes: label = String(localized: "Add Index")
        case .foreignKeys: label = String(localized: "Add Foreign Key")
        case .ddl, .parts: return nil
        }

        let target = StructureMenuTarget { [self] in addNewRow() }
        let item = NSMenuItem(title: label, action: #selector(StructureMenuTarget.addNewItem), keyEquivalent: "")
        item.target = target
        item.representedObject = target
        menu.addItem(item)
        return menu
    }

    static let structureRowViewId = NSUserInterfaceItemIdentifier("StructureRowView")

    func makeStructureRowView(
        _ tableView: NSTableView, _ row: Int, _ coordinator: TableViewCoordinator
    ) -> NSTableRowView {
        let rowView = (tableView.makeView(withIdentifier: Self.structureRowViewId, owner: nil)
            as? StructureRowViewWithMenu) ?? StructureRowViewWithMenu()
        rowView.identifier = Self.structureRowViewId
        rowView.coordinator = coordinator
        rowView.rowIndex = row
        rowView.structureTab = selectedTab
        rowView.isStructureEditable = connection.type.supportsSchemaEditing
        rowView.isRowDeleted = structureChangeManager.getVisualState(for: row, tab: selectedTab).isDeleted

        if selectedTab == .foreignKeys, row < structureChangeManager.workingForeignKeys.count {
            rowView.referencedTableName = structureChangeManager.workingForeignKeys[row].referencedTable
        }

        rowView.onCopyName = { [self] indices in handleCopyName(indices) }
        rowView.onCopyDefinition = { [self] indices in handleCopyDefinition(indices) }
        rowView.onNavigateFK = { [self] idx in handleNavigateToFK(idx) }
        rowView.onDuplicate = { [self] indices in handleDuplicateItems(indices) }
        rowView.onDelete = { [self] indices in handleDeleteRows(indices) }
        rowView.onUndoDelete = { [self] _ in handleUndo() }
        return rowView
    }

    private func handleCopyName(_ indices: Set<Int>) {
        let provider = StructureRowProvider(
            changeManager: structureChangeManager, tab: selectedTab, databaseType: connection.type
        )
        let names = indices.sorted().compactMap { provider.row(at: $0)?.first ?? nil }
        guard !names.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(names.joined(separator: "\n"), forType: .string)
    }

    private func handleCopyDefinition(_ indices: Set<Int>) {
        guard let driver = DatabaseManager.shared.driver(for: connection.id) else { return }
        var definitions: [String] = []

        for row in indices.sorted() {
            switch selectedTab {
            case .columns:
                guard row < structureChangeManager.workingColumns.count else { continue }
                let col = structureChangeManager.workingColumns[row]
                if let sql = driver.generateColumnDefinitionSQL(column: col.toPlugin()) {
                    definitions.append(sql)
                }
            case .indexes:
                guard row < structureChangeManager.workingIndexes.count else { continue }
                let idx = structureChangeManager.workingIndexes[row]
                if let sql = driver.generateIndexDefinitionSQL(index: idx.toPlugin(), tableName: tableName) {
                    definitions.append(sql)
                }
            case .foreignKeys:
                guard row < structureChangeManager.workingForeignKeys.count else { continue }
                let fk = structureChangeManager.workingForeignKeys[row]
                if let sql = driver.generateForeignKeyDefinitionSQL(fk: fk.toPlugin()) {
                    definitions.append(sql)
                }
            case .ddl, .parts:
                break
            }
        }

        guard !definitions.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(definitions.joined(separator: "\n"), forType: .string)
    }

    private func handleDuplicateItems(_ indices: Set<Int>) {
        for row in indices.sorted() {
            switch selectedTab {
            case .columns:
                guard row < structureChangeManager.workingColumns.count else { continue }
                var copy = structureChangeManager.workingColumns[row]
                copy = EditableColumnDefinition(
                    id: UUID(), name: copy.name, dataType: copy.dataType, isNullable: copy.isNullable,
                    defaultValue: copy.defaultValue, autoIncrement: copy.autoIncrement, unsigned: copy.unsigned,
                    comment: copy.comment, collation: copy.collation, onUpdate: copy.onUpdate,
                    charset: copy.charset, extra: copy.extra, isPrimaryKey: copy.isPrimaryKey
                )
                structureChangeManager.addColumn(copy)
            case .indexes:
                guard row < structureChangeManager.workingIndexes.count else { continue }
                var copy = structureChangeManager.workingIndexes[row]
                copy = EditableIndexDefinition(
                    id: UUID(), name: copy.name, columns: copy.columns,
                    type: copy.type, isUnique: copy.isUnique, isPrimary: false, comment: copy.comment
                )
                structureChangeManager.addIndex(copy)
            case .foreignKeys:
                guard row < structureChangeManager.workingForeignKeys.count else { continue }
                var copy = structureChangeManager.workingForeignKeys[row]
                copy = EditableForeignKeyDefinition(
                    id: UUID(), name: copy.name, columns: copy.columns,
                    referencedTable: copy.referencedTable, referencedColumns: copy.referencedColumns,
                    onDelete: copy.onDelete, onUpdate: copy.onUpdate
                )
                structureChangeManager.addForeignKey(copy)
            case .ddl, .parts:
                break
            }
        }
    }

    private func handleNavigateToFK(_ row: Int) {
        guard row < structureChangeManager.workingForeignKeys.count else { return }
        let fk = structureChangeManager.workingForeignKeys[row]
        coordinator?.openTableTab(fk.referencedTable, showStructure: false, isView: false)
    }
}
