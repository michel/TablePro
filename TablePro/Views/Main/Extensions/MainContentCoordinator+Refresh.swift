//
//  MainContentCoordinator+Refresh.swift
//  TablePro
//
//  Refresh handling operations for MainContentCoordinator
//

import Foundation

extension MainContentCoordinator {
    // MARK: - Refresh Handling

    func handleRefreshAll(
        hasPendingTableOps: Bool,
        onDiscard: @escaping () -> Void
    ) {
        // If showing structure view, let it handle refresh notifications
        if let tabIndex = tabManager.selectedTabIndex,
           tabManager.tabs[tabIndex].showStructure {
            return
        }

        let hasEditedCells = changeManager.hasChanges

        if hasEditedCells || hasPendingTableOps {
            Task { @MainActor in
                let confirmed = await confirmDiscardChanges(action: .refreshAll)
                if confirmed {
                    onDiscard()
                    changeManager.clearChanges()
                    NotificationCenter.default.post(name: .databaseDidConnect, object: nil)
                    runQuery()
                }
            }
        } else {
            NotificationCenter.default.post(name: .databaseDidConnect, object: nil)
            runQuery()
        }
    }

    func handleRefresh(
        hasPendingTableOps: Bool,
        onDiscard: @escaping () -> Void
    ) {
        // If showing structure view, let it handle refresh notifications
        if let tabIndex = tabManager.selectedTabIndex,
           tabManager.tabs[tabIndex].showStructure {
            return
        }

        let hasEditedCells = changeManager.hasChanges

        if hasEditedCells || hasPendingTableOps {
            Task { @MainActor in
                let confirmed = await confirmDiscardChanges(action: .refresh)
                if confirmed {
                    onDiscard()
                    changeManager.clearChanges()
                    // Only execute query if we're in a table tab
                    // Query tabs should not auto-execute on refresh (use Cmd+Enter to execute)
                    if let tabIndex = tabManager.selectedTabIndex,
                       tabManager.tabs[tabIndex].tabType == .table {
                        currentQueryTask?.cancel()
                        rebuildTableQuery(at: tabIndex)
                        runQuery()
                    }
                }
            }
        } else {
            // Only execute query if we're in a table tab
            // Query tabs should not auto-execute on refresh (use Cmd+Enter to execute)
            if let tabIndex = tabManager.selectedTabIndex,
               tabManager.tabs[tabIndex].tabType == .table {
                currentQueryTask?.cancel()
                rebuildTableQuery(at: tabIndex)
                runQuery()
            }
        }
    }
}
