//
//  MainContentCoordinator+MultiStatement.swift
//  TablePro
//
//  Multi-statement SQL execution support for MainContentCoordinator.
//  Executes each statement sequentially, stopping on first error.
//

import AppKit
import Foundation

extension MainContentCoordinator {
    // MARK: - Multi-Statement Execution

    /// Execute multiple SQL statements sequentially within a transaction,
    /// stopping on first error with automatic rollback.
    /// Displays results from the last SELECT statement (if any).
    func executeMultipleStatements(_ statements: [String]) {
        guard let index = tabManager.selectedTabIndex else { return }
        guard !tabManager.tabs[index].isExecuting else { return }

        currentQueryTask?.cancel()
        queryGeneration += 1
        let capturedGeneration = queryGeneration

        var tab = tabManager.tabs[index]
        tab.isExecuting = true
        tab.executionTime = nil
        tab.errorMessage = nil
        tabManager.tabs[index] = tab
        toolbarState.setExecuting(true)

        let conn = connection
        let tabId = tabManager.tabs[index].id
        let totalCount = statements.count
        let dbType = connection.type

        currentQueryTask = Task {
            var cumulativeTime: TimeInterval = 0
            var lastSelectResult: QueryResult?
            var lastSelectSQL: String?
            var totalRowsAffected = 0
            var executedCount = 0
            var failedSQL: String?

            do {
                guard let driver = DatabaseManager.shared.driver(for: conn.id) else {
                    throw DatabaseError.notConnected
                }

                // Wrap in a transaction for atomicity
                _ = try await driver.execute(query: dbType.beginTransactionSQL)

                for (stmtIndex, sql) in statements.enumerated() {
                    guard !Task.isCancelled else { break }
                    guard capturedGeneration == queryGeneration else {
                        _ = try? await driver.execute(query: "ROLLBACK")
                        return
                    }

                    failedSQL = sql
                    let result = try await driver.execute(query: sql)
                    failedSQL = nil
                    executedCount = stmtIndex + 1
                    cumulativeTime += result.executionTime
                    totalRowsAffected += result.rowsAffected

                    // Keep the last result that has columns (i.e. a SELECT)
                    if !result.columns.isEmpty {
                        lastSelectResult = result
                        lastSelectSQL = sql
                    }

                    // Record each statement individually in query history
                    await MainActor.run {
                        QueryHistoryManager.shared.recordQuery(
                            query: sql,
                            connectionId: conn.id,
                            databaseName: conn.database,
                            executionTime: result.executionTime,
                            rowCount: result.rows.count,
                            wasSuccessful: true,
                            errorMessage: nil
                        )
                    }
                }

                // Commit the transaction
                _ = try await driver.execute(query: "COMMIT")

                // All statements succeeded — update tab with results
                await MainActor.run {
                    currentQueryTask = nil
                    toolbarState.setExecuting(false)
                    toolbarState.lastQueryDuration = cumulativeTime

                    guard capturedGeneration == queryGeneration else { return }
                    guard let idx = tabManager.tabs.firstIndex(where: { $0.id == tabId }) else {
                        return
                    }

                    var updatedTab = tabManager.tabs[idx]

                    if let selectResult = lastSelectResult {
                        // Deep copy to prevent C buffer retention issues
                        let safeColumns = selectResult.columns.map { String($0) }
                        let safeColumnTypes = selectResult.columnTypes
                        let safeRows = selectResult.rows.enumerated().map { index, row in
                            QueryResultRow(id: index, values: row.map { $0.map { String($0) } })
                        }
                        let tableName = lastSelectSQL.flatMap {
                            extractTableName(from: $0)
                        }

                        updatedTab.resultColumns = safeColumns
                        updatedTab.columnTypes = safeColumnTypes
                        updatedTab.resultRows = safeRows
                        updatedTab.tableName = tableName
                        updatedTab.isEditable = tableName != nil && updatedTab.isEditable
                    } else {
                        // No SELECT results — clear grid, show rowsAffected summary
                        updatedTab.resultColumns = []
                        updatedTab.columnTypes = []
                        updatedTab.resultRows = []
                        updatedTab.tableName = nil
                        updatedTab.isEditable = false
                    }

                    updatedTab.resultVersion += 1
                    updatedTab.executionTime = cumulativeTime
                    updatedTab.rowsAffected = totalRowsAffected
                    updatedTab.isExecuting = false
                    updatedTab.lastExecutedAt = Date()
                    updatedTab.errorMessage = nil
                    tabManager.tabs[idx] = updatedTab

                    changeManager.clearChanges()
                    changeManager.reloadVersion += 1
                }
            } catch {
                // Rollback on failure
                if let driver = DatabaseManager.shared.driver(for: conn.id) {
                    _ = try? await driver.execute(query: "ROLLBACK")
                }

                guard capturedGeneration == queryGeneration else { return }

                let failedStmtIndex = executedCount + 1
                let contextMsg = "Statement \(failedStmtIndex)/\(totalCount) failed: "
                    + error.localizedDescription

                await MainActor.run {
                    currentQueryTask = nil
                    toolbarState.setExecuting(false)

                    if let idx = tabManager.tabs.firstIndex(where: { $0.id == tabId }) {
                        var errTab = tabManager.tabs[idx]
                        errTab.errorMessage = contextMsg
                        errTab.isExecuting = false
                        errTab.executionTime = cumulativeTime
                        tabManager.tabs[idx] = errTab
                    }

                    // Record only the failing statement in history
                    let recordSQL = failedSQL ?? statements[min(executedCount, totalCount - 1)]
                    QueryHistoryManager.shared.recordQuery(
                        query: recordSQL,
                        connectionId: conn.id,
                        databaseName: conn.database,
                        executionTime: cumulativeTime,
                        rowCount: 0,
                        wasSuccessful: false,
                        errorMessage: error.localizedDescription
                    )

                    AlertHelper.showErrorSheet(
                        title: String(localized: "Query Execution Failed"),
                        message: contextMsg,
                        window: NSApp.keyWindow
                    )
                }
            }
        }
    }
}
