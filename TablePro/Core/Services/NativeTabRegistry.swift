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
        print("[NativeTabRegistry] REGISTER windowId=\(windowId.uuidString.prefix(8)) connId=\(connectionId.uuidString.prefix(8)) tabs=\(tabs.count) window=\(window != nil ? "YES" : "nil")")
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
        let hasEntry = entries[windowId] != nil
        print("[NativeTabRegistry] SET_WINDOW windowId=\(windowId.uuidString.prefix(8)) hasEntry=\(hasEntry) connId=\(connectionId.uuidString.prefix(8)) window=\(window) title=\(window.title) subtitle=\(window.subtitle)")
        if entries[windowId] != nil {
            entries[windowId]?.window = window
        } else {
            // Re-create entry — SwiftUI's onDisappear may have removed it during body re-evaluation
            entries[windowId] = WindowEntry(connectionId: connectionId, tabs: [], selectedTabId: nil, window: window)
        }
    }

    /// Find any visible NSWindow for a given connection
    internal func findWindow(for connectionId: UUID) -> NSWindow? {
        let matching = entries.filter { $0.value.connectionId == connectionId }
        print("[NativeTabRegistry] FIND_WINDOW connId=\(connectionId.uuidString.prefix(8)) totalEntries=\(entries.count) matchingEntries=\(matching.count)")
        for (wid, entry) in matching {
            let hasWindow = entry.window != nil
            let isVisible = entry.window?.isVisible ?? false
            print("[NativeTabRegistry]   entry windowId=\(wid.uuidString.prefix(8)) hasWindow=\(hasWindow) isVisible=\(isVisible) tabs=\(entry.tabs.count)")
        }
        let result = matching.values
            .compactMap(\.window)
            .first { $0.isVisible }
        print("[NativeTabRegistry] FIND_WINDOW result=\(result != nil ? "FOUND \(result!)" : "nil")")
        return result
    }

    /// Remove a window from the registry (call on window close/disappear)
    internal func unregister(windowId: UUID) {
        let entry = entries[windowId]
        print("[NativeTabRegistry] UNREGISTER windowId=\(windowId.uuidString.prefix(8)) connId=\(entry?.connectionId.uuidString.prefix(8) ?? "nil")")
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
}
