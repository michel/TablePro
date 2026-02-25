//
//  NativeTabRegistry.swift
//  TablePro
//
//  Registry tracking tabs across all native macOS window-tabs.
//  Used to collect combined tab state for persistence.
//

import Foundation

/// Tracks tab state across all native window-tabs for a connection.
/// Each `MainContentView` registers its tabs here so the persistence layer
/// can save the combined state from all windows.
@MainActor
final class NativeTabRegistry {
    static let shared = NativeTabRegistry()

    private struct WindowEntry {
        let connectionId: UUID
        var tabs: [QueryTab]
        var selectedTabId: UUID?
    }

    private var entries: [UUID: WindowEntry] = [:]

    /// Register a window's tabs in the registry
    func register(windowId: UUID, connectionId: UUID, tabs: [QueryTab], selectedTabId: UUID?) {
        entries[windowId] = WindowEntry(connectionId: connectionId, tabs: tabs, selectedTabId: selectedTabId)
    }

    /// Update a window's tabs (call when tabs or selection changes)
    func update(windowId: UUID, tabs: [QueryTab], selectedTabId: UUID?) {
        guard entries[windowId] != nil else { return }
        entries[windowId]?.tabs = tabs
        entries[windowId]?.selectedTabId = selectedTabId
    }

    /// Remove a window from the registry (call on window close/disappear)
    func unregister(windowId: UUID) {
        entries.removeValue(forKey: windowId)
    }

    /// Get combined tabs from all windows for a connection
    func allTabs(for connectionId: UUID) -> [QueryTab] {
        entries.values
            .filter { $0.connectionId == connectionId }
            .flatMap(\.tabs)
    }

    /// Get the selected tab ID for a connection (from any registered window)
    func selectedTabId(for connectionId: UUID) -> UUID? {
        entries.values
            .first { $0.connectionId == connectionId && $0.selectedTabId != nil }?
            .selectedTabId
    }

    /// Get all connection IDs that have registered windows
    func connectionIds() -> Set<UUID> {
        Set(entries.values.map(\.connectionId))
    }

    /// Check if any windows are registered for a connection
    func hasWindows(for connectionId: UUID) -> Bool {
        entries.values.contains { $0.connectionId == connectionId }
    }
}
