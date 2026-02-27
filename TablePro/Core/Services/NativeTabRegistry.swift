//
//  NativeTabRegistry.swift
//  TablePro
//
//  Registry tracking tabs across all native macOS window-tabs.
//  Used to collect combined tab state for persistence.
//

import Foundation
import os

/// Tracks tab state across all native window-tabs for a connection.
/// Each `MainContentView` registers its tabs here so the persistence layer
/// can save the combined state from all windows.
@MainActor
internal final class NativeTabRegistry {
    private static let logger = Logger(subsystem: "com.TablePro", category: "NativeTabRegistry")

    internal static let shared = NativeTabRegistry()

    private struct WindowEntry {
        let connectionId: UUID
        var tabs: [QueryTab]
        var selectedTabId: UUID?
    }

    private var entries: [UUID: WindowEntry] = [:]

    /// Register a window's tabs in the registry
    internal func register(windowId: UUID, connectionId: UUID, tabs: [QueryTab], selectedTabId: UUID?) {
        entries[windowId] = WindowEntry(connectionId: connectionId, tabs: tabs, selectedTabId: selectedTabId)
    }

    /// Update a window's tabs (call when tabs or selection changes)
    internal func update(windowId: UUID, tabs: [QueryTab], selectedTabId: UUID?) {
        guard entries[windowId] != nil else {
            Self.logger.warning("update called for unregistered windowId \(windowId)")
            return
        }
        entries[windowId]?.tabs = tabs
        entries[windowId]?.selectedTabId = selectedTabId
    }

    /// Remove a window from the registry (call on window close/disappear)
    internal func unregister(windowId: UUID) {
        entries.removeValue(forKey: windowId)
    }

    /// Get combined tabs from all windows for a connection
    internal func allTabs(for connectionId: UUID) -> [QueryTab] {
        entries.values
            .filter { $0.connectionId == connectionId }
            .flatMap(\.tabs)
    }

    /// Get the selected tab ID for a connection (from any registered window)
    internal func selectedTabId(for connectionId: UUID) -> UUID? {
        entries.values
            .first { $0.connectionId == connectionId && $0.selectedTabId != nil }?
            .selectedTabId
    }

    /// Get all connection IDs that have registered windows
    internal func connectionIds() -> Set<UUID> {
        Set(entries.values.map(\.connectionId))
    }

    /// Check if any windows are registered for a connection
    internal func hasWindows(for connectionId: UUID) -> Bool {
        entries.values.contains { $0.connectionId == connectionId }
    }
}
