//
//  NativeTabRegistryTests.swift
//  TableProTests
//

import Foundation
import Testing
@testable import TablePro

@Suite("NativeTabRegistry")
@MainActor
struct NativeTabRegistryTests {
    private func makeSnapshot(
        id: UUID = UUID(),
        title: String = "test",
        tableName: String? = "test_table",
        tabType: TabType = .table,
        databaseName: String = "testdb"
    ) -> TabSnapshot {
        TabSnapshot(id: id, title: title, query: "SELECT * FROM test", tabType: tabType, tableName: tableName, isView: false, databaseName: databaseName)
    }

    // MARK: - Register and retrieve

    @Test("Register window — hasWindows returns true and allTabs returns registered tabs")
    func registerAndRetrieve() {
        let windowId = UUID()
        let connectionId = UUID()
        let tabs = [makeSnapshot(), makeSnapshot()]

        NativeTabRegistry.shared.register(windowId: windowId, connectionId: connectionId, tabs: tabs, selectedTabId: nil)
        defer { NativeTabRegistry.shared.unregister(windowId: windowId) }

        #expect(NativeTabRegistry.shared.hasWindows(for: connectionId))
        #expect(NativeTabRegistry.shared.allTabs(for: connectionId).count == 2)
    }

    // MARK: - Update upsert

    @Test("Update without prior register auto-registers the window")
    func updateUpsert() {
        let windowId = UUID()
        let connectionId = UUID()
        let tabs = [makeSnapshot()]

        NativeTabRegistry.shared.update(windowId: windowId, connectionId: connectionId, tabs: tabs, selectedTabId: nil)
        defer { NativeTabRegistry.shared.unregister(windowId: windowId) }

        #expect(NativeTabRegistry.shared.hasWindows(for: connectionId))
        #expect(NativeTabRegistry.shared.allTabs(for: connectionId).count == 1)
    }

    // MARK: - Update existing

    @Test("Update after register replaces tabs")
    func updateExisting() {
        let windowId = UUID()
        let connectionId = UUID()

        NativeTabRegistry.shared.register(windowId: windowId, connectionId: connectionId, tabs: [makeSnapshot(), makeSnapshot()], selectedTabId: nil)
        defer { NativeTabRegistry.shared.unregister(windowId: windowId) }

        let newTab = makeSnapshot()
        NativeTabRegistry.shared.update(windowId: windowId, connectionId: connectionId, tabs: [newTab], selectedTabId: newTab.id)

        let allTabs = NativeTabRegistry.shared.allTabs(for: connectionId)
        #expect(allTabs.count == 1)
        #expect(allTabs.first?.id == newTab.id)
    }

    // MARK: - Unregister

    @Test("Unregister removes window — hasWindows returns false and allTabs is empty")
    func unregister() {
        let windowId = UUID()
        let connectionId = UUID()

        NativeTabRegistry.shared.register(windowId: windowId, connectionId: connectionId, tabs: [makeSnapshot()], selectedTabId: nil)
        NativeTabRegistry.shared.unregister(windowId: windowId)

        #expect(!NativeTabRegistry.shared.hasWindows(for: connectionId))
        #expect(NativeTabRegistry.shared.allTabs(for: connectionId).isEmpty)
    }

    // MARK: - allTabs aggregates across windows

    @Test("allTabs combines tabs from all windows for the same connection")
    func allTabsAggregatesAcrossWindows() {
        let windowId1 = UUID()
        let windowId2 = UUID()
        let connectionId = UUID()
        let tab1 = makeSnapshot()
        let tab2 = makeSnapshot()

        NativeTabRegistry.shared.register(windowId: windowId1, connectionId: connectionId, tabs: [tab1], selectedTabId: nil)
        NativeTabRegistry.shared.register(windowId: windowId2, connectionId: connectionId, tabs: [tab2], selectedTabId: nil)
        defer {
            NativeTabRegistry.shared.unregister(windowId: windowId1)
            NativeTabRegistry.shared.unregister(windowId: windowId2)
        }

        let allTabs = NativeTabRegistry.shared.allTabs(for: connectionId)
        let allIds = Set(allTabs.map(\.id))
        #expect(allTabs.count == 2)
        #expect(allIds.contains(tab1.id))
        #expect(allIds.contains(tab2.id))
    }

    // MARK: - selectedTabId

    @Test("selectedTabId returns the registered selected tab ID")
    func selectedTabId() {
        let windowId = UUID()
        let connectionId = UUID()
        let tab = makeSnapshot()

        NativeTabRegistry.shared.register(windowId: windowId, connectionId: connectionId, tabs: [tab], selectedTabId: tab.id)
        defer { NativeTabRegistry.shared.unregister(windowId: windowId) }

        #expect(NativeTabRegistry.shared.selectedTabId(for: connectionId) == tab.id)
    }

    // MARK: - selectedTabId returns nil for unknown

    @Test("selectedTabId returns nil for unregistered connection")
    func selectedTabIdNilForUnknown() {
        #expect(NativeTabRegistry.shared.selectedTabId(for: UUID()) == nil)
    }

    // MARK: - hasWindows false for unknown

    @Test("hasWindows returns false for unregistered connection")
    func hasWindowsFalseForUnknown() {
        #expect(!NativeTabRegistry.shared.hasWindows(for: UUID()))
    }

    // MARK: - connectionIds

    @Test("connectionIds contains all registered connection IDs")
    func connectionIds() {
        let windowId1 = UUID()
        let windowId2 = UUID()
        let connectionId1 = UUID()
        let connectionId2 = UUID()

        NativeTabRegistry.shared.register(windowId: windowId1, connectionId: connectionId1, tabs: [makeSnapshot()], selectedTabId: nil)
        NativeTabRegistry.shared.register(windowId: windowId2, connectionId: connectionId2, tabs: [makeSnapshot()], selectedTabId: nil)
        defer {
            NativeTabRegistry.shared.unregister(windowId: windowId1)
            NativeTabRegistry.shared.unregister(windowId: windowId2)
        }

        let ids = NativeTabRegistry.shared.connectionIds()
        #expect(ids.contains(connectionId1))
        #expect(ids.contains(connectionId2))
    }

    // MARK: - Multiple connections independent

    @Test("Unregistering one connection's window does not affect another connection")
    func multipleConnectionsIndependent() {
        let windowId1 = UUID()
        let windowId2 = UUID()
        let connectionId1 = UUID()
        let connectionId2 = UUID()
        let tab2 = makeSnapshot()

        NativeTabRegistry.shared.register(windowId: windowId1, connectionId: connectionId1, tabs: [makeSnapshot()], selectedTabId: nil)
        NativeTabRegistry.shared.register(windowId: windowId2, connectionId: connectionId2, tabs: [tab2], selectedTabId: nil)
        defer { NativeTabRegistry.shared.unregister(windowId: windowId2) }

        NativeTabRegistry.shared.unregister(windowId: windowId1)

        #expect(!NativeTabRegistry.shared.hasWindows(for: connectionId1))
        #expect(NativeTabRegistry.shared.hasWindows(for: connectionId2))
        #expect(NativeTabRegistry.shared.allTabs(for: connectionId2).count == 1)
        #expect(NativeTabRegistry.shared.allTabs(for: connectionId2).first?.id == tab2.id)
    }

    // MARK: - allTabs empty after all windows unregistered

    @Test("allTabs is empty after all windows for a connection are unregistered")
    func allTabsEmptyAfterAllWindowsUnregistered() {
        let windowId1 = UUID()
        let windowId2 = UUID()
        let connectionId = UUID()

        NativeTabRegistry.shared.register(windowId: windowId1, connectionId: connectionId, tabs: [makeSnapshot()], selectedTabId: nil)
        NativeTabRegistry.shared.register(windowId: windowId2, connectionId: connectionId, tabs: [makeSnapshot()], selectedTabId: nil)

        NativeTabRegistry.shared.unregister(windowId: windowId1)
        NativeTabRegistry.shared.unregister(windowId: windowId2)

        #expect(NativeTabRegistry.shared.allTabs(for: connectionId).isEmpty)
        #expect(!NativeTabRegistry.shared.hasWindows(for: connectionId))
    }
}
