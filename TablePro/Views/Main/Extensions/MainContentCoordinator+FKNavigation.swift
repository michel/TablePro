//
//  MainContentCoordinator+FKNavigation.swift
//  TablePro
//
//  Foreign key navigation operations for MainContentCoordinator
//

import Foundation
import os

private let fkNavigationLogger = Logger(subsystem: "com.TablePro", category: "FKNavigation")

extension MainContentCoordinator {
    // MARK: - Foreign Key Navigation

    /// Navigate to the referenced table filtered by the FK value.
    /// Opens or switches to the referenced table tab with a pre-applied filter
    /// so only the matching row is shown.
    func navigateToFKReference(value: String, fkInfo: ForeignKeyInfo) {
        let referencedTable = fkInfo.referencedTable
        let referencedColumn = fkInfo.referencedColumn

        fkNavigationLogger.debug("FK navigate: \(referencedTable).\(referencedColumn) = \(value)")

        let filter = TableFilter(
            columnName: referencedColumn,
            filterOperator: .equal,
            value: value
        )

        // Get current database context
        let currentDatabase: String
        if let sessionId = DatabaseManager.shared.currentSessionId,
           let session = DatabaseManager.shared.activeSessions[sessionId] {
            currentDatabase = session.connection.database
        } else {
            currentDatabase = connection.database
        }

        // Fast path: referenced table is already the active tab — just apply filter
        if let current = tabManager.selectedTab,
           current.tabType == .table,
           current.tableName == referencedTable,
           current.databaseName == currentDatabase {
            applyFKFilter(filter, for: referencedTable)
            return
        }

        // Open or reuse a tab for the referenced table
        let needsQuery = tabManager.TableProTabSmart(
            tableName: referencedTable,
            hasUnsavedChanges: changeManager.hasChanges,
            databaseType: connection.type,
            isView: false,
            databaseName: currentDatabase
        )

        if needsQuery, let tabIndex = tabManager.selectedTabIndex {
            tabManager.tabs[tabIndex].pagination.reset()
        }

        // Update editable state for menu items
        if let tabIndex = tabManager.selectedTabIndex {
            let tab = tabManager.tabs[tabIndex]
            AppState.shared.isCurrentTabEditable = tab.isEditable && !tab.isView && tab.tableName != nil
            toolbarState.isTableTab = tab.tabType == .table
        }

        if needsQuery {
            // New tab — build filtered query directly, run once
            guard let tabIndex = tabManager.selectedTabIndex else { return }
            let tab = tabManager.tabs[tabIndex]
            let filteredQuery = queryBuilder.buildFilteredQuery(
                tableName: referencedTable,
                filters: [filter],
                columns: tab.resultColumns,
                limit: tab.pagination.pageSize,
                offset: tab.pagination.currentOffset
            )
            tabManager.tabs[tabIndex].query = filteredQuery

            updateFilterState(filter, for: referencedTable)
            runQuery()
        } else {
            // Reused tab already has data — apply filter (rebuilds query + re-runs)
            applyFKFilter(filter, for: referencedTable)
        }
    }

    private func applyFKFilter(_ filter: TableFilter, for tableName: String) {
        applyFilters([filter])
        updateFilterState(filter, for: tableName)
    }

    private func updateFilterState(_ filter: TableFilter, for tableName: String) {
        filterStateManager.filters = [filter]
        filterStateManager.appliedFilters = [filter]
        filterStateManager.isVisible = true
    }
}
