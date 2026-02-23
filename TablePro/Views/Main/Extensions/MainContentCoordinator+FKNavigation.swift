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
    /// Opens or switches to the referenced table tab, then applies a filter
    /// so only matching rows are shown.
    func navigateToFKReference(value: String, fkInfo: ForeignKeyInfo) {
        let referencedTable = fkInfo.referencedTable
        let referencedColumn = fkInfo.referencedColumn

        fkNavigationLogger.debug("FK navigate: \(referencedTable).\(referencedColumn) = \(value)")

        // Open or switch to the referenced table tab
        openTableTab(referencedTable)

        // Apply filter for the FK value after the table loads
        // We need a small delay because openTableTab triggers runQuery which is async.
        // The filter is applied once the table data has loaded.
        Task { @MainActor in
            // Wait for query execution to complete
            guard let tab = tabManager.selectedTab,
                  tab.tableName == referencedTable else { return }

            // Wait until the tab finishes executing
            while tabManager.selectedTab?.isExecuting == true {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }

            // Build and apply the filter
            let filter = TableFilter(
                columnName: referencedColumn,
                filterOperator: .equal,
                value: value
            )

            applyFilters([filter])

            // Update filter panel to show the applied filter
            filterStateManager.isVisible = true
            filterStateManager.filters = [filter]
        }
    }
}
