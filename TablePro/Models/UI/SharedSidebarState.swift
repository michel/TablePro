//
//  SharedSidebarState.swift
//  TablePro
//
//  Shared sidebar state (selection + search) for cross-tab synchronization.
//  One instance per connection, shared across all native macOS tabs.
//

import Foundation

@MainActor @Observable
final class SharedSidebarState {
    var selectedTables: Set<TableInfo> = []
    var searchText: String = ""

    private static var registry: [UUID: SharedSidebarState] = [:]

    static func forConnection(_ id: UUID) -> SharedSidebarState {
        if let existing = registry[id] { return existing }
        let state = SharedSidebarState()
        registry[id] = state
        return state
    }

    static func removeConnection(_ id: UUID) {
        registry.removeValue(forKey: id)
    }
}
