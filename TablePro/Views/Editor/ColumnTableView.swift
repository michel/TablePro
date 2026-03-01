//
//  ColumnTableView.swift
//  TablePro
//
//  Table-style column editor with sticky header and inline editing.
//

import SwiftUI
import UniformTypeIdentifiers

struct ColumnTableView: View {
    @Binding var columns: [ColumnDefinition]
    @Binding var primaryKeyColumns: [String]
    let databaseType: DatabaseType
    let onDelete: (ColumnDefinition) -> Void

    @State private var draggedColumn: ColumnDefinition?

    private var showAutoIncrement: Bool {
        databaseType == .mysql || databaseType == .mariadb || databaseType == .sqlite
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            Divider()

            if columns.isEmpty {
                EmptyStateView.columns {
                    addColumn()
                }
            } else {
                List {
                    ForEach(columns) { column in
                        ColumnTableRow(
                            column: columnBinding(for: column),
                            isPrimaryKey: primaryKeyBinding(for: column),
                            databaseType: databaseType,
                            showAutoIncrement: showAutoIncrement,
                            onDelete: { onDelete(column) }
                        )
                        .onDrag {
                            draggedColumn = column
                            return NSItemProvider(object: column.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: ColumnTableDropDelegate(
                            column: column,
                            columns: $columns,
                            draggedColumn: $draggedColumn
                        ))
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: DesignConstants.ColumnWidth.dragHandle)

            Text("Name")
                .frame(minWidth: DesignConstants.ColumnWidth.nameMin, maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignConstants.Spacing.xxs)

            Text("Type")
                .frame(minWidth: DesignConstants.ColumnWidth.typeMin, maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignConstants.Spacing.xxs)

            Text("Length")
                .frame(width: DesignConstants.ColumnWidth.length, alignment: .leading)
                .padding(.horizontal, DesignConstants.Spacing.xxs)

            Text("Default")
                .frame(minWidth: DesignConstants.ColumnWidth.defaultMin, maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignConstants.Spacing.xxs)

            Text("PK")
                .frame(width: DesignConstants.ColumnWidth.checkbox, alignment: .center)

            Text("NN")
                .frame(width: DesignConstants.ColumnWidth.checkbox, alignment: .center)

            if showAutoIncrement {
                Text("AI")
                    .frame(width: DesignConstants.ColumnWidth.checkbox, alignment: .center)
            }

            Text("")
                .frame(width: DesignConstants.ColumnWidth.checkbox)
        }
        .font(.system(size: DesignConstants.FontSize.small, weight: .semibold))
        .foregroundStyle(DesignConstants.Colors.secondaryText)
        .frame(height: DesignConstants.RowHeight.table)
        .frame(maxWidth: .infinity)
        .background(DesignConstants.Colors.sectionBackground.opacity(0.5))
    }

    // MARK: - Bindings

    private func columnBinding(for column: ColumnDefinition) -> Binding<ColumnDefinition> {
        Binding(
            get: { column },
            set: { newValue in
                if let idx = columns.firstIndex(where: { $0.id == column.id }) {
                    columns[idx] = newValue
                }
            }
        )
    }

    private func primaryKeyBinding(for column: ColumnDefinition) -> Binding<Bool> {
        Binding(
            get: { primaryKeyColumns.contains(column.name) },
            set: { isOn in
                if isOn {
                    if !primaryKeyColumns.contains(column.name) {
                        primaryKeyColumns.append(column.name)
                    }
                } else {
                    primaryKeyColumns.removeAll { $0 == column.name }
                }
            }
        )
    }

    // MARK: - Actions

    private func addColumn() {
        let newColumn = ColumnDefinition(
            name: "column_\(columns.count + 1)",
            dataType: "VARCHAR",
            length: 255
        )
        columns.append(newColumn)
    }
}

// MARK: - Drop Delegate

struct ColumnTableDropDelegate: DropDelegate {
    let column: ColumnDefinition
    @Binding var columns: [ColumnDefinition]
    @Binding var draggedColumn: ColumnDefinition?

    func performDrop(info: DropInfo) -> Bool {
        draggedColumn = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedColumn = draggedColumn,
              draggedColumn.id != column.id,
              let fromIndex = columns.firstIndex(where: { $0.id == draggedColumn.id }),
              let toIndex = columns.firstIndex(where: { $0.id == column.id }) else {
            return
        }

        withAnimation(.easeInOut(duration: DesignConstants.AnimationDuration.normal)) {
            columns.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }
}
