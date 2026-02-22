//
//  MainContentCoordinator+Navigation.swift
//  TablePro
//
//  Table tab opening and database switching operations for MainContentCoordinator
//

import AppKit
import Foundation
import os

private let navigationLogger = Logger(subsystem: "com.TablePro", category: "MainContentCoordinator+Navigation")

extension MainContentCoordinator {
    // MARK: - Table Tab Opening

    func openTableTab(_ tableName: String, showStructure: Bool = false, isView: Bool = false) {
        // Get current database name from active session (may differ from connection default after Cmd+K switch)
        let currentDatabase: String
        if let sessionId = DatabaseManager.shared.currentSessionId,
           let session = DatabaseManager.shared.activeSessions[sessionId] {
            currentDatabase = session.connection.database
        } else {
            currentDatabase = connection.database
        }

        // Fast path: if this table is already the active tab in the same database, skip all work
        if let current = tabManager.selectedTab,
           current.tabType == .table,
           current.tableName == tableName,
           current.databaseName == currentDatabase {
            if showStructure, let idx = tabManager.selectedTabIndex {
                tabManager.tabs[idx].showStructure = true
            }
            return
        }

        let needsQuery = tabManager.TableProTabSmart(
            tableName: tableName,
            hasUnsavedChanges: changeManager.hasChanges,
            databaseType: connection.type,
            isView: isView,
            databaseName: currentDatabase
        )

        // Attach timing once tab UUID is known (promotes any pending sidebar trigger)
        if let tabId = tabManager.selectedTabId {
            TabOpenTimingLogger.shared.attach(tabId: tabId, source: "openTable:\(tableName)")
        }

        // Initialize pagination for new table tab
        if needsQuery, let tabIndex = tabManager.selectedTabIndex {
            tabManager.tabs[tabIndex].pagination.reset()
        }

        // Update editable state for menu items (tab switch handler may not fire on reuse path)
        if let tabIndex = tabManager.selectedTabIndex {
            let tab = tabManager.tabs[tabIndex]
            AppState.shared.isCurrentTabEditable = tab.isEditable && !tab.isView && tab.tableName != nil
            toolbarState.isTableTab = tab.tabType == .table
        }

        // Toggle structure view if requested
        if showStructure, let tabIndex = tabManager.selectedTabIndex {
            tabManager.tabs[tabIndex].showStructure = true
        }

        if needsQuery {
            runQuery()
        } else if let tabId = tabManager.selectedTabId {
            // Tab was already open and loaded — nothing more to do
            TabOpenTimingLogger.shared.markDone(tabId: tabId, milestone: "openTable-tabReused")
        }
    }

    func showAllTablesMetadata() {
        let sql: String
        switch connection.type {
        case .postgresql:
            sql = """
            SELECT
                schemaname as schema,
                relname as name,
                'TABLE' as kind,
                n_live_tup as estimated_rows,
                pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) as total_size,
                pg_size_pretty(pg_relation_size(schemaname||'.'||relname)) as data_size,
                pg_size_pretty(pg_indexes_size(schemaname||'.'||relname)) as index_size,
                obj_description((schemaname||'.'||relname)::regclass) as comment
            FROM pg_stat_user_tables
            WHERE schemaname = 'public'
            ORDER BY relname
            """
        case .mysql, .mariadb:
            sql = """
            SELECT
                TABLE_SCHEMA as `schema`,
                TABLE_NAME as name,
                TABLE_TYPE as kind,
                IFNULL(CCSA.CHARACTER_SET_NAME, '') as charset,
                TABLE_COLLATION as collation,
                TABLE_ROWS as estimated_rows,
                CONCAT(ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2), ' MB') as total_size,
                CONCAT(ROUND(DATA_LENGTH / 1024 / 1024, 2), ' MB') as data_size,
                CONCAT(ROUND(INDEX_LENGTH / 1024 / 1024, 2), ' MB') as index_size,
                TABLE_COMMENT as comment
            FROM information_schema.TABLES
            LEFT JOIN information_schema.COLLATION_CHARACTER_SET_APPLICABILITY CCSA
                ON TABLE_COLLATION = CCSA.COLLATION_NAME
            WHERE TABLE_SCHEMA = DATABASE()
            ORDER BY TABLE_NAME
            """
        case .sqlite:
            sql = """
            SELECT
                '' as schema,
                name,
                type as kind,
                '' as charset,
                '' as collation,
                '' as estimated_rows,
                '' as total_size,
                '' as data_size,
                '' as index_size,
                '' as comment
            FROM sqlite_master
            WHERE type IN ('table', 'view')
            AND name NOT LIKE 'sqlite_%'
            ORDER BY name
            """
        }

        if let existingTab = tabManager.tabs.first(where: { $0.title == "Tables" }) {
            if let index = tabManager.tabs.firstIndex(where: { $0.id == existingTab.id }) {
                tabManager.tabs[index].query = sql
            }
            tabManager.selectedTabId = existingTab.id
            runQuery()
            return
        }

        let newTab = QueryTab(
            title: "Tables",
            query: sql,
            tabType: .table,
            tableName: nil
        )
        tabManager.tabs.append(newTab)
        tabManager.selectedTabId = newTab.id
        runQuery()
    }

    // MARK: - Database Switching

    /// Switch to a different database (called from database switcher)
    func switchDatabase(to database: String) async {
        guard let driver = DatabaseManager.shared.activeDriver else {
            return
        }

        do {
            // For MySQL/MariaDB, use USE command
            if connection.type == .mysql || connection.type == .mariadb {
                _ = try await driver.execute(query: "USE `\(database)`")

                // Update session with new database
                if let sessionId = DatabaseManager.shared.currentSessionId {
                    DatabaseManager.shared.updateSession(sessionId) { session in
                        var updatedConnection = session.connection
                        updatedConnection.database = database
                        session.connection = updatedConnection
                    }
                }

                // Update toolbar state
                toolbarState.databaseName = database

                // Clear tab results but keep tabs open, update databaseName to new database
                tabManager.tabs = tabManager.tabs.map { tab in
                    var updatedTab = tab
                    updatedTab.resultColumns = []
                    updatedTab.resultRows = []
                    updatedTab.resultVersion += 1
                    updatedTab.errorMessage = nil
                    updatedTab.executionTime = nil
                    updatedTab.databaseName = database
                    return updatedTab
                }

                // Reload schema for autocomplete
                await loadSchema()

                // Refresh tables list in sidebar
                NotificationCenter.default.post(name: .refreshAll, object: nil)

                // Re-execute current tab's query if it's a table tab
                if let currentTab = tabManager.selectedTab, currentTab.tabType == .table {
                    runQuery()
                }
            } else {
                // For PostgreSQL and SQLite, reconnect with new database
                // (SQLite doesn't apply, but keeping for completeness)
            }
        } catch {
            navigationLogger.error("Failed to switch database: \(error.localizedDescription, privacy: .public)")
            AlertHelper.showErrorSheet(
                title: String(localized: "Database Switch Failed"),
                message: error.localizedDescription,
                window: NSApplication.shared.keyWindow
            )
        }
    }

    /// Switch to a different database (legacy method - creates new connection)
    func switchToDatabase(_ database: String) {
        let newConnection = DatabaseConnection(
            id: UUID(),
            name: connection.name,
            host: connection.host,
            port: connection.port,
            database: database,
            username: connection.username,
            type: connection.type,
            sshConfig: connection.sshConfig,
            color: connection.color,
            tagId: connection.tagId
        )

        Task { @MainActor in
            do {
                try await DatabaseManager.shared.connectToSession(newConnection)
            } catch {
                navigationLogger.error("Failed to connect to database '\(database, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                AlertHelper.showErrorSheet(
                    title: String(localized: "Connection Failed"),
                    message: error.localizedDescription,
                    window: NSApplication.shared.keyWindow
                )
            }
        }
    }
}
