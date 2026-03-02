//
//  NativeTabRegistry.swift
//  TablePro
//
//  Registry tracking tabs across all native macOS window-tabs.
//  Used to collect combined tab state for persistence.
//

import AppKit
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
        var tabs: [TabSnapshot]
        var selectedTabId: UUID?
        weak var window: NSWindow?
    }

    private var entries: [UUID: WindowEntry] = [:]

    /// Register a window's tabs in the registry
    internal func register(windowId: UUID, connectionId: UUID, tabs: [TabSnapshot], selectedTabId: UUID?, window: NSWindow? = nil) {
        entries[windowId] = WindowEntry(connectionId: connectionId, tabs: tabs, selectedTabId: selectedTabId, window: window)
    }

    /// Update a window's tabs (call when tabs or selection changes).
    /// Auto-registers the window if not yet registered — handles the race where
    /// `.onChange` fires before `.onAppear` (upsert pattern).
    internal func update(windowId: UUID, connectionId: UUID, tabs: [TabSnapshot], selectedTabId: UUID?) {
        if entries[windowId] != nil {
            entries[windowId]?.tabs = tabs
            entries[windowId]?.selectedTabId = selectedTabId
        } else {
            // Auto-register: .onChange can fire before .onAppear
            entries[windowId] = WindowEntry(connectionId: connectionId, tabs: tabs, selectedTabId: selectedTabId)
        }
    }

    /// Set the NSWindow reference for a registered window.
    /// If the entry was removed by SwiftUI's onDisappear re-evaluation,
    /// re-creates a minimal entry so the window can still be found.
    internal func setWindow(_ window: NSWindow, for windowId: UUID, connectionId: UUID) {
        if entries[windowId] != nil {
            entries[windowId]?.window = window
        } else {
            // Re-create entry — SwiftUI's onDisappear may have removed it during body re-evaluation
            entries[windowId] = WindowEntry(connectionId: connectionId, tabs: [], selectedTabId: nil, window: window)
        }
    }

    /// Find any visible NSWindow for a given connection
    internal func findWindow(for connectionId: UUID) -> NSWindow? {
        entries.values
            .filter { $0.connectionId == connectionId }
            .compactMap(\.window)
            .first { $0.isVisible }
    }

    /// Remove a window from the registry (call on window close/disappear)
    internal func unregister(windowId: UUID) {
        entries.removeValue(forKey: windowId)
    }

    /// Get combined tabs from all windows for a connection
    internal func allTabs(for connectionId: UUID) -> [TabSnapshot] {
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

    /// Check if a specific window is still registered
    internal func isRegistered(windowId: UUID) -> Bool {
        entries[windowId] != nil
    }
}
