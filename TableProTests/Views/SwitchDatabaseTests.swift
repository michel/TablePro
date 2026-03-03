//
//  SwitchDatabaseTests.swift
//  TableProTests
//
//  Tests for the "switch database" flow: verifies that switching databases
//  (Cmd+K) does NOT create new macOS windows, and that table tabs are
//  properly reset to avoid "table not found" errors in the new database.
//

import Foundation
import SwiftUI
import Testing

@testable import TablePro

// MARK: - Mock TableFetcher

private struct MockTableFetcher: TableFetcher {
    var tables: [TableInfo]

    func fetchTables() async throws -> [TableInfo] {
        tables
    }
}

// MARK: - Helpers

/// Simulates the tab-mapping logic from switchDatabase(to:).
/// Table-type tabs are converted to query tabs with cleared state to prevent
/// "table not found" errors when the new database has different tables.
@MainActor
private func simulateDatabaseSwitchTabMapping(
    tabManager: QueryTabManager,
    newDatabase: String
) {
    tabManager.tabs = tabManager.tabs.map { tab in
        var updatedTab = tab
        updatedTab.resultColumns = []
        updatedTab.resultRows = []
        updatedTab.resultVersion += 1
        updatedTab.errorMessage = nil
        updatedTab.executionTime = nil
        updatedTab.databaseName = newDatabase
        if tab.tabType == .table {
            updatedTab.tableName = nil
            updatedTab.tabType = .query
            updatedTab.query = ""
            updatedTab.showStructure = false
            updatedTab.isView = false
            updatedTab.isEditable = false
        }
        return updatedTab
    }
}

@Suite("SwitchDatabase")
struct SwitchDatabaseTests {
    // MARK: - isSwitchingDatabase flag

    @Test("isSwitchingDatabase defaults to false")
    @MainActor
    func flagDefaultsToFalse() {
        let connection = TestFixtures.makeConnection()
        let tabManager = QueryTabManager()
        let changeManager = DataChangeManager()
        let filterStateManager = FilterStateManager()
        let toolbarState = ConnectionToolbarState()

        let coordinator = MainContentCoordinator(
            connection: connection,
            tabManager: tabManager,
            changeManager: changeManager,
            filterStateManager: filterStateManager,
            toolbarState: toolbarState
        )
        defer { coordinator.teardown() }

        #expect(coordinator.isSwitchingDatabase == false)
    }

    @Test("isSwitchingDatabase can be set to true")
    @MainActor
    func flagCanBeSetToTrue() {
        let connection = TestFixtures.makeConnection()
        let tabManager = QueryTabManager()
        let changeManager = DataChangeManager()
        let filterStateManager = FilterStateManager()
        let toolbarState = ConnectionToolbarState()

        let coordinator = MainContentCoordinator(
            connection: connection,
            tabManager: tabManager,
            changeManager: changeManager,
            filterStateManager: filterStateManager,
            toolbarState: toolbarState
        )
        defer { coordinator.teardown() }

        coordinator.isSwitchingDatabase = true
        #expect(coordinator.isSwitchingDatabase == true)
    }

    // MARK: - openTableTab behavior during database switch

    @Test("openTableTab skips new window when switching database with existing tabs")
    @MainActor
    func openTableTabSkipsNewWindowDuringSwitch() {
        let connection = TestFixtures.makeConnection(database: "db_a")
        let tabManager = QueryTabManager()
        let changeManager = DataChangeManager()
        let filterStateManager = FilterStateManager()
        let toolbarState = ConnectionToolbarState()

        let coordinator = MainContentCoordinator(
            connection: connection,
            tabManager: tabManager,
            changeManager: changeManager,
            filterStateManager: filterStateManager,
            toolbarState: toolbarState
        )
        defer { coordinator.teardown() }

        // Set up: one existing tab
        tabManager.addTableTab(tableName: "users", databaseType: .mysql, databaseName: "db_a")
        let tabCountBefore = tabManager.tabs.count

        // Simulate database switch in progress
        coordinator.isSwitchingDatabase = true

        // Opening a different table during switch should NOT add more tabs
        // (because the guard returns early without calling WindowOpener)
        coordinator.openTableTab("orders")

        // Tab count should remain unchanged — no new tab was added
        // (isSwitchingDatabase guard returns early when tabs exist)
        #expect(tabManager.tabs.count == tabCountBefore)
    }

    @Test("openTableTab adds tab in-place when switching database with empty tabs")
    @MainActor
    func openTableTabAddsInPlaceWhenSwitchingWithEmptyTabs() {
        let connection = TestFixtures.makeConnection(database: "db_a")
        let tabManager = QueryTabManager()
        let changeManager = DataChangeManager()
        let filterStateManager = FilterStateManager()
        let toolbarState = ConnectionToolbarState()

        let coordinator = MainContentCoordinator(
            connection: connection,
            tabManager: tabManager,
            changeManager: changeManager,
            filterStateManager: filterStateManager,
            toolbarState: toolbarState
        )
        defer { coordinator.teardown() }

        // No existing tabs
        #expect(tabManager.tabs.isEmpty)

        // Simulate database switch in progress
        coordinator.isSwitchingDatabase = true

        // Opening a table during switch with empty tabs should add in-place
        coordinator.openTableTab("users")

        #expect(tabManager.tabs.count == 1)
        #expect(tabManager.tabs.first?.tableName == "users")
    }

    // MARK: - openTableTab fast path (same table + same database)

    @Test("openTableTab skips when table is already active tab in same database")
    @MainActor
    func openTableTabSkipsForSameTableSameDatabase() {
        let connection = TestFixtures.makeConnection(database: "db_a")
        let tabManager = QueryTabManager()
        let changeManager = DataChangeManager()
        let filterStateManager = FilterStateManager()
        let toolbarState = ConnectionToolbarState()

        let coordinator = MainContentCoordinator(
            connection: connection,
            tabManager: tabManager,
            changeManager: changeManager,
            filterStateManager: filterStateManager,
            toolbarState: toolbarState
        )
        defer { coordinator.teardown() }

        // Add a tab for "users" in "db_a"
        tabManager.addTableTab(tableName: "users", databaseType: .mysql, databaseName: "db_a")
        let tabCountBefore = tabManager.tabs.count

        // Opening "users" again in same database should be a no-op (fast path)
        coordinator.openTableTab("users")

        #expect(tabManager.tabs.count == tabCountBefore)
    }

    // MARK: - Tab state after database switch

    @Test("switchDatabase clears tableName on table tabs")
    @MainActor
    func switchDatabaseClearsTableName() {
        let tabManager = QueryTabManager()
        tabManager.addTableTab(tableName: "users", databaseType: .mysql, databaseName: "db_a")

        simulateDatabaseSwitchTabMapping(tabManager: tabManager, newDatabase: "db_b")

        #expect(tabManager.tabs.first?.tableName == nil)
    }

    @Test("switchDatabase converts table tabs to query type")
    @MainActor
    func switchDatabaseConvertsTableTabsToQuery() {
        let tabManager = QueryTabManager()
        tabManager.addTableTab(tableName: "users", databaseType: .mysql, databaseName: "db_a")

        simulateDatabaseSwitchTabMapping(tabManager: tabManager, newDatabase: "db_b")

        #expect(tabManager.tabs.first?.tabType == .query)
    }

    @Test("switchDatabase clears query on table tabs")
    @MainActor
    func switchDatabaseClearsQueryOnTableTabs() {
        let tabManager = QueryTabManager()
        tabManager.addTableTab(tableName: "users", databaseType: .mysql, databaseName: "db_a")
        #expect(tabManager.tabs.first?.query.isEmpty == false)

        simulateDatabaseSwitchTabMapping(tabManager: tabManager, newDatabase: "db_b")

        #expect(tabManager.tabs.first?.query == "")
    }

    @Test("switchDatabase preserves query tabs unchanged")
    @MainActor
    func switchDatabasePreservesQueryTabs() {
        let tabManager = QueryTabManager()
        let customSQL = "SELECT COUNT(*) FROM orders WHERE status = 'active'"
        tabManager.addTab(initialQuery: customSQL, databaseName: "db_a")

        simulateDatabaseSwitchTabMapping(tabManager: tabManager, newDatabase: "db_b")

        let tab = tabManager.tabs.first
        #expect(tab?.query == customSQL)
        #expect(tab?.tabType == .query)
    }

    @Test("switchDatabase updates databaseName on all tabs")
    @MainActor
    func switchDatabaseUpdatesDatabaseName() {
        let tabManager = QueryTabManager()
        tabManager.addTableTab(tableName: "users", databaseType: .mysql, databaseName: "db_a")
        tabManager.addTab(initialQuery: "SELECT 1", databaseName: "db_a")

        simulateDatabaseSwitchTabMapping(tabManager: tabManager, newDatabase: "db_b")

        for tab in tabManager.tabs {
            #expect(tab.databaseName == "db_b")
        }
    }

    @Test("switchDatabase clears results on all tabs")
    @MainActor
    func switchDatabaseClearsResults() {
        let tabManager = QueryTabManager()
        tabManager.addTableTab(tableName: "users", databaseType: .mysql, databaseName: "db_a")
        tabManager.addTab(initialQuery: "SELECT 1", databaseName: "db_a")

        // Populate result data on both tabs
        for i in tabManager.tabs.indices {
            tabManager.tabs[i].resultColumns = ["id", "name"]
            tabManager.tabs[i].resultRows = [QueryResultRow(id: 0, values: ["1", "Alice"])]
        }

        let versionsBefore = tabManager.tabs.map(\.resultVersion)

        simulateDatabaseSwitchTabMapping(tabManager: tabManager, newDatabase: "db_b")

        for (i, tab) in tabManager.tabs.enumerated() {
            #expect(tab.resultColumns.isEmpty)
            #expect(tab.resultRows.isEmpty)
            #expect(tab.resultVersion == versionsBefore[i] + 1)
        }
    }

    @Test("switchDatabase handles mixed table and query tabs")
    @MainActor
    func switchDatabaseHandlesMixedTabs() {
        let tabManager = QueryTabManager()
        tabManager.addTableTab(tableName: "users", databaseType: .mysql, databaseName: "db_a")
        let customSQL = "SELECT NOW()"
        tabManager.addTab(initialQuery: customSQL, databaseName: "db_a")

        simulateDatabaseSwitchTabMapping(tabManager: tabManager, newDatabase: "db_b")

        // Table tab should be converted
        let tableTab = tabManager.tabs[0]
        #expect(tableTab.tabType == .query)
        #expect(tableTab.tableName == nil)
        #expect(tableTab.query == "")
        #expect(tableTab.showStructure == false)
        #expect(tableTab.isView == false)
        #expect(tableTab.isEditable == false)
        #expect(tableTab.databaseName == "db_b")

        // Query tab should keep its SQL
        let queryTab = tabManager.tabs[1]
        #expect(queryTab.tabType == .query)
        #expect(queryTab.query == customSQL)
        #expect(queryTab.databaseName == "db_b")
    }

    @Test("switchDatabase clears errorMessage and executionTime")
    @MainActor
    func switchDatabaseClearsErrorAndTiming() {
        let tabManager = QueryTabManager()
        tabManager.addTableTab(tableName: "users", databaseType: .mysql, databaseName: "db_a")

        // Simulate previous execution state
        tabManager.tabs[0].errorMessage = "Table 'users' doesn't exist"
        tabManager.tabs[0].executionTime = 0.042

        simulateDatabaseSwitchTabMapping(tabManager: tabManager, newDatabase: "db_b")

        #expect(tabManager.tabs[0].errorMessage == nil)
        #expect(tabManager.tabs[0].executionTime == nil)
    }

    // MARK: - SidebarViewModel selection during database switch

    @Test("SidebarViewModel skips selection restore during database switch")
    @MainActor
    func sidebarSkipsSelectionRestoreDuringSwitch() async throws {
        let newTables = [
            TestFixtures.makeTableInfo(name: "orders"),
            TestFixtures.makeTableInfo(name: "products")
        ]

        // Start with empty tables and empty selection (simulates state after
        // switchDatabase clears session.tables)
        var tablesState: [TableInfo] = []
        var selectedState: Set<TableInfo> = []
        var truncatesState: Set<String> = []
        var deletesState: Set<String> = []
        var optionsState: [String: TableOperationOptions] = [:]

        let tablesBinding = Binding(get: { tablesState }, set: { tablesState = $0 })
        let selectedBinding = Binding(get: { selectedState }, set: { selectedState = $0 })
        let truncatesBinding = Binding(get: { truncatesState }, set: { truncatesState = $0 })
        let deletesBinding = Binding(get: { deletesState }, set: { deletesState = $0 })
        let optionsBinding = Binding(get: { optionsState }, set: { optionsState = $0 })

        let fetcher = MockTableFetcher(tables: newTables)
        let vm = SidebarViewModel(
            tables: tablesBinding,
            selectedTables: selectedBinding,
            pendingTruncates: truncatesBinding,
            pendingDeletes: deletesBinding,
            tableOperationOptions: optionsBinding,
            databaseType: .mysql,
            connectionId: UUID(),
            tableFetcher: fetcher
        )

        // When tables list is empty (cleared by switchDatabase), previousSelectedName
        // should be nil so no stale table name is restored as a selection
        vm.loadTables()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Tables should be populated from fetcher
        #expect(tablesBinding.wrappedValue.count == 2)

        // No selection should be restored because there was no previous selection
        // to preserve (tables were empty when loadTablesAsync captured previousSelectedName)
        #expect(selectedBinding.wrappedValue.isEmpty)
    }
}
