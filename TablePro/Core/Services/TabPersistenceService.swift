//
//  TabPersistenceService.swift
//  TablePro
//
//  Service responsible for persisting and restoring tab state.
//  Handles debounced saving, restoration from disk, and window close handling.
//

import Foundation
import Observation
import os

/// Service for managing tab state persistence
@MainActor @Observable
final class TabPersistenceService {
    private static let logger = Logger(subsystem: "com.TablePro", category: "TabPersistenceService")

    // MARK: - Constants

    private static let saveDebounceDelay: UInt64 = 500_000_000  // 500ms in nanoseconds

    /// Serial queue for ALL disk operations (save, clear, load).
    /// Guarantees ordering: a clear always runs after any pending save,
    /// eliminating the race where orphaned Task.detached writes survive a clear.
    private static let diskQueue = DispatchQueue(label: "com.TablePro.tabPersistence.disk", qos: .utility)

    // MARK: - State

    /// Connections where tabs were explicitly closed by the user.
    /// Extra safety net for in-session restoreTabs() calls — diskQueue
    /// serialization is the primary race-condition fix.
    private static var clearedConnections: Set<UUID> = []

    /// Check if a connection was explicitly cleared (tabs closed by user)
    static func isCleared(connectionId: UUID) -> Bool {
        clearedConnections.contains(connectionId)
    }

    /// Indicates tabs are being restored (prevents circular sync)
    private(set) var isRestoringTabs = false

    /// Indicates view is being dismissed (prevents saving during teardown)
    private(set) var isDismissing = false

    /// Flag to track if a tab was just restored (prevents duplicate lazy load)
    private(set) var justRestoredTab = false

    // MARK: - Private State

    private var saveDebounceTask: Task<Void, Never>?
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

        // Create new debounce task — debounce on MainActor, write on serial queue
        saveDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.saveDebounceDelay)

            guard !Task.isCancelled, !isDismissing else { return }

            Self.diskQueue.async {
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
        Self.diskQueue.async {
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
        Self.diskQueue.async {
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
        guard !isRestoringTabs, !isDismissing else {
            Self.logger.info("[TabRestore] saveTabsAsync — skipped (isRestoring=\(self.isRestoringTabs), isDismissing=\(self.isDismissing))")
            return
        }
        Self.logger.info("[TabRestore] saveTabsAsync — \(tabs.count) tabs, selectedTabId=\(selectedTabId?.uuidString ?? "nil", privacy: .public)")

        // If tabs are being saved, this connection is no longer "cleared".
        // This ensures normal disconnect/reconnect still restores tabs.
        Self.clearedConnections.remove(connectionId)

        let tabsToSave = tabs
        let selectedId = selectedTabId
        let connId = connectionId
        Self.diskQueue.async {
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
    func restoreTabs() async -> RestoreResult {
        isRestoringTabs = true
        defer { isRestoringTabs = false }

        Self.logger.info("[TabRestore] restoreTabs — connectionId=\(self.connectionId)")

        // If tabs were explicitly closed (clearSavedState was called), skip restoration.
        if Self.clearedConnections.remove(connectionId) != nil {
            Self.logger.info("[TabRestore] restoreTabs → connection was explicitly cleared, returning empty")
            return RestoreResult(tabs: [], selectedTabId: nil, source: .none)
        }

        // Try disk storage first (persists across app restarts).
        // Load through the serial diskQueue so the read waits for any pending writes.
        let connId = connectionId
        let savedState = await withCheckedContinuation { continuation in
            Self.diskQueue.async {
                let state = TabStateStorage.shared.loadTabState(connectionId: connId)
                continuation.resume(returning: state)
            }
        }
        if let savedState, !savedState.tabs.isEmpty {
            let restoredTabs = savedState.tabs.map { QueryTab(from: $0) }
            let tabNames = restoredTabs.map { $0.tableName ?? "query" }.joined(separator: ", ")
            Self.logger.info("[TabRestore] restoreTabs → disk: \(restoredTabs.count) tabs [\(tabNames, privacy: .public)], selectedTabId=\(savedState.selectedTabId?.uuidString ?? "nil", privacy: .public)")
            return RestoreResult(
                tabs: restoredTabs,
                selectedTabId: savedState.selectedTabId,
                source: .disk
            )
        }
        Self.logger.info("[TabRestore] restoreTabs → no disk state, checking session")

        // Fallback to session (persists during app session only)
        if let session = DatabaseManager.shared.session(for: connectionId),
           !session.tabs.isEmpty {
            Self.logger.info("[TabRestore] restoreTabs → session: \(session.tabs.count) tabs")
            return RestoreResult(
                tabs: session.tabs,
                selectedTabId: session.selectedTabId,
                source: .session
            )
        }

        Self.logger.info("[TabRestore] restoreTabs → no tabs found (none)")
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
        Self.logger.info("[TabRestore] clearSavedState — connectionId=\(self.connectionId)")

        // Cancel any pending debounce so it doesn't fire after clear.
        saveDebounceTask?.cancel()

        // Mark this connection as explicitly cleared (in-session safety net).
        Self.clearedConnections.insert(connectionId)

        // Dispatch clear to the same serial queue as saves.
        // Since all saves also go through diskQueue, this clear is guaranteed
        // to execute AFTER any previously queued saves — no orphaned writes.
        let connId = connectionId
        Self.diskQueue.async {
            TabStateStorage.shared.clearTabState(connectionId: connId)
        }

        // Also clear session tab cache so restoreTabs() session fallback
        // doesn't resurrect tabs the user explicitly closed
        DatabaseManager.shared.updateSession(connectionId) { session in
            session.tabs = []
            session.selectedTabId = nil
        }
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

            Self.diskQueue.async {
                TabStateStorage.shared.saveLastQuery(query, for: connId)
            }
        }
    }
}
