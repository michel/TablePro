//
//  TabPersistenceService.swift
//  TablePro
//
//  Service responsible for persisting and restoring tab state.
//  Handles debounced saving, restoration from disk, and window close handling.
//

import Combine
import Foundation
import os

/// Service for managing tab state persistence
@MainActor
final class TabPersistenceService: ObservableObject {
    private static let logger = Logger(subsystem: "com.TablePro", category: "TabPersistenceService")

    // MARK: - Constants

    private static let saveDebounceDelay: UInt64 = 500_000_000  // 500ms in nanoseconds

    // MARK: - State

    /// Indicates tabs are being restored (prevents circular sync)
    @Published private(set) var isRestoringTabs = false

    /// Indicates view is being dismissed (prevents saving during teardown)
    @Published private(set) var isDismissing = false

    /// Flag to track if a tab was just restored (prevents duplicate lazy load)
    @Published private(set) var justRestoredTab = false

    // MARK: - Private State

    private var saveDebounceTask: Task<Void, Never>?
    private var backgroundSaveTask: Task<Void, Never>?
    private var lastQueryDebounceTask: Task<Void, Never>?
    private let connectionId: UUID

    // MARK: - Initialization

    init(connectionId: UUID) {
        self.connectionId = connectionId
    }

    // MARK: - Save Operations

    /// Save tabs with debouncing to prevent rapid successive saves
    /// - Parameters:
    ///   - tabs: Current tabs array
    ///   - selectedTabId: Currently selected tab ID
    func saveTabsDebounced(tabs: [TabSnapshot], selectedTabId: UUID?) {
        guard !isRestoringTabs, !isDismissing else { return }

        // Cancel previous debounce task
        saveDebounceTask?.cancel()

        // Capture current state to prevent stale data
        let tabsToSave = tabs
        let selectedId = selectedTabId
        let connId = connectionId

        // Create new debounce task — debounce on MainActor, write on background
        saveDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.saveDebounceDelay)

            guard !Task.isCancelled, !isDismissing else { return }

            Task.detached(priority: .utility) {
                TabStateStorage.shared.saveTabState(
                    connectionId: connId,
                    tabs: tabsToSave,
                    selectedTabId: selectedId
                )
            }
        }
    }

    /// Immediately save tabs without debouncing
    /// - Parameters:
    ///   - tabs: Current tabs array
    ///   - selectedTabId: Currently selected tab ID
    func saveTabsImmediately(tabs: [TabSnapshot], selectedTabId: UUID?) {
        guard !isRestoringTabs, !isDismissing else { return }

        let connId = connectionId
        Task.detached(priority: .utility) {
            TabStateStorage.shared.saveTabState(
                connectionId: connId,
                tabs: tabs,
                selectedTabId: selectedTabId
            )
        }
    }

    /// Handle window close - flush any pending saves
    /// - Parameters:
    ///   - tabs: Current tabs array
    ///   - selectedTabId: Currently selected tab ID
    func handleWindowClose(tabs: [TabSnapshot], selectedTabId: UUID?) {
        isDismissing = true
        saveDebounceTask?.cancel()

        let connId = connectionId
        Task.detached(priority: .userInitiated) {
            TabStateStorage.shared.saveTabState(
                connectionId: connId,
                tabs: tabs,
                selectedTabId: selectedTabId
            )
        }
    }

    /// Save tabs asynchronously on a background thread to avoid blocking the main thread.
    /// Use this for tab-switch paths; use saveTabsImmediately only when the process is about to exit.
    /// - Parameters:
    ///   - tabs: Current tabs array
    ///   - selectedTabId: Currently selected tab ID
    func saveTabsAsync(tabs: [TabSnapshot], selectedTabId: UUID?) {
        guard !isRestoringTabs, !isDismissing else { return }

        // Cancel any in-flight background save so an older snapshot can't
        // finish after a newer one and overwrite it.
        backgroundSaveTask?.cancel()

        let tabsToSave = tabs
        let selectedId = selectedTabId
        let connId = connectionId
        backgroundSaveTask = Task.detached(priority: .utility) {
            guard !Task.isCancelled else { return }
            TabStateStorage.shared.saveTabState(
                connectionId: connId,
                tabs: tabsToSave,
                selectedTabId: selectedId
            )
        }
    }

    // MARK: - Restore Operations

    /// Result of tab restoration
    struct RestoreResult {
        let tabs: [QueryTab]
        let selectedTabId: UUID?
        let source: RestoreSource

        enum RestoreSource {
            case disk
            case session
            case none
        }
    }

    /// Restore tabs from storage (disk first, then session fallback)
    /// - Returns: RestoreResult with tabs and source
    func restoreTabs() -> RestoreResult {
        isRestoringTabs = true
        defer { isRestoringTabs = false }

        // Try disk storage first (persists across app restarts)
        if let savedState = TabStateStorage.shared.loadTabState(connectionId: connectionId),
           !savedState.tabs.isEmpty {
            let restoredTabs = savedState.tabs.map { QueryTab(from: $0) }
            return RestoreResult(
                tabs: restoredTabs,
                selectedTabId: savedState.selectedTabId,
                source: .disk
            )
        }

        // Fallback to session (persists during app session only)
        if let sessionId = DatabaseManager.shared.currentSessionId,
           let session = DatabaseManager.shared.activeSessions[sessionId],
           !session.tabs.isEmpty {
            return RestoreResult(
                tabs: session.tabs,
                selectedTabId: session.selectedTabId,
                source: .session
            )
        }

        return RestoreResult(tabs: [], selectedTabId: nil, source: .none)
    }

    /// Mark that a tab was just restored (prevents duplicate lazy load on tab switch)
    func markJustRestored() {
        justRestoredTab = true
    }

    /// Reset the just restored flag
    func clearJustRestoredFlag() {
        justRestoredTab = false
    }

    /// Mark restoration as starting
    func beginRestoration() {
        isRestoringTabs = true
    }

    /// Mark restoration as complete
    func endRestoration() {
        isRestoringTabs = false
    }

    /// Clear saved state when all tabs are closed
    func clearSavedState() {
        TabStateStorage.shared.clearTabState(connectionId: connectionId)
    }

    /// Load last query for this connection (TablePlus-style)
    func loadLastQuery() -> String? {
        TabStateStorage.shared.loadLastQuery(for: connectionId)
    }

    /// Save last query for this connection (synchronous - use saveLastQueryDebounced for per-keystroke calls)
    func saveLastQuery(_ query: String) {
        TabStateStorage.shared.saveLastQuery(query, for: connectionId)
    }

    /// Save last query with debouncing to avoid blocking I/O on every keystroke
    func saveLastQueryDebounced(_ query: String) {
        lastQueryDebounceTask?.cancel()
        let connId = connectionId
        lastQueryDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.saveDebounceDelay)
            guard !Task.isCancelled, !isDismissing else { return }

            Task.detached(priority: .utility) {
                TabStateStorage.shared.saveLastQuery(query, for: connId)
            }
        }
    }
}
