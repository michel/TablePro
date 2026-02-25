//
//  EditorTabPayload.swift
//  TablePro
//
//  Payload for identifying the content of a native window tab.
//  Used with WindowGroup(for:) to create native macOS window tabs.
//

import Foundation

/// Payload passed to each native window tab to identify what content it should display.
/// Each window-tab receives this at creation time via `openWindow(id:value:)`.
struct EditorTabPayload: Codable, Hashable {
    /// Unique identifier for this window-tab (ensures openWindow always creates a new window)
    let id: UUID
    /// The connection this tab belongs to
    let connectionId: UUID
    /// What type of content to display
    let tabType: TabType
    /// Table name (for .table tabs)
    let tableName: String?
    /// Database context (for multi-database connections)
    let databaseName: String?
    /// Initial SQL query (for .query tabs opened from files)
    let initialQuery: String?
    /// Whether this tab displays a database view (read-only)
    let isView: Bool

    init(
        id: UUID = UUID(),
        connectionId: UUID,
        tabType: TabType = .query,
        tableName: String? = nil,
        databaseName: String? = nil,
        initialQuery: String? = nil,
        isView: Bool = false
    ) {
        self.id = id
        self.connectionId = connectionId
        self.tabType = tabType
        self.tableName = tableName
        self.databaseName = databaseName
        self.initialQuery = initialQuery
        self.isView = isView
    }

    /// Create a payload from a persisted QueryTab for restoration
    init(from tab: QueryTab, connectionId: UUID) {
        self.id = UUID()
        self.connectionId = connectionId
        self.tabType = tab.tabType
        self.tableName = tab.tableName
        self.databaseName = tab.databaseName
        self.initialQuery = tab.query
        self.isView = tab.isView
    }
}
