//
//  ExportTableTreeView.swift
//  TablePro
//
//  Pure SwiftUI tree view for selecting tables in the export dialog.
//  Replaces the NSOutlineView-based ExportTableOutlineView.
//

import AppKit
import SwiftUI

struct ExportTableTreeView: View {
    @Binding var databaseItems: [ExportDatabaseItem]
    let format: ExportFormat

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach($databaseItems) { $database in
                    DisclosureGroup(isExpanded: $database.isExpanded) {
                        ForEach($database.tables) { $table in
                            tableRow(table: $table)
                        }
                    } label: {
                        databaseLabel(database: database, allTables: $database.tables)
                    }
                }
            }
            .listStyle(.plain)
            .alternatingRowBackgrounds(.enabled)
        }
    }

    // MARK: - Database Row

    private func databaseLabel(
        database: ExportDatabaseItem,
        allTables: Binding<[ExportTableItem]>
    ) -> some View {
        HStack(spacing: 4) {
            TristateCheckbox(
                state: databaseCheckboxState(database),
                action: {
                    let newState = !database.allSelected
                    for index in allTables.wrappedValue.indices {
                        allTables[index].isSelected.wrappedValue = newState
                        if newState && format == .sql {
                            if !allTables[index].sqlOptions.wrappedValue.hasAnyOption {
                                allTables[index].sqlOptions.wrappedValue = SQLTableExportOptions()
                            }
                        }
                        if newState && format == .mql {
                            if !allTables[index].mqlOptions.wrappedValue.hasAnyOption {
                                allTables[index].mqlOptions.wrappedValue = MQLTableExportOptions()
                            }
                        }
                    }
                }
            )
            .disabled(database.tables.isEmpty)
            .frame(width: 18)

            Image(systemName: "cylinder")
                .foregroundStyle(.blue)
                .font(.system(size: 13))

            Text(database.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func databaseCheckboxState(_ database: ExportDatabaseItem) -> TristateCheckbox.State {
        let selected = database.selectedCount
        if selected == 0 { return .unchecked }
        if selected == database.tables.count { return .checked }
        return .mixed
    }

    // MARK: - Table Row

    private func tableRow(table: Binding<ExportTableItem>) -> some View {
        HStack(spacing: 4) {
            if format == .sql {
                TristateCheckbox(
                    state: sqlTableCheckboxState(table.wrappedValue),
                    action: {
                        toggleTableSQLOptions(table)
                    }
                )
                .frame(width: 18)
            } else if format == .mql {
                TristateCheckbox(
                    state: mqlTableCheckboxState(table.wrappedValue),
                    action: {
                        toggleTableMQLOptions(table)
                    }
                )
                .frame(width: 18)
            } else {
                Toggle("", isOn: table.isSelected)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }

            Image(systemName: table.wrappedValue.type == .view ? "eye" : "tablecells")
                .foregroundStyle(table.wrappedValue.type == .view ? .purple : .gray)
                .font(.system(size: 13))

            Text(table.wrappedValue.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)

            if format == .sql {
                Spacer()

                Toggle("Structure", isOn: table.sqlOptions.includeStructure)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!table.wrappedValue.isSelected)
                    .opacity(table.wrappedValue.isSelected ? 1.0 : 0.4)
                    .frame(width: 56, alignment: .center)
                    .onChange(of: table.wrappedValue.sqlOptions) { _, newOptions in
                        table.isSelected.wrappedValue = newOptions.hasAnyOption
                    }

                Toggle("Drop", isOn: table.sqlOptions.includeDrop)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!table.wrappedValue.isSelected)
                    .opacity(table.wrappedValue.isSelected ? 1.0 : 0.4)
                    .frame(width: 44, alignment: .center)

                Toggle("Data", isOn: table.sqlOptions.includeData)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!table.wrappedValue.isSelected)
                    .opacity(table.wrappedValue.isSelected ? 1.0 : 0.4)
                    .frame(width: 44, alignment: .center)
            } else if format == .mql {
                Spacer()

                Toggle("Drop", isOn: table.mqlOptions.includeDrop)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!table.wrappedValue.isSelected)
                    .opacity(table.wrappedValue.isSelected ? 1.0 : 0.4)
                    .frame(width: 44, alignment: .center)
                    .onChange(of: table.wrappedValue.mqlOptions) { _, newOptions in
                        table.isSelected.wrappedValue = newOptions.hasAnyOption
                    }

                Toggle("Indexes", isOn: table.mqlOptions.includeIndexes)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!table.wrappedValue.isSelected)
                    .opacity(table.wrappedValue.isSelected ? 1.0 : 0.4)
                    .frame(width: 44, alignment: .center)

                Toggle("Data", isOn: table.mqlOptions.includeData)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!table.wrappedValue.isSelected)
                    .opacity(table.wrappedValue.isSelected ? 1.0 : 0.4)
                    .frame(width: 44, alignment: .center)
            }
        }
    }

    private func sqlTableCheckboxState(_ table: ExportTableItem) -> TristateCheckbox.State {
        let opts = table.sqlOptions
        let count = (opts.includeStructure ? 1 : 0) + (opts.includeDrop ? 1 : 0) + (opts.includeData ? 1 : 0)
        if !table.isSelected || count == 0 { return .unchecked }
        if count == 3 { return .checked }
        return .mixed
    }

    private func toggleTableSQLOptions(_ table: Binding<ExportTableItem>) {
        if !table.wrappedValue.isSelected {
            table.isSelected.wrappedValue = true
            if !table.wrappedValue.sqlOptions.hasAnyOption {
                table.sqlOptions.includeStructure.wrappedValue = true
                table.sqlOptions.includeDrop.wrappedValue = true
                table.sqlOptions.includeData.wrappedValue = true
            }
        } else {
            let opts = table.wrappedValue.sqlOptions
            let allChecked = opts.includeStructure && opts.includeDrop && opts.includeData

            if allChecked {
                table.isSelected.wrappedValue = false
            } else {
                table.sqlOptions.includeStructure.wrappedValue = true
                table.sqlOptions.includeDrop.wrappedValue = true
                table.sqlOptions.includeData.wrappedValue = true
            }
        }
    }

    private func mqlTableCheckboxState(_ table: ExportTableItem) -> TristateCheckbox.State {
        let opts = table.mqlOptions
        let count = (opts.includeDrop ? 1 : 0) + (opts.includeIndexes ? 1 : 0) + (opts.includeData ? 1 : 0)
        if !table.isSelected || count == 0 { return .unchecked }
        if count == 3 { return .checked }
        return .mixed
    }

    private func toggleTableMQLOptions(_ table: Binding<ExportTableItem>) {
        if !table.wrappedValue.isSelected {
            table.isSelected.wrappedValue = true
            if !table.wrappedValue.mqlOptions.hasAnyOption {
                table.mqlOptions.includeDrop.wrappedValue = true
                table.mqlOptions.includeData.wrappedValue = true
                table.mqlOptions.includeIndexes.wrappedValue = true
            }
        } else {
            let opts = table.wrappedValue.mqlOptions
            let allChecked = opts.includeDrop && opts.includeData && opts.includeIndexes

            if allChecked {
                table.isSelected.wrappedValue = false
            } else {
                table.mqlOptions.includeDrop.wrappedValue = true
                table.mqlOptions.includeData.wrappedValue = true
                table.mqlOptions.includeIndexes.wrappedValue = true
            }
        }
    }
}

// MARK: - Tristate Checkbox

/// Native macOS tristate checkbox using NSButton
private struct TristateCheckbox: NSViewRepresentable {
    enum State {
        case unchecked, checked, mixed
    }

    let state: State
    let action: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.clicked))
        button.allowsMixedState = true
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        switch state {
        case .unchecked: button.state = .off
        case .checked: button.state = .on
        case .mixed: button.state = .mixed
        }
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) {
            self.action = action
        }
        @objc func clicked() {
            action()
        }
    }
}
