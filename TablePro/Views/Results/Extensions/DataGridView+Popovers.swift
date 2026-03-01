//
//  DataGridView+Popovers.swift
//  TablePro
//

import AppKit
import SwiftUI

// MARK: - Popover Editors

extension TableViewCoordinator {
    func showDatePickerPopover(tableView: NSTableView, row: Int, column: Int, columnIndex: Int) {
        guard let rowData = rowProvider.row(at: row) else { return }
        let currentValue = rowData.value(at: columnIndex)
        let columnType = rowProvider.columnTypes[columnIndex]

        guard let cellView = tableView.view(atColumn: column, row: row, makeIfNecessary: false) else { return }

        DatePickerPopoverController.shared.show(
            relativeTo: cellView.bounds,
            of: cellView,
            value: currentValue,
            columnType: columnType
        ) { [weak self] newValue in
            guard let self = self else { return }
            guard let rowData = self.rowProvider.row(at: row) else { return }
            let oldValue = rowData.value(at: columnIndex)
            guard oldValue != newValue else { return }

            let columnName = self.rowProvider.columns[columnIndex]
            self.changeManager.recordCellChange(
                rowIndex: row,
                columnIndex: columnIndex,
                columnName: columnName,
                oldValue: oldValue,
                newValue: newValue,
                originalRow: rowData.values
            )

            self.rowProvider.updateValue(newValue, at: row, columnIndex: columnIndex)
            self.onCellEdit?(row, columnIndex, newValue)

            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: column))
        }
    }

    func showForeignKeyPopover(tableView: NSTableView, row: Int, column: Int, columnIndex: Int, fkInfo: ForeignKeyInfo) {
        guard let rowData = rowProvider.row(at: row) else { return }
        let currentValue = rowData.value(at: columnIndex)

        guard let cellView = tableView.view(atColumn: column, row: row, makeIfNecessary: false) else { return }
        guard let databaseType, let connectionId else { return }

        PopoverPresenter.show(
            relativeTo: cellView.bounds,
            of: cellView,
            contentSize: NSSize(width: 420, height: 320)
        ) { [weak self] dismiss in
            ForeignKeyPopoverContentView(
                currentValue: currentValue,
                fkInfo: fkInfo,
                connectionId: connectionId,
                databaseType: databaseType,
                onCommit: { newValue in
                    self?.commitPopoverEdit(
                        tableView: tableView,
                        row: row,
                        column: column,
                        columnIndex: columnIndex,
                        newValue: newValue
                    )
                },
                onDismiss: dismiss
            )
        }
    }

    func showJSONEditorPopover(tableView: NSTableView, row: Int, column: Int, columnIndex: Int) {
        guard let rowData = rowProvider.row(at: row) else { return }
        let currentValue = rowData.value(at: columnIndex)

        guard let cellView = tableView.view(atColumn: column, row: row, makeIfNecessary: false) else { return }

        PopoverPresenter.show(
            relativeTo: cellView.bounds,
            of: cellView,
            contentSize: NSSize(width: 420, height: 340)
        ) { [weak self] dismiss in
            JSONEditorContentView(
                initialValue: currentValue,
                onCommit: { newValue in
                    self?.commitPopoverEdit(
                        tableView: tableView,
                        row: row,
                        column: column,
                        columnIndex: columnIndex,
                        newValue: newValue
                    )
                },
                onDismiss: dismiss
            )
        }
    }

    func showEnumPopover(tableView: NSTableView, row: Int, column: Int, columnIndex: Int) {
        guard let cellView = tableView.view(atColumn: column, row: row, makeIfNecessary: false),
              let rowData = rowProvider.row(at: row) else { return }
        let columnName = rowProvider.columns[columnIndex]
        guard let allowedValues = rowProvider.columnEnumValues[columnName] else { return }

        let currentValue = rowData.value(at: columnIndex)
        let isNullable = rowProvider.columnNullable[columnName] ?? true

        var values: [String] = []
        if isNullable {
            values.append("\u{2300} NULL")
        }
        values.append(contentsOf: allowedValues)

        PopoverPresenter.show(
            relativeTo: cellView.bounds,
            of: cellView
        ) { [weak self] dismiss in
            EnumPopoverContentView(
                allValues: values,
                currentValue: currentValue,
                isNullable: isNullable,
                onCommit: { newValue in
                    self?.commitPopoverEdit(tableView: tableView, row: row, column: column, columnIndex: columnIndex, newValue: newValue)
                },
                onDismiss: dismiss
            )
        }
    }

    func showSetPopover(tableView: NSTableView, row: Int, column: Int, columnIndex: Int) {
        guard let cellView = tableView.view(atColumn: column, row: row, makeIfNecessary: false),
              let rowData = rowProvider.row(at: row) else { return }
        let columnName = rowProvider.columns[columnIndex]
        guard let allowedValues = rowProvider.columnEnumValues[columnName] else { return }

        let currentValue = rowData.value(at: columnIndex)

        let currentSet: Set<String>
        if let value = currentValue {
            currentSet = Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        } else {
            currentSet = []
        }
        var selections: [String: Bool] = [:]
        for value in allowedValues {
            selections[value] = currentSet.contains(value)
        }

        PopoverPresenter.show(
            relativeTo: cellView.bounds,
            of: cellView
        ) { [weak self] dismiss in
            SetPopoverContentView(
                allowedValues: allowedValues,
                initialSelections: selections,
                onCommit: { newValue in
                    self?.commitPopoverEdit(tableView: tableView, row: row, column: column, columnIndex: columnIndex, newValue: newValue)
                },
                onDismiss: dismiss
            )
        }
    }

    func showDropdownMenu(tableView: NSTableView, row: Int, column: Int, columnIndex: Int) {
        guard let cellView = tableView.view(atColumn: column, row: row, makeIfNecessary: false),
              let rowData = rowProvider.row(at: row) else { return }

        let currentValue = rowData.value(at: columnIndex)
        pendingDropdownRow = row
        pendingDropdownColumn = columnIndex

        let menu = NSMenu()
        for option in ["YES", "NO"] {
            let item = NSMenuItem(title: option, action: #selector(dropdownMenuItemSelected(_:)), keyEquivalent: "")
            item.target = self
            if option == currentValue {
                item.state = .on
            }
            menu.addItem(item)
        }

        let cellRect = cellView.bounds
        menu.popUp(positioning: nil, at: NSPoint(x: cellRect.minX, y: cellRect.maxY), in: cellView)
    }

    @objc func dropdownMenuItemSelected(_ sender: NSMenuItem) {
        let newValue = sender.title
        guard let rowData = rowProvider.row(at: pendingDropdownRow) else { return }
        let oldValue = rowData.value(at: pendingDropdownColumn)
        guard oldValue != newValue else { return }
        onCellEdit?(pendingDropdownRow, pendingDropdownColumn, newValue)
    }

    func commitPopoverEdit(tableView: NSTableView, row: Int, column: Int, columnIndex: Int, newValue: String?) {
        guard let rowData = rowProvider.row(at: row) else { return }
        let oldValue = rowData.value(at: columnIndex)
        guard oldValue != newValue else { return }

        let columnName = rowProvider.columns[columnIndex]
        changeManager.recordCellChange(
            rowIndex: row,
            columnIndex: columnIndex,
            columnName: columnName,
            oldValue: oldValue,
            newValue: newValue,
            originalRow: rowData.values
        )

        rowProvider.updateValue(newValue, at: row, columnIndex: columnIndex)
        onCellEdit?(row, columnIndex, newValue)

        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: column))
    }
}
