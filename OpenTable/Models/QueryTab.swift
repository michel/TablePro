//
//  QueryTab.swift
//  OpenTable
//
//  Model for query tabs
//

import Foundation
import Combine

/// Type of tab
enum TabType: Equatable {
    case query      // SQL editor tab
    case table      // Direct table view tab
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
        // Start with one tab
        let initialTab = QueryTab(title: "Query 1", query: "SELECT 1;")
        tabs = [initialTab]
        selectedTabId = initialTab.id
    }
    
    // MARK: - Tab Management
    
    func addTab() {
        let queryCount = tabs.filter { $0.tabType == .query }.count
        let newTab = QueryTab(title: "Query \(queryCount + 1)", tabType: .query)
        tabs.append(newTab)
        selectedTabId = newTab.id
    }
    
    func addTableTab(tableName: String) {
        // Check if table tab already exists
        if let existingTab = tabs.first(where: { $0.tabType == .table && $0.tableName == tableName }) {
            selectedTabId = existingTab.id
            return
        }
        
        let newTab = QueryTab(
            title: tableName,
            query: "SELECT * FROM `\(tableName)` LIMIT 1000;",
            tabType: .table,
            tableName: tableName
        )
        tabs.append(newTab)
        selectedTabId = newTab.id
    }
    
    func closeTab(_ tab: QueryTab) {
        guard tabs.count > 1 else { return } // Keep at least one tab
        
        if let index = tabs.firstIndex(of: tab) {
            tabs.remove(at: index)
            
            // Select another tab if we closed the selected one
            if selectedTabId == tab.id {
                selectedTabId = tabs[max(0, index - 1)].id
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
