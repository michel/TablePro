//
//  DataGridView+TypePicker.swift
//  TablePro
//
//  Extension for database-specific type picker popover in structure view.
//

import AppKit

extension TableViewCoordinator {
    func showTypePickerPopover(
        tableView: NSTableView,
        row: Int,
        column: Int,
        columnIndex: Int
    ) {
        guard let cellView = tableView.view(atColumn: column, row: row, makeIfNecessary: false),
              let rowData = rowProvider.row(at: row) else { return }

        let currentValue = rowData.value(at: columnIndex) ?? ""
        let dbType = databaseType ?? .mysql

        TypePickerPopoverController.shared.show(
            relativeTo: cellView.bounds,
            of: cellView,
            databaseType: dbType,
            currentValue: currentValue
        ) { [weak self] newValue in
            guard let self else { return }
            guard let rowData = self.rowProvider.row(at: row) else { return }
            let oldValue = rowData.value(at: columnIndex)
            guard oldValue != newValue else { return }

            self.rowProvider.updateValue(newValue, at: row, columnIndex: columnIndex)
            self.onCellEdit?(row, columnIndex, newValue)

            tableView.reloadData(
                forRowIndexes: IndexSet(integer: row),
                columnIndexes: IndexSet(integer: column)
            )
        }
    }
}
