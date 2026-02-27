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

        // Check if another native window tab already has this table open — switch to it
        if let keyWindow = NSApp.keyWindow {
            let tabbedWindows = keyWindow.tabbedWindows ?? [keyWindow]
            for window in tabbedWindows where window.title == tableName {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }

        // If no tabs exist (empty state), add a table tab directly
        if tabManager.tabs.isEmpty {
            tabManager.addTableTab(
                tableName: tableName,
                databaseType: connection.type,
                databaseName: currentDatabase
            )
            if let tabIndex = tabManager.selectedTabIndex {
                tabManager.tabs[tabIndex].isView = isView
                tabManager.tabs[tabIndex].isEditable = !isView
                tabManager.tabs[tabIndex].pagination.reset()
                AppState.shared.isCurrentTabEditable = !isView && tableName.isEmpty == false
                toolbarState.isTableTab = true
            }
            runQuery()
            return
        }

        // If current tab has unsaved changes, open in a new native tab instead of replacing
        if changeManager.hasChanges {
            let payload = EditorTabPayload(
                connectionId: connection.id,
                tabType: .table,
                tableName: tableName,
                databaseName: currentDatabase,
                isView: isView,
                showStructure: showStructure
            )
            WindowOpener.shared.openNativeTab(payload)
            return
        }

        // Default: open table in a new native tab
        let payload = EditorTabPayload(
            connectionId: connection.id,
            tabType: .table,
            tableName: tableName,
            databaseName: currentDatabase,
            isView: isView,
            showStructure: showStructure
        )
        WindowOpener.shared.openNativeTab(payload)
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

        let payload = EditorTabPayload(
            connectionId: connection.id,
            tabType: .query,
            initialQuery: sql
        )
        WindowOpener.shared.openNativeTab(payload)
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
                        session.tables = []          // triggers SidebarView.loadTables() via onChange
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

                // Reload schema for autocomplete.
                // session.tables was cleared above, which triggers SidebarView.loadTables() via onChange.
                await loadSchema()

                // Re-execute current tab if it's a table tab.
                // Do NOT post .refreshAll here — that broadcasts to ALL windows and causes
                // every window to re-execute its query against the wrong database.
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
}
