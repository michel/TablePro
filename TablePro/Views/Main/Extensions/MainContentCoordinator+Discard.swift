//
//  MainContentCoordinator+Discard.swift
//  TablePro
//
//  Sidebar transaction execution and discard handling.
//

import Foundation

extension MainContentCoordinator {
    // MARK: - Table Creation

    /// Execute sidebar changes immediately (single transaction)
    func executeSidebarChanges(statements: [String]) async throws {
        guard let driver = DatabaseManager.shared.driver(for: connectionId) else {
            throw DatabaseError.notConnected
        }

        let dbType = connection.type
        let supportsTransactions = dbType != .redis && dbType != .mongodb && dbType != .clickhouse
        var allStatements: [String] = []

        if supportsTransactions {
            allStatements.append(dbType.beginTransactionSQL)
        }

        // Add user statements
        allStatements.append(contentsOf: statements)

        if supportsTransactions {
            // Add COMMIT
            allStatements.append("COMMIT")
        }

        // Execute all statements sequentially
        do {
            for sql in allStatements {
                _ = try await driver.execute(query: sql)
            }
        } catch {
            if supportsTransactions {
                // Try to rollback on error
                _ = try? await driver.execute(query: "ROLLBACK")
            }
            throw error
        }
    }

    // MARK: - Discard Handling

    func handleDiscard(
        pendingTruncates: inout Set<String>,
        pendingDeletes: inout Set<String>
    ) {
        let originalValues = changeManager.getOriginalValues()
        if let index = tabManager.selectedTabIndex {
            for (rowIndex, columnIndex, originalValue) in originalValues {
                if rowIndex < tabManager.tabs[index].resultRows.count {
                    tabManager.tabs[index].resultRows[rowIndex].values[columnIndex] = originalValue
                }
            }

            let insertedIndices = changeManager.insertedRowIndices.sorted(by: >)
            for rowIndex in insertedIndices {
                if rowIndex < tabManager.tabs[index].resultRows.count {
                    tabManager.tabs[index].resultRows.remove(at: rowIndex)
                }
            }
        }

        pendingTruncates.removeAll()
        pendingDeletes.removeAll()
        changeManager.clearChanges()

        if let index = tabManager.selectedTabIndex {
            tabManager.tabs[index].pendingChanges = TabPendingChanges()
        }

        NotificationCenter.default.post(name: .databaseDidConnect, object: nil)
    }
}
