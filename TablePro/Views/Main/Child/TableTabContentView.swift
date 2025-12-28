//
//  TableTabContentView.swift
//  TablePro
//
//  Created by Ngo Quoc Dat on 24/12/25.
//

import SwiftUI

/// Content view for table tabs (results only, no editor)
struct TableTabContentView: View {
    let tab: QueryTab
    let connection: DatabaseConnection
    let changeManager: DataChangeManager
    let filterStateManager: FilterStateManager
    @Binding var selectedRowIndices: Set<Int>
    @Binding var editingCell: CellPosition?
    
    // Callbacks
    let onCommit: (String) -> Void
    let onRefresh: () -> Void
    let onCellEdit: (Int, Int, String?) -> Void
    let onSort: (Int, Bool) -> Void
    let onAddRow: () -> Void
    let onUndoInsert: (Int) -> Void
    let onFilterColumn: (String) -> Void
    let onApplyFilters: ([TableFilter]) -> Void
    let onClearFilters: () -> Void
    let onQuickSearch: (String) -> Void
    let sortedRows: [QueryResultRow]
    
    // Pagination callbacks
    let onFirstPage: () -> Void
    let onPreviousPage: () -> Void
    let onNextPage: () -> Void
    let onLastPage: () -> Void
    let onLimitChange: (Int) -> Void
    let onOffsetChange: (Int) -> Void
    let onPaginationGo: () -> Void
    
    @Binding var sortState: SortState
    @Binding var showStructure: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Error banner (if query failed)
            if let errorMessage = tab.errorMessage, !errorMessage.isEmpty {
                errorBanner(errorMessage)
            }
            
            // Show structure view or data view based on toggle
            if showStructure, let tableName = tab.tableName {
                TableStructureView(tableName: tableName, connection: connection)
                    .frame(maxHeight: .infinity)
            } else {
                DataGridView(
                    rowProvider: InMemoryRowProvider(
                        rows: sortedRows,
                        columns: tab.resultColumns,
                        columnDefaults: tab.columnDefaults
                    ),
                    changeManager: changeManager,
                    isEditable: tab.isEditable,
                    onCommit: onCommit,
                    onRefresh: onRefresh,
                    onCellEdit: onCellEdit,
                    onSort: onSort,
                    onAddRow: onAddRow,
                    onUndoInsert: onUndoInsert,
                    onFilterColumn: onFilterColumn,
                    selectedRowIndices: $selectedRowIndices,
                    sortState: $sortState,
                    editingCell: $editingCell
                )
                .frame(maxHeight: .infinity, alignment: .top)
            }
            
            // Filter panel (collapsible, at bottom)
            if filterStateManager.isVisible && tab.tabType == .table {
                Divider()
                FilterPanelView(
                    filterState: filterStateManager,
                    columns: tab.resultColumns,
                    primaryKeyColumn: changeManager.primaryKeyColumn,
                    databaseType: connection.type,
                    onApply: onApplyFilters,
                    onUnset: onClearFilters,
                    onQuickSearch: onQuickSearch
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Status bar
            MainStatusBarView(
                tab: tab,
                filterStateManager: filterStateManager,
                selectedRowIndices: selectedRowIndices,
                showStructure: $showStructure,
                onFirstPage: onFirstPage,
                onPreviousPage: onPreviousPage,
                onNextPage: onNextPage,
                onLastPage: onLastPage,
                onLimitChange: onLimitChange,
                onOffsetChange: onOffsetChange,
                onPaginationGo: onPaginationGo
            )
        }
    }
    
    // MARK: - Error Banner
    
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Native macOS error icon
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 16))
                .symbolRenderingMode(.multicolor)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 8)
            
            // Dismiss button - needs to be wired to coordinator
            Button(action: {
                tab.errorMessage = nil
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .opacity(0.6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
