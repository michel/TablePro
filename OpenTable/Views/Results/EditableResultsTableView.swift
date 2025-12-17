//
//  EditableResultsTableView.swift
//  OpenTable
//
//  Results table with inline editing support
//

import SwiftUI
import AppKit

/// Results table that supports inline editing
struct EditableResultsTableView: View {
    let columns: [String]
    @Binding var rows: [QueryResultRow]
    @ObservedObject var changeManager: DataChangeManager
    let isEditable: Bool
    var onCommit: ((String) -> Void)?  // Callback to execute SQL
    
    @State private var selectedRowIndex: Int?
    @State private var sortColumn: Int?
    @State private var sortAscending: Bool = true
    @State private var showingSQLPreview: Bool = false
    @State private var sqlPreviewText: String = ""
    @State private var columnWidths: [Int: CGFloat] = [:]  // Resizable column widths
    
    private let defaultColumnWidth: CGFloat = 150
    private let minColumnWidth: CGFloat = 80
    private let rowNumberWidth: CGFloat = 40
    
    var body: some View {
        GeometryReader { geometry in
            tableContent
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .onChange(of: columns) { _, _ in
            // Reset column widths when switching to different table
            columnWidths = [:]
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "table")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            
            Text("No Results")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Execute a query to see results")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Table Content
    
    private var tableContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Change indicator bar
            if changeManager.hasChanges {
                changeIndicatorBar
            }
            
            if columns.isEmpty {
                // No columns - show minimal empty state
                VStack(spacing: 8) {
                    Image(systemName: "table")
                        .font(.system(size: 32))
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Table with synchronized scrolling
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header row
                        headerRow
                        
                        Divider()
                        
                        // Scrollable data rows (vertical only)
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                                    rowView(rowIndex: rowIndex, row: row)
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingSQLPreview) {
            SQLPreviewSheet(
                sql: sqlPreviewText,
                isPresented: $showingSQLPreview,
                onExecute: { sql in
                    onCommit?(sql)
                    changeManager.discardChanges()
                }
            )
        }
    }
    
    // MARK: - Change Indicator Bar
    
    private var changeIndicatorBar: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            
            Text("\(changeManager.changes.count) pending change(s)")
                .font(.caption)
            
            Spacer()
            
            Button("Discard") {
                changeManager.discardChanges()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            
            Button("Commit (⌘S)") {
                commitChanges()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
    }
    
    // MARK: - Header Row
    
    private func widthForColumn(_ index: Int) -> CGFloat {
        columnWidths[index] ?? defaultColumnWidth
    }
    
    private var headerRow: some View {
        HStack(spacing: 0) {
            // Row number column
            Text("#")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: rowNumberWidth)
            
            Divider()
                .frame(height: 20)
            
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                HStack(spacing: 0) {
                    // Column header content
                    HStack(spacing: 4) {
                        Text(column)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        
                        if sortColumn == index {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSort(column: index) }
                    
                    // Resize handle
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 4)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let newWidth = max(minColumnWidth, widthForColumn(index) + value.translation.width)
                                    columnWidths[index] = newWidth
                                }
                        )
                        .onHover { hovering in
                            if hovering {
                                NSCursor.resizeLeftRight.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                }
                .frame(width: widthForColumn(index))
                
                if index < columns.count - 1 {
                    Divider()
                        .frame(height: 20)
                }
            }
        }
        .frame(height: 28)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Row View
    
    private func rowView(rowIndex: Int, row: QueryResultRow) -> some View {
        let isDeleted = changeManager.isRowDeleted(rowIndex)
        let isSelected = selectedRowIndex == rowIndex
        
        return HStack(spacing: 0) {
            // Row number
            HStack {
                Text("\(rowIndex + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if isEditable && !isDeleted {
                    Button(action: { deleteRow(rowIndex: rowIndex, row: row) }) {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.borderless)
                    .opacity(isSelected ? 1 : 0)
                }
            }
            .frame(width: rowNumberWidth)
            .padding(.vertical, 4)
            
            Divider()
            
            ForEach(Array(columns.enumerated()), id: \.offset) { colIndex, _ in
                cellView(row: row, rowIndex: rowIndex, colIndex: colIndex, isDeleted: isDeleted)
                
                if colIndex < columns.count - 1 {
                    Divider()
                }
            }
        }
        .background(rowBackground(rowIndex: rowIndex, isDeleted: isDeleted, isSelected: isSelected))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedRowIndex = rowIndex
        }
        .contextMenu {
            if isEditable {
                rowContextMenu(rowIndex: rowIndex, row: row, isDeleted: isDeleted)
            }
        }
    }
    
    private func rowBackground(rowIndex: Int, isDeleted: Bool, isSelected: Bool) -> Color {
        if isDeleted {
            return Color.red.opacity(0.1)
        } else if isSelected {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.3)
        } else if rowIndex % 2 == 1 {
            return Color(nsColor: .alternatingContentBackgroundColors[1])
        }
        return Color.clear
    }
    
    @ViewBuilder
    private func cellView(row: QueryResultRow, rowIndex: Int, colIndex: Int, isDeleted: Bool) -> some View {
        let value = colIndex < row.values.count ? row.values[colIndex] : nil
        
        if isEditable {
            EditableCell(
                value: value,
                isModified: changeManager.isCellModified(rowIndex: rowIndex, columnIndex: colIndex),
                isDeleted: isDeleted,
                onEdit: { newValue in
                    handleCellEdit(rowIndex: rowIndex, columnIndex: colIndex, oldValue: value, newValue: newValue)
                }
            )
            .padding(.horizontal, 8)
            .frame(width: widthForColumn(colIndex))
        } else {
            Text(value ?? "NULL")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(value == nil ? .secondary.opacity(0.5) : .primary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(width: widthForColumn(colIndex), alignment: .leading)
        }
    }
    
    // MARK: - Context Menu
    
    @ViewBuilder
    private func rowContextMenu(rowIndex: Int, row: QueryResultRow, isDeleted: Bool) -> some View {
        if isDeleted {
            Button("Undo Delete") {
                undoDeleteRow(rowIndex: rowIndex)
            }
        } else {
            Button("Delete Row") {
                deleteRow(rowIndex: rowIndex, row: row)
            }
            
            Divider()
            
            Button("Copy Row") {
                copyRow(row: row)
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleCellEdit(rowIndex: Int, columnIndex: Int, oldValue: String?, newValue: String?) {
        changeManager.recordCellChange(
            rowIndex: rowIndex,
            columnIndex: columnIndex,
            columnName: columns[columnIndex],
            oldValue: oldValue,
            newValue: newValue
        )
        
        // Update the local row data
        if rowIndex < rows.count && columnIndex < rows[rowIndex].values.count {
            rows[rowIndex].values[columnIndex] = newValue
        }
    }
    
    private func deleteRow(rowIndex: Int, row: QueryResultRow) {
        changeManager.recordRowDeletion(rowIndex: rowIndex, originalRow: row.values)
    }
    
    private func undoDeleteRow(rowIndex: Int) {
        changeManager.changes.removeAll { $0.rowIndex == rowIndex && $0.type == .delete }
        changeManager.hasChanges = !changeManager.changes.isEmpty
    }
    
    private func copyRow(row: QueryResultRow) {
        let text = row.values.map { $0 ?? "NULL" }.joined(separator: "\t")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    private func toggleSort(column: Int) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
        
        // Sort rows
        rows.sort { row1, row2 in
            let val1 = row1.values[safe: column] ?? nil
            let val2 = row2.values[safe: column] ?? nil
            
            switch (val1, val2) {
            case (nil, nil): return false
            case (nil, _): return !sortAscending
            case (_, nil): return sortAscending
            case let (v1?, v2?):
                return sortAscending ? v1 < v2 : v1 > v2
            }
        }
    }
    
    private func commitChanges() {
        let statements = changeManager.generateSQL()
        sqlPreviewText = statements.joined(separator: ";\n")
        showingSQLPreview = true
    }
}

// MARK: - SQL Preview Sheet

struct SQLPreviewSheet: View {
    let sql: String
    @Binding var isPresented: Bool
    var onExecute: ((String) -> Void)?
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Generated SQL")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
            }
            
            if sql.isEmpty {
                Text("No changes to commit")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(sql)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            HStack {
                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(sql, forType: .string)
                }
                .disabled(sql.isEmpty)
                
                Spacer()
                
                Button("Execute") {
                    onExecute?(sql)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(sql.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding()
        .frame(width: 550, height: 400)
    }
}

#Preview {
    EditableResultsTableView(
        columns: ["id", "name", "email"],
        rows: .constant([
            QueryResultRow(values: ["1", "John", "john@example.com"]),
            QueryResultRow(values: ["2", "Jane", "jane@example.com"]),
            QueryResultRow(values: ["3", nil, "test@example.com"])
        ]),
        changeManager: DataChangeManager(),
        isEditable: true
    )
    .frame(width: 600, height: 300)
}
