//
//  QueryHistoryManager.swift
//  OpenTable
//
//  Thread-safe coordinator for query history and bookmarks
//  Communicates via NotificationCenter (NOT ObservableObject)
//

import Combine
import Foundation

/// Notification names for query history updates
extension Notification.Name {
    static let queryHistoryDidUpdate = Notification.Name("queryHistoryDidUpdate")
    static let queryBookmarksDidUpdate = Notification.Name("queryBookmarksDidUpdate")
    static let loadQueryIntoEditor = Notification.Name("loadQueryIntoEditor")
}

/// Thread-safe manager for query history and bookmarks
/// NOT an ObservableObject - uses NotificationCenter for UI communication
final class QueryHistoryManager {
    static let shared = QueryHistoryManager()

    private let storage = QueryHistoryStorage.shared

    // Settings observer for immediate cleanup when settings change
    private var settingsObserver: AnyCancellable?

    private init() {
        // Note: Cleanup is now triggered from app startup with settings check
        // See OpenTableApp.swift for startup cleanup logic

        // Subscribe to history settings changes for immediate cleanup
        settingsObserver = NotificationCenter.default.publisher(for: .historySettingsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }

                // Update settings cache
                self.storage.updateSettingsCache()

                // Perform cleanup if auto-cleanup is enabled
                if AppSettingsManager.shared.history.autoCleanup {
                    self.storage.cleanup()
                }
            }
    }

    /// Perform cleanup if auto-cleanup is enabled in settings
    /// Should be called from app startup (MainActor context)
    @MainActor
    func performStartupCleanup() {
        // Check if auto cleanup is enabled
        guard AppSettingsManager.shared.history.autoCleanup else { return }

        // Update the settings cache before cleanup
        storage.updateSettingsCache()

        // Perform cleanup
        storage.cleanup()
    }

    // MARK: - History Capture

    /// Record a query execution (non-blocking background write)
    func recordQuery(
        query: String,
        connectionId: UUID,
        databaseName: String,
        executionTime: TimeInterval,
        rowCount: Int,
        wasSuccessful: Bool,
        errorMessage: String? = nil
    ) {
        let entry = QueryHistoryEntry(
            query: query,
            connectionId: connectionId,
            databaseName: databaseName,
            executionTime: executionTime,
            rowCount: rowCount,
            wasSuccessful: wasSuccessful,
            errorMessage: errorMessage
        )

        // Background write (non-blocking)
        storage.addHistory(entry) { success in
            if success {
                // Notify UI to refresh on main thread
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .queryHistoryDidUpdate,
                        object: nil
                    )
                }
            }
        }
    }

    // MARK: - History Retrieval

    /// Fetch history entries (synchronous - for compatibility)
    func fetchHistory(
        limit: Int = 100,
        offset: Int = 0,
        connectionId: UUID? = nil,
        searchText: String? = nil,
        dateFilter: DateFilter = .all
    ) -> [QueryHistoryEntry] {
        storage.fetchHistory(
            limit: limit,
            offset: offset,
            connectionId: connectionId,
            searchText: searchText,
            dateFilter: dateFilter
        )
    }

    /// Fetch history entries asynchronously (non-blocking - preferred)
    func fetchHistoryAsync(
        limit: Int = 100,
        offset: Int = 0,
        connectionId: UUID? = nil,
        searchText: String? = nil,
        dateFilter: DateFilter = .all,
        completion: @escaping ([QueryHistoryEntry]) -> Void
    ) {
        storage.fetchHistoryAsync(
            limit: limit,
            offset: offset,
            connectionId: connectionId,
            searchText: searchText,
            dateFilter: dateFilter,
            completion: completion
        )
    }

    /// Search queries using FTS5 full-text search
    func searchQueries(_ text: String) -> [QueryHistoryEntry] {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return fetchHistory()
        }
        return storage.fetchHistory(searchText: text)
    }

    /// Delete a history entry
    func deleteHistory(id: UUID) -> Bool {
        let success = storage.deleteHistory(id: id)
        if success {
            NotificationCenter.default.post(name: .queryHistoryDidUpdate, object: nil)
        }
        return success
    }

    /// Get total history count
    func getHistoryCount() -> Int {
        storage.getHistoryCount()
    }

    // MARK: - Bookmarks

    /// Save a new bookmark
    func saveBookmark(
        name: String,
        query: String,
        connectionId: UUID? = nil,
        tags: [String] = [],
        notes: String? = nil
    ) -> Bool {
        let bookmark = QueryBookmark(
            name: name,
            query: query,
            connectionId: connectionId,
            tags: tags,
            notes: notes
        )

        let success = storage.addBookmark(bookmark)
        if success {
            NotificationCenter.default.post(name: .queryBookmarksDidUpdate, object: nil)
        }
        return success
    }

    /// Save bookmark from history entry
    func saveBookmarkFromHistory(_ entry: QueryHistoryEntry, name: String) -> Bool {
        saveBookmark(
            name: name,
            query: entry.query,
            connectionId: entry.connectionId
        )
    }

    /// Update an existing bookmark
    func updateBookmark(_ bookmark: QueryBookmark) -> Bool {
        let success = storage.updateBookmark(bookmark)
        if success {
            NotificationCenter.default.post(name: .queryBookmarksDidUpdate, object: nil)
        }
        return success
    }

    /// Update bookmark's last used timestamp
    func markBookmarkUsed(id: UUID) {
        if var bookmark = fetchBookmarks().first(where: { $0.id == id }) {
            bookmark.lastUsedAt = Date()
            _ = storage.updateBookmark(bookmark)
        }
    }

    /// Fetch bookmarks with optional filters (synchronous - for compatibility)
    func fetchBookmarks(searchText: String? = nil, tag: String? = nil) -> [QueryBookmark] {
        storage.fetchBookmarks(searchText: searchText, tag: tag)
    }

    /// Fetch bookmarks asynchronously (non-blocking - preferred)
    func fetchBookmarksAsync(searchText: String? = nil, tag: String? = nil, completion: @escaping ([QueryBookmark]) -> Void) {
        storage.fetchBookmarksAsync(searchText: searchText, tag: tag, completion: completion)
    }

    /// Delete a bookmark
    func deleteBookmark(id: UUID) -> Bool {
        let success = storage.deleteBookmark(id: id)
        if success {
            NotificationCenter.default.post(name: .queryBookmarksDidUpdate, object: nil)
        }
        return success
    }

    /// Clear all history entries
    func clearAllHistory() -> Bool {
        let success = storage.clearAllHistory()
        if success {
            NotificationCenter.default.post(name: .queryHistoryDidUpdate, object: nil)
        }
        return success
    }

    /// Clear all bookmarks
    func clearAllBookmarks() -> Bool {
        let success = storage.clearAllBookmarks()
        if success {
            NotificationCenter.default.post(name: .queryBookmarksDidUpdate, object: nil)
        }
        return success
    }

    // MARK: - Cleanup

    /// Manually trigger cleanup (normally runs automatically)
    /// Must be called from MainActor context
    @MainActor
    func cleanup() {
        // Update settings cache before cleanup
        storage.updateSettingsCache()
        storage.cleanup()
    }
}
