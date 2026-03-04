//
//  RedisQueryBuilderTests.swift
//  TableProTests
//
//  Tests for RedisQueryBuilder — Redis SCAN command construction.
//

import Foundation
import Testing
@testable import TablePro

@Suite("Redis Query Builder")
struct RedisQueryBuilderTests {
    private let builder = RedisQueryBuilder()

    // MARK: - buildBaseQuery

    @Test("Empty namespace produces wildcard pattern")
    func baseQueryEmptyNamespace() {
        let query = builder.buildBaseQuery(namespace: "")
        #expect(query == "SCAN 0 MATCH * COUNT 200")
    }

    @Test("Namespace appends wildcard after prefix")
    func baseQueryWithNamespace() {
        let query = builder.buildBaseQuery(namespace: "user:")
        #expect(query == "SCAN 0 MATCH user:* COUNT 200")
    }

    @Test("Custom limit overrides default")
    func baseQueryCustomLimit() {
        let query = builder.buildBaseQuery(namespace: "", limit: 500)
        #expect(query == "SCAN 0 MATCH * COUNT 500")
    }

    // MARK: - buildFilteredQuery

    @Test("Contains filter on Key wraps value with wildcards")
    func filteredQueryContains() {
        let filter = TestFixtures.makeTableFilter(column: "Key", op: .contains, value: "session")
        let query = builder.buildFilteredQuery(namespace: "", filters: [filter])
        #expect(query == "SCAN 0 MATCH *session* COUNT 200")
    }

    @Test("StartsWith filter on Key appends trailing wildcard")
    func filteredQueryStartsWith() {
        let filter = TestFixtures.makeTableFilter(column: "Key", op: .startsWith, value: "cache")
        let query = builder.buildFilteredQuery(namespace: "", filters: [filter])
        #expect(query == "SCAN 0 MATCH cache* COUNT 200")
    }

    @Test("EndsWith filter on Key prepends leading wildcard")
    func filteredQueryEndsWith() {
        let filter = TestFixtures.makeTableFilter(column: "Key", op: .endsWith, value: "meta")
        let query = builder.buildFilteredQuery(namespace: "", filters: [filter])
        #expect(query == "SCAN 0 MATCH *meta COUNT 200")
    }

    @Test("Equal filter on Key uses exact value")
    func filteredQueryEqual() {
        let filter = TestFixtures.makeTableFilter(column: "Key", op: .equal, value: "config")
        let query = builder.buildFilteredQuery(namespace: "", filters: [filter])
        #expect(query == "SCAN 0 MATCH config COUNT 200")
    }

    @Test("Filter with namespace prepends namespace to pattern")
    func filteredQueryWithNamespace() {
        let filter = TestFixtures.makeTableFilter(column: "Key", op: .contains, value: "token")
        let query = builder.buildFilteredQuery(namespace: "ns:", filters: [filter])
        #expect(query == "SCAN 0 MATCH ns:*token* COUNT 200")
    }

    @Test("Non-Key column filter falls back to base query")
    func filteredQueryNonKeyColumn() {
        let filter = TestFixtures.makeTableFilter(column: "Value", op: .contains, value: "hello")
        let query = builder.buildFilteredQuery(namespace: "", filters: [filter])
        #expect(query == "SCAN 0 MATCH * COUNT 200")
    }

    @Test("Unsupported operator falls back to base query")
    func filteredQueryUnsupportedOperator() {
        let filter = TestFixtures.makeTableFilter(column: "Key", op: .greaterThan, value: "100")
        let query = builder.buildFilteredQuery(namespace: "", filters: [filter])
        #expect(query == "SCAN 0 MATCH * COUNT 200")
    }

    @Test("Multiple Key filters falls back to base query")
    func filteredQueryMultipleKeyFilters() {
        let filter1 = TestFixtures.makeTableFilter(column: "Key", op: .contains, value: "a")
        let filter2 = TestFixtures.makeTableFilter(column: "Key", op: .startsWith, value: "b")
        let query = builder.buildFilteredQuery(namespace: "", filters: [filter1, filter2])
        #expect(query == "SCAN 0 MATCH * COUNT 200")
    }

    @Test("Disabled filter is ignored and falls back to base query")
    func filteredQueryDisabledFilter() {
        let filter = TableFilter(
            columnName: "Key",
            filterOperator: .contains,
            value: "test",
            isEnabled: false
        )
        let query = builder.buildFilteredQuery(namespace: "", filters: [filter])
        #expect(query == "SCAN 0 MATCH * COUNT 200")
    }

    // MARK: - buildQuickSearchQuery

    @Test("No namespace wraps search text with wildcards")
    func quickSearchNoNamespace() {
        let query = builder.buildQuickSearchQuery(namespace: "", searchText: "user")
        #expect(query == "SCAN 0 MATCH *user* COUNT 200")
    }

    @Test("With namespace prepends namespace before wildcard")
    func quickSearchWithNamespace() {
        let query = builder.buildQuickSearchQuery(namespace: "app:", searchText: "session")
        #expect(query == "SCAN 0 MATCH app:*session* COUNT 200")
    }

    @Test("Glob special characters in search text are escaped")
    func quickSearchEscapesGlobChars() {
        let query = builder.buildQuickSearchQuery(namespace: "", searchText: "key*val?ue[0]")
        #expect(query == "SCAN 0 MATCH *key\\*val\\?ue\\[0\\]* COUNT 200")
    }

    // MARK: - buildCountQuery

    @Test("Empty namespace returns DBSIZE")
    func countQueryEmptyNamespace() {
        let query = builder.buildCountQuery(namespace: "")
        #expect(query == "DBSIZE")
    }

    @Test("With namespace returns SCAN with high count")
    func countQueryWithNamespace() {
        let query = builder.buildCountQuery(namespace: "cache:")
        #expect(query == "SCAN 0 MATCH cache:* COUNT 10000")
    }

    // MARK: - Glob Escaping (via buildQuickSearchQuery)

    @Test("Asterisk in input is escaped")
    func globEscapeAsterisk() {
        let query = builder.buildQuickSearchQuery(namespace: "", searchText: "a*b")
        #expect(query == "SCAN 0 MATCH *a\\*b* COUNT 200")
    }

    @Test("Question mark in input is escaped")
    func globEscapeQuestionMark() {
        let query = builder.buildQuickSearchQuery(namespace: "", searchText: "a?b")
        #expect(query == "SCAN 0 MATCH *a\\?b* COUNT 200")
    }

    @Test("Square brackets in input are escaped")
    func globEscapeBrackets() {
        let query = builder.buildQuickSearchQuery(namespace: "", searchText: "[test]")
        #expect(query == "SCAN 0 MATCH *\\[test\\]* COUNT 200")
    }

    // MARK: - Additional Glob Escaping

    @Test("Backslash in search text is escaped to double backslash")
    func globEscapeBackslash() {
        let query = builder.buildQuickSearchQuery(namespace: "", searchText: "path\\to")
        #expect(query == "SCAN 0 MATCH *path\\\\to* COUNT 200")
    }

    @Test("Empty search text produces double wildcard pattern")
    func quickSearchEmptyString() {
        let query = builder.buildQuickSearchQuery(namespace: "", searchText: "")
        #expect(query == "SCAN 0 MATCH ** COUNT 200")
    }

    @Test("Count query with namespace containing glob chars does not escape them")
    func countQueryNamespaceWithGlobChars() {
        // buildCountQuery does not escape the namespace — it's used as-is
        let query = builder.buildCountQuery(namespace: "cache*")
        #expect(query == "SCAN 0 MATCH cache** COUNT 10000")
    }

    @Test("Filtered query with glob chars in filter value escapes them")
    func filteredQueryGlobCharsInValue() {
        let filter = TestFixtures.makeTableFilter(column: "Key", op: .contains, value: "a*b")
        let query = builder.buildFilteredQuery(namespace: "", filters: [filter])
        #expect(query == "SCAN 0 MATCH *a\\*b* COUNT 200")
    }
}
