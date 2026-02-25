//
//  MainContentCoordinator+Filtering.swift
//  TablePro
//
//  Filtering and search operations for MainContentCoordinator
//

import Foundation

extension MainContentCoordinator {
    // MARK: - Filtering

    func applyFilters(_ filters: [TableFilter]) {
        guard let tabIndex = tabManager.selectedTabIndex,
              tabIndex < tabManager.tabs.count,
              let tableName = tabManager.tabs[tabIndex].tableName else { return }

        // Reset pagination when filters change
        tabManager.tabs[tabIndex].pagination.reset()

        let tab = tabManager.tabs[tabIndex]
        let newQuery: String

        // Combine with quick search if active
        if filterStateManager.hasActiveQuickSearch {
            newQuery = queryBuilder.buildCombinedQuery(
                tableName: tableName,
                filters: filters,
                logicMode: filterStateManager.filterLogicMode,
                searchText: filterStateManager.quickSearchText,
                searchColumns: tab.resultColumns,
                sortState: tab.sortState,
                columns: tab.resultColumns,
                limit: tab.pagination.pageSize,
                offset: tab.pagination.currentOffset
            )
        } else {
            newQuery = queryBuilder.buildFilteredQuery(
                tableName: tableName,
                filters: filters,
                logicMode: filterStateManager.filterLogicMode,
                sortState: tab.sortState,
                columns: tab.resultColumns,
                limit: tab.pagination.pageSize,
                offset: tab.pagination.currentOffset
            )
        }

        tabManager.tabs[tabIndex].query = newQuery

        if !filters.isEmpty {
            filterStateManager.saveLastFilters(for: tableName)
        }

        runQuery()
    }

    func applyQuickSearch(_ searchText: String) {
        guard let tabIndex = tabManager.selectedTabIndex,
              tabIndex < tabManager.tabs.count,
              let tableName = tabManager.tabs[tabIndex].tableName,
              !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        // Reset pagination when search changes
        tabManager.tabs[tabIndex].pagination.reset()

        let tab = tabManager.tabs[tabIndex]
        let newQuery: String

        // Combine with applied filters if present
        if filterStateManager.hasAppliedFilters {
            newQuery = queryBuilder.buildCombinedQuery(
                tableName: tableName,
                filters: filterStateManager.appliedFilters,
                logicMode: filterStateManager.filterLogicMode,
                searchText: searchText,
                searchColumns: tab.resultColumns,
                sortState: tab.sortState,
                columns: tab.resultColumns,
                limit: tab.pagination.pageSize,
                offset: tab.pagination.currentOffset
            )
        } else {
            newQuery = queryBuilder.buildQuickSearchQuery(
                tableName: tableName,
                searchText: searchText,
                columns: tab.resultColumns,
                sortState: tab.sortState,
                limit: tab.pagination.pageSize,
                offset: tab.pagination.currentOffset
            )
        }

        tabManager.tabs[tabIndex].query = newQuery
        runQuery()
    }

    func clearFiltersAndReload() {
        guard let tabIndex = tabManager.selectedTabIndex,
              tabIndex < tabManager.tabs.count,
              let tableName = tabManager.tabs[tabIndex].tableName else { return }

        let tab = tabManager.tabs[tabIndex]
        let newQuery = queryBuilder.buildBaseQuery(
            tableName: tableName,
            sortState: tab.sortState,
            columns: tab.resultColumns,
            limit: tab.pagination.pageSize,
            offset: tab.pagination.currentOffset
        )

        tabManager.tabs[tabIndex].query = newQuery
        runQuery()
    }

    func rebuildTableQuery(at tabIndex: Int) {
        guard tabIndex < tabManager.tabs.count,
              let tableName = tabManager.tabs[tabIndex].tableName else { return }

        let tab = tabManager.tabs[tabIndex]
        let hasFilters = filterStateManager.hasAppliedFilters
        let hasSearch = filterStateManager.hasActiveQuickSearch

        let newQuery: String
        if hasFilters && hasSearch {
            newQuery = queryBuilder.buildCombinedQuery(
                tableName: tableName,
                filters: filterStateManager.appliedFilters,
                logicMode: filterStateManager.filterLogicMode,
                searchText: filterStateManager.quickSearchText,
                searchColumns: tab.resultColumns,
                sortState: tab.sortState,
                columns: tab.resultColumns,
                limit: tab.pagination.pageSize,
                offset: tab.pagination.currentOffset
            )
        } else if hasFilters {
            newQuery = queryBuilder.buildFilteredQuery(
                tableName: tableName,
                filters: filterStateManager.appliedFilters,
                logicMode: filterStateManager.filterLogicMode,
                sortState: tab.sortState,
                columns: tab.resultColumns,
                limit: tab.pagination.pageSize,
                offset: tab.pagination.currentOffset
            )
        } else {
            newQuery = queryBuilder.buildBaseQuery(
                tableName: tableName,
                sortState: tab.sortState,
                columns: tab.resultColumns,
                limit: tab.pagination.pageSize,
                offset: tab.pagination.currentOffset
            )
        }

        tabManager.tabs[tabIndex].query = newQuery
    }
}
