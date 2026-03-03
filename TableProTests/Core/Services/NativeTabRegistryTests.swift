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

    // MARK: - isRegistered

    @Test("isRegistered returns true for a registered window")
    func isRegisteredReturnsTrueForRegisteredWindow() {
        let windowId = UUID()
        let connectionId = UUID()

        NativeTabRegistry.shared.register(windowId: windowId, connectionId: connectionId, tabs: [makeSnapshot()], selectedTabId: nil)
        defer { NativeTabRegistry.shared.unregister(windowId: windowId) }

        #expect(NativeTabRegistry.shared.isRegistered(windowId: windowId))
    }

    @Test("isRegistered returns false for an unregistered window")
    func isRegisteredReturnsFalseForUnknownWindow() {
        #expect(!NativeTabRegistry.shared.isRegistered(windowId: UUID()))
    }

    @Test("isRegistered returns false after unregister")
    func isRegisteredReturnsFalseAfterUnregister() {
        let windowId = UUID()
        let connectionId = UUID()

        NativeTabRegistry.shared.register(windowId: windowId, connectionId: connectionId, tabs: [makeSnapshot()], selectedTabId: nil)
        NativeTabRegistry.shared.unregister(windowId: windowId)

        #expect(!NativeTabRegistry.shared.isRegistered(windowId: windowId))
    }

    // MARK: - Tab group merge scenario

    @Test("Tab group merge — re-register after unregister keeps window alive")
    func tabGroupMergeReRegister() {
        let windowId = UUID()
        let connectionId = UUID()
        let tab = makeSnapshot()

        // Step 1: Initial register (window appears)
        NativeTabRegistry.shared.register(windowId: windowId, connectionId: connectionId, tabs: [tab], selectedTabId: tab.id)
        defer { NativeTabRegistry.shared.unregister(windowId: windowId) }

        // Step 2: macOS tab group merge fires onDisappear → unregister
        NativeTabRegistry.shared.unregister(windowId: windowId)
        #expect(!NativeTabRegistry.shared.isRegistered(windowId: windowId))

        // Step 3: macOS tab group merge fires onAppear → re-register same windowId
        NativeTabRegistry.shared.register(windowId: windowId, connectionId: connectionId, tabs: [tab], selectedTabId: tab.id)

        // Window should be alive — isRegistered true, hasWindows true, tabs intact
        #expect(NativeTabRegistry.shared.isRegistered(windowId: windowId))
        #expect(NativeTabRegistry.shared.hasWindows(for: connectionId))
        #expect(NativeTabRegistry.shared.allTabs(for: connectionId).count == 1)
        #expect(NativeTabRegistry.shared.allTabs(for: connectionId).first?.id == tab.id)
    }

    @Test("Tab group merge — teardown proceeds when window is not re-registered")
    func tabGroupMergeTeardownWhenNotReRegistered() {
        let windowId = UUID()
        let connectionId = UUID()

        // Step 1: Initial register (window appears)
        NativeTabRegistry.shared.register(windowId: windowId, connectionId: connectionId, tabs: [makeSnapshot()], selectedTabId: nil)

        // Step 2: onDisappear fires → unregister
        NativeTabRegistry.shared.unregister(windowId: windowId)

        // Step 3: No re-register happens (genuine window close, not a merge)
        // After the delay, isRegistered should be false → teardown should proceed
        #expect(!NativeTabRegistry.shared.isRegistered(windowId: windowId))
        #expect(!NativeTabRegistry.shared.hasWindows(for: connectionId))
        #expect(NativeTabRegistry.shared.allTabs(for: connectionId).isEmpty)
    }

    // MARK: - hasOtherWindows excludes self

    @Test("hasOtherWindows returns false when only self is registered")
    func hasOtherWindowsExcludesSelf() {
        let windowId = UUID()
        let connectionId = UUID()

        NativeTabRegistry.shared.register(windowId: windowId, connectionId: connectionId, tabs: [makeSnapshot()], selectedTabId: nil)
        defer { NativeTabRegistry.shared.unregister(windowId: windowId) }

        #expect(!NativeTabRegistry.shared.hasOtherWindows(for: connectionId, excluding: windowId))
    }

    // MARK: - hasOtherWindows true when other exists

    @Test("hasOtherWindows returns true when another window exists for the same connection")
    func hasOtherWindowsTrueWhenOtherExists() {
        let windowId1 = UUID()
        let windowId2 = UUID()
        let connectionId = UUID()

        NativeTabRegistry.shared.register(windowId: windowId1, connectionId: connectionId, tabs: [makeSnapshot()], selectedTabId: nil)
        NativeTabRegistry.shared.register(windowId: windowId2, connectionId: connectionId, tabs: [makeSnapshot()], selectedTabId: nil)
        defer {
            NativeTabRegistry.shared.unregister(windowId: windowId1)
            NativeTabRegistry.shared.unregister(windowId: windowId2)
        }

        #expect(NativeTabRegistry.shared.hasOtherWindows(for: connectionId, excluding: windowId1))
        #expect(NativeTabRegistry.shared.hasOtherWindows(for: connectionId, excluding: windowId2))
    }

    // MARK: - hasOtherWindows false for unknown connection

    @Test("hasOtherWindows returns false for an unknown connectionId")
    func hasOtherWindowsFalseForUnknown() {
        #expect(!NativeTabRegistry.shared.hasOtherWindows(for: UUID(), excluding: UUID()))
    }

    // MARK: - hasOtherWindows excludes only specified window

    @Test("hasOtherWindows excludes only the specified window across multiple connections")
    func hasOtherWindowsExcludesOnlySpecifiedWindow() {
        let windowId1 = UUID()
        let windowId2 = UUID()
        let windowId3 = UUID()
        let connectionA = UUID()
        let connectionB = UUID()

        NativeTabRegistry.shared.register(windowId: windowId1, connectionId: connectionA, tabs: [makeSnapshot()], selectedTabId: nil)
        NativeTabRegistry.shared.register(windowId: windowId2, connectionId: connectionA, tabs: [makeSnapshot()], selectedTabId: nil)
        NativeTabRegistry.shared.register(windowId: windowId3, connectionId: connectionB, tabs: [makeSnapshot()], selectedTabId: nil)
        defer {
            NativeTabRegistry.shared.unregister(windowId: windowId1)
            NativeTabRegistry.shared.unregister(windowId: windowId2)
            NativeTabRegistry.shared.unregister(windowId: windowId3)
        }

        // Excluding window1 from connection A — window2 still exists for A
        #expect(NativeTabRegistry.shared.hasOtherWindows(for: connectionA, excluding: windowId1))

        // Excluding window1 from connection B — window3 exists for B (window1 isn't even for B)
        #expect(NativeTabRegistry.shared.hasOtherWindows(for: connectionB, excluding: windowId1))

        // Excluding window3 from connection A — window1 and window2 still exist for A
        #expect(NativeTabRegistry.shared.hasOtherWindows(for: connectionA, excluding: windowId3))

        // Excluding window3 from connection B — no other windows for B
        #expect(!NativeTabRegistry.shared.hasOtherWindows(for: connectionB, excluding: windowId3))
    }
}
