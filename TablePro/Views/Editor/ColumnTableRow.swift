//
//  ColumnTableRow.swift
//  TablePro
//
//  Single row in the column table editor with inline editing controls.
//

import SwiftUI
import UniformTypeIdentifiers

struct ColumnTableRow: View {
    @Binding var column: ColumnDefinition
    @Binding var isPrimaryKey: Bool
    let databaseType: DatabaseType
    let showAutoIncrement: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(DesignConstants.Colors.tertiaryText)
                .frame(width: DesignConstants.ColumnWidth.dragHandle)

            TextField("Column name", text: $column.name)
                .frame(minWidth: DesignConstants.ColumnWidth.nameMin, maxWidth: .infinity)
                .padding(.horizontal, DesignConstants.Spacing.xxs)

            DataTypePicker(selectedType: $column.dataType, databaseType: databaseType)
                .frame(minWidth: DesignConstants.ColumnWidth.typeMin, maxWidth: .infinity)
                .padding(.horizontal, DesignConstants.Spacing.xxs)

            TextField(
                "Length",
                value: $column.length,
                format: .number
            )
            .frame(width: DesignConstants.ColumnWidth.length)
            .padding(.horizontal, DesignConstants.Spacing.xxs)

            TextField("Default", text: Binding(
                get: { column.defaultValue ?? "" },
                set: { column.defaultValue = $0.isEmpty ? nil : $0 }
            ))
            .frame(minWidth: DesignConstants.ColumnWidth.defaultMin, maxWidth: .infinity)
            .padding(.horizontal, DesignConstants.Spacing.xxs)

            Toggle("", isOn: $isPrimaryKey)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: DesignConstants.ColumnWidth.checkbox)

            Toggle("", isOn: $column.notNull)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: DesignConstants.ColumnWidth.checkbox)

            if showAutoIncrement {
                Toggle("", isOn: $column.autoIncrement)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .frame(width: DesignConstants.ColumnWidth.checkbox)
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: DesignConstants.FontSize.caption))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .frame(width: DesignConstants.ColumnWidth.checkbox)
        }
        .frame(height: DesignConstants.RowHeight.table)
    }
}
