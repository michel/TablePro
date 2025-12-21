//
//  QueryTab.swift
//  OpenTable
//
//  Model for query tabs
//

import Combine
import Foundation

/// Type of tab
enum TabType: Equatable {
    case query  // SQL editor tab
    case table  // Direct table view tab
}

/// Stores pending changes for a tab (used to preserve state when switching tabs)
struct TabPendingChanges: Equatable {
    var changes: [RowChange]
    var deletedRowIndices: Set<Int>
    var insertedRowIndices: Set<Int>
    var modifiedCells: Set<String>
    var primaryKeyColumn: String?
    var columns: [String]

    init() {
        self.changes = []
        self.deletedRowIndices = []
        self.insertedRowIndices = []
        self.modifiedCells = []
        self.primaryKeyColumn = nil
        self.columns = []
    }

    var hasChanges: Bool {
        !changes.isEmpty || !insertedRowIndices.isEmpty || !deletedRowIndices.isEmpty
    }
}

/// Sort direction for column sorting
enum SortDirection: Equatable {
    case ascending
    case descending

    var indicator: String {
        switch self {
        case .ascending: return "▲"
        case .descending: return "▼"
        }
    }

    mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
    }
}

/// Tracks sorting state for a table
struct SortState: Equatable {
    var columnIndex: Int?
    var direction: SortDirection

    init() {
        self.columnIndex = nil
        self.direction = .ascending
    }

    var isSorting: Bool {
        columnIndex != nil
    }
}

/// Tracks pagination state for lazy loading with Load More button
struct PaginationState: Equatable {
    var totalRowCount: Int?      // Total rows in table (fetched once, nil if unknown)
    var pageSize: Int = 200     // Rows per page
    var isLoadingMore: Bool = false  // True while fetching more rows
    
    /// Whether there are more rows to load
    func hasMore(loadedCount: Int) -> Bool {
        guard let total = totalRowCount else {
            // If we don't know total, assume there might be more
            return loadedCount > 0 && loadedCount % pageSize == 0
        }
        return loadedCount < total
    }
}

/// Represents a single tab (query or table)
struct QueryTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var query: String
    var isPinned: Bool
    var lastExecutedAt: Date?
    var tabType: TabType

    // Results
    var resultColumns: [String]
    var columnDefaults: [String: String?]  // Column name -> default value from schema
    var resultRows: [QueryResultRow]
    var executionTime: TimeInterval?
    var errorMessage: String?
    var isExecuting: Bool

    // Editing support
    var tableName: String?
    var isEditable: Bool
    var showStructure: Bool  // Toggle to show structure view instead of data

    // Per-tab change tracking (preserves changes when switching tabs)
    var pendingChanges: TabPendingChanges

    // Per-tab row selection (preserves selection when switching tabs)
    var selectedRowIndices: Set<Int>

    // Per-tab sort state (column sorting)
    var sortState: SortState

    // Track if user has interacted with this tab (sort, edit, select, etc)
    // Prevents tab from being replaced when opening new tables
    var hasUserInteraction: Bool
    
    // Pagination state for lazy loading (table tabs only)
    var pagination: PaginationState

    // Per-tab filter state (preserves filters when switching tabs)
    var filterState: TabFilterState

    init(
        id: UUID = UUID(),
        title: String = "Query",
        query: String = "",
        isPinned: Bool = false,
        tabType: TabType = .query,
        tableName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.query = query
        self.isPinned = isPinned
        self.tabType = tabType
        self.lastExecutedAt = nil
        self.resultColumns = []
        self.columnDefaults = [:]
        self.resultRows = []
        self.executionTime = nil
        self.errorMessage = nil
        self.isExecuting = false
        self.tableName = tableName
        self.isEditable = tabType == .table  // Table tabs are editable by default
        self.showStructure = false
        self.pendingChanges = TabPendingChanges()
        self.selectedRowIndices = []
        self.sortState = SortState()
        self.hasUserInteraction = false
        self.pagination = PaginationState()
        self.filterState = TabFilterState()
    }

    static func == (lhs: QueryTab, rhs: QueryTab) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manager for query tabs
final class QueryTabManager: ObservableObject {
    @Published var tabs: [QueryTab] = []
    @Published var selectedTabId: UUID?

    var selectedTab: QueryTab? {
        guard let id = selectedTabId else { return tabs.first }
        return tabs.first { $0.id == id }
    }

    var selectedTabIndex: Int? {
        guard let id = selectedTabId else { return nil }
        return tabs.firstIndex { $0.id == id }
    }

    init() {
        // Start with no tabs - shows empty state
        tabs = []
        selectedTabId = nil
    }

    // MARK: - Tab Management

    func addTab() {
        let queryCount = tabs.filter { $0.tabType == .query }.count
        let newTab = QueryTab(title: "Query \(queryCount + 1)", tabType: .query)
        tabs.append(newTab)
        selectedTabId = newTab.id
    }

    func addTableTab(tableName: String, databaseType: DatabaseType = .mysql) {
        // Check if table tab already exists
        if let existingTab = tabs.first(where: { $0.tabType == .table && $0.tableName == tableName }
        ) {
            selectedTabId = existingTab.id
            return
        }

        let quotedName = databaseType.quoteIdentifier(tableName)
        let newTab = QueryTab(
            title: tableName,
            query: "SELECT * FROM \(quotedName) LIMIT 200;",
            tabType: .table,
            tableName: tableName
        )
        tabs.append(newTab)
        selectedTabId = newTab.id
    }

    /// Smart table tab opening (TablePlus-style behavior)
    /// - If clicking the same table: just switch to it
    /// - If current tab is a clean table tab (no changes): replace it
    /// - If current tab has pending changes or is a query tab: create new tab
    /// - Returns: true if query needs to be executed (new/replaced tab), false if just switching
    @discardableResult
    func openTableTabSmart(
        tableName: String, hasUnsavedChanges: Bool, databaseType: DatabaseType = .mysql
    ) -> Bool {
        // 1. If a tab for this table already exists, just switch to it
        if let existingTab = tabs.first(where: { $0.tabType == .table && $0.tableName == tableName }
        ) {
            selectedTabId = existingTab.id
            return false  // No need to run query, data already loaded
        }

        let quotedName = databaseType.quoteIdentifier(tableName)

        // 2. Try to reuse the current tab if it's a clean table tab (no changes, no user interaction)
        if let selectedId = selectedTabId,
            let selectedIndex = tabs.firstIndex(where: { $0.id == selectedId }),
            tabs[selectedIndex].tabType == .table,
            !tabs[selectedIndex].isPinned,
            !hasUnsavedChanges,
            !tabs[selectedIndex].hasUserInteraction  // Don't replace if user has interacted
        {
            // Replace the current table tab instead of creating a new one
            tabs[selectedIndex].title = tableName
            tabs[selectedIndex].tableName = tableName
            tabs[selectedIndex].query = "SELECT * FROM \(quotedName) LIMIT 200;"
            tabs[selectedIndex].resultColumns = []
            tabs[selectedIndex].resultRows = []
            tabs[selectedIndex].executionTime = nil
            tabs[selectedIndex].errorMessage = nil
            tabs[selectedIndex].lastExecutedAt = nil
            tabs[selectedIndex].showStructure = false
            tabs[selectedIndex].sortState = SortState()  // Reset sort state
            tabs[selectedIndex].selectedRowIndices = []  // Reset selection
            tabs[selectedIndex].pendingChanges = TabPendingChanges()  // Reset changes
            tabs[selectedIndex].hasUserInteraction = false  // Reset interaction flag
            tabs[selectedIndex].filterState = TabFilterState()  // Reset filter state
            return true  // Need to run query for new table
        }

        // 3. Otherwise, create a new tab
        let newTab = QueryTab(
            title: tableName,
            query: "SELECT * FROM \(quotedName) LIMIT 200;",
            tabType: .table,
            tableName: tableName
        )
        tabs.append(newTab)
        selectedTabId = newTab.id
        return true  // Need to run query for new tab
    }

    func closeTab(_ tab: QueryTab) {
        if let index = tabs.firstIndex(of: tab) {
            tabs.remove(at: index)

            // Select another tab if we closed the selected one
            if selectedTabId == tab.id {
                if tabs.isEmpty {
                    // No tabs left - clear selection (shows empty state)
                    selectedTabId = nil
                } else {
                    // Select nearest remaining tab
                    selectedTabId = tabs[max(0, index - 1)].id
                }
            }
        }
    }

    func selectTab(_ tab: QueryTab) {
        selectedTabId = tab.id
    }

    func updateTab(_ tab: QueryTab) {
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs[index] = tab
        }
    }

    func togglePin(_ tab: QueryTab) {
        if let index = tabs.firstIndex(of: tab) {
            tabs[index].isPinned.toggle()
        }
    }

    func duplicateTab(_ tab: QueryTab) {
        var newTab = QueryTab(
            title: "\(tab.title) (copy)",
            query: tab.query
        )
        newTab.resultColumns = tab.resultColumns
        newTab.resultRows = tab.resultRows

        if let index = tabs.firstIndex(of: tab) {
            tabs.insert(newTab, at: index + 1)
        } else {
            tabs.append(newTab)
        }
        selectedTabId = newTab.id
    }
}
