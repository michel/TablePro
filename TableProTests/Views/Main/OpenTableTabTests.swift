//
//  OpenTableTabTests.swift
//  TableProTests
//
//  Tests for openTableTab logic — verifies skip/open behavior
//  based on current tab state and database context.
//

import Foundation
import Testing

@testable import TablePro

@Suite("OpenTableTab")
struct OpenTableTabTests {
    // MARK: - Fast path: same table + same database

    @Test("Skips when table is already active tab in same database")
    @MainActor
    func skipsForSameTableSameDatabase() {
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

        tabManager.addTableTab(tableName: "users", databaseType: .mysql, databaseName: "db_a")
        let tabCountBefore = tabManager.tabs.count

        coordinator.openTableTab("users")

        // No new tab created — fast path triggered
        #expect(tabManager.tabs.count == tabCountBefore)
    }

    // MARK: - isSwitchingDatabase guard

    @Test("Does not add new tabs when switching database with existing tabs")
    @MainActor
    func doesNotAddTabsWhenSwitchingWithExistingTabs() {
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

        tabManager.addTableTab(tableName: "users", databaseType: .mysql, databaseName: "db_a")
        let tabCountBefore = tabManager.tabs.count

        coordinator.isSwitchingDatabase = true
        coordinator.openTableTab("orders")

        // No new tab — the guard returns early when tabs exist
        #expect(tabManager.tabs.count == tabCountBefore)
    }

    @Test("Adds tab in-place when switching database with empty tabs")
    @MainActor
    func addsTabInPlaceWhenSwitchingWithEmptyTabs() {
        let connection = TestFixtures.makeConnection(database: "db_b")
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

        #expect(tabManager.tabs.isEmpty)

        coordinator.isSwitchingDatabase = true
        coordinator.openTableTab("products")

        #expect(tabManager.tabs.count == 1)
        #expect(tabManager.tabs.first?.tableName == "products")
    }

    // MARK: - Empty tabs path (no switching)

    @Test("Adds tab directly when tabs are empty and not switching")
    @MainActor
    func addsTabDirectlyWhenTabsEmptyNotSwitching() {
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

        #expect(tabManager.tabs.isEmpty)

        coordinator.openTableTab("users")

        #expect(tabManager.tabs.count == 1)
        #expect(tabManager.tabs.first?.tableName == "users")
    }
}
