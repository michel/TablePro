//
//  MongoDBQueryBuilderTests.swift
//  TableProTests
//
//  Tests for MongoDBQueryBuilder — MongoDB shell syntax query construction.
//

import Foundation
import Testing
@testable import TablePro

@Suite("MongoDB Query Builder")
struct MongoDBQueryBuilderTests {
    private let builder = MongoDBQueryBuilder()

    // MARK: - buildBaseQuery

    @Test("Base query with defaults produces find with limit")
    func baseQueryDefaults() {
        let query = builder.buildBaseQuery(collection: "users")
        #expect(query == "db.users.find({}).limit(200)")
    }

    @Test("Base query with custom limit and offset")
    func baseQueryWithLimitAndOffset() {
        let query = builder.buildBaseQuery(collection: "users", limit: 50, offset: 100)
        #expect(query == "db.users.find({}).skip(100).limit(50)")
    }

    @Test("Base query with ascending sort includes sort document")
    func baseQueryWithAscendingSort() {
        var sortState = SortState()
        sortState.columns = [SortColumn(columnIndex: 0, direction: .ascending)]

        let query = builder.buildBaseQuery(
            collection: "users",
            sortState: sortState,
            columns: ["name", "email"]
        )
        #expect(query == "db.users.find({}).sort({\"name\": 1}).limit(200)")
    }

    // MARK: - buildQuickSearchQuery

    @Test("Quick search with single column produces $or with regex")
    func quickSearchSingleColumn() {
        let query = builder.buildQuickSearchQuery(
            collection: "users",
            searchText: "john",
            columns: ["name"]
        )
        #expect(query == "db.users.find({\"$or\": [{\"name\": {\"$regex\": \"john\", \"$options\": \"i\"}}]}).limit(200)")
    }

    @Test("Quick search with multiple columns produces $or array with multiple entries")
    func quickSearchMultipleColumns() {
        let query = builder.buildQuickSearchQuery(
            collection: "users",
            searchText: "john",
            columns: ["name", "email"]
        )
        let expected = "db.users.find({\"$or\": ["
            + "{\"name\": {\"$regex\": \"john\", \"$options\": \"i\"}}, "
            + "{\"email\": {\"$regex\": \"john\", \"$options\": \"i\"}}"
            + "]}).limit(200)"
        #expect(query == expected)
    }

    @Test("Quick search escapes regex special characters in search text")
    func quickSearchEscapesSpecialChars() {
        let query = builder.buildQuickSearchQuery(
            collection: "users",
            searchText: "test.value",
            columns: ["name"]
        )
        // The dot should be escaped as \. for regex safety
        #expect(query.contains("test\\.value"))
        #expect(query.contains("$regex"))
    }

    // MARK: - Sort via buildBaseQuery

    @Test("Descending sort uses -1 in sort document")
    func descendingSortDirection() {
        var sortState = SortState()
        sortState.columns = [SortColumn(columnIndex: 0, direction: .descending)]

        let query = builder.buildBaseQuery(
            collection: "users",
            sortState: sortState,
            columns: ["name"]
        )
        #expect(query == "db.users.find({}).sort({\"name\": -1}).limit(200)")
    }

    @Test("Multi-column sort produces combined sort document")
    func multiColumnSort() {
        var sortState = SortState()
        sortState.columns = [
            SortColumn(columnIndex: 0, direction: .ascending),
            SortColumn(columnIndex: 1, direction: .descending)
        ]

        let query = builder.buildBaseQuery(
            collection: "users",
            sortState: sortState,
            columns: ["name", "age"]
        )
        #expect(query == "db.users.find({}).sort({\"name\": 1, \"age\": -1}).limit(200)")
    }

    // MARK: - buildFilteredQuery

    @Test("Filtered query with empty filters produces base query")
    func filteredQueryEmptyFilters() {
        let query = builder.buildFilteredQuery(collection: "users", filters: [])
        #expect(query == "db.users.find({}).limit(200)")
    }

    @Test("Filtered query with disabled filter produces base query")
    func filteredQueryDisabledFilter() {
        let filter = TableFilter(columnName: "name", filterOperator: .equal, value: "John", isEnabled: false)
        let query = builder.buildFilteredQuery(collection: "users", filters: [filter])
        #expect(query == "db.users.find({}).limit(200)")
    }

    @Test("Filtered query with single active filter includes filter document")
    func filteredQuerySingleFilter() {
        let filter = TableFilter(columnName: "name", filterOperator: .equal, value: "John")
        let query = builder.buildFilteredQuery(collection: "users", filters: [filter])
        #expect(query == "db.users.find({\"name\": \"John\"}).limit(200)")
    }

    // MARK: - buildCombinedQuery

    @Test("Combined query with filter and search uses $and wrapper")
    func combinedQueryUsesAndWrapper() {
        let filter = TableFilter(columnName: "status", filterOperator: .equal, value: "active")
        let query = builder.buildCombinedQuery(
            collection: "users",
            filters: [filter],
            searchText: "john",
            searchColumns: ["name", "email"]
        )
        #expect(query.contains("\"$and\""))
        #expect(query.contains("\"status\": \"active\""))
        #expect(query.contains("\"$or\""))
        #expect(query.contains("\"$regex\": \"john\""))
        #expect(query.contains(".limit(200)"))
    }

    // MARK: - buildQuickSearchQuery with sort and offset

    @Test("Quick search with sort and offset includes all clauses")
    func quickSearchWithSortAndOffset() {
        var sortState = SortState()
        sortState.columns = [SortColumn(columnIndex: 0, direction: .ascending)]

        let query = builder.buildQuickSearchQuery(
            collection: "users",
            searchText: "john",
            columns: ["name"],
            sortState: sortState,
            limit: 50,
            offset: 10
        )
        #expect(query.contains(".sort("))
        #expect(query.contains(".skip(10)"))
        #expect(query.contains(".limit(50)"))
        #expect(query.contains("$regex"))
    }
}
