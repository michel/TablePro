//
//  DisplayValueCacheTests.swift
//  TableProTests
//

import Foundation
import Testing
@testable import TablePro

@Suite("Display Value Cache")
@MainActor
struct DisplayValueCacheTests {
    private func makeProvider(rows: [[String?]], columns: [String], columnTypes: [ColumnType]? = nil) -> InMemoryRowProvider {
        InMemoryRowProvider(
            rows: rows,
            columns: columns,
            columnTypes: columnTypes
        )
    }

    @Test("first access computes and returns display value")
    func firstAccessComputes() {
        let provider = makeProvider(
            rows: [["hello", "world"]],
            columns: ["a", "b"]
        )
        let result = provider.displayValue(atRow: 0, column: 0)
        #expect(result == "hello")
    }

    @Test("second access returns cached value without recomputation")
    func secondAccessCached() {
        let provider = makeProvider(
            rows: [["value1", "value2"]],
            columns: ["a", "b"]
        )
        let first = provider.displayValue(atRow: 0, column: 0)
        let second = provider.displayValue(atRow: 0, column: 0)
        #expect(first == second)
        #expect(first == "value1")
    }

    @Test("updateValue invalidates cache for that row")
    func updateInvalidates() {
        let provider = makeProvider(
            rows: [["old", "keep"]],
            columns: ["a", "b"]
        )
        _ = provider.displayValue(atRow: 0, column: 0)
        provider.updateValue("new", at: 0, columnIndex: 0)
        let result = provider.displayValue(atRow: 0, column: 0)
        #expect(result == "new")
    }

    @Test("invalidateDisplayCache clears all cached values")
    func invalidateAll() {
        let provider = makeProvider(
            rows: [["a1", "a2"], ["b1", "b2"]],
            columns: ["x", "y"]
        )
        _ = provider.displayValue(atRow: 0, column: 0)
        _ = provider.displayValue(atRow: 1, column: 0)
        provider.invalidateDisplayCache()
        // After invalidation, re-access should still work (recomputes)
        let result = provider.displayValue(atRow: 0, column: 0)
        #expect(result == "a1")
    }

    @Test("nil raw value returns nil display value")
    func nilRawValue() {
        let provider = makeProvider(
            rows: [[nil, "ok"]],
            columns: ["a", "b"]
        )
        let result = provider.displayValue(atRow: 0, column: 0)
        #expect(result == nil)
    }

    @Test("out-of-bounds row returns nil")
    func outOfBoundsRow() {
        let provider = makeProvider(
            rows: [["a"]],
            columns: ["x"]
        )
        let result = provider.displayValue(atRow: 5, column: 0)
        #expect(result == nil)
    }

    @Test("linebreaks in values are sanitized in display cache")
    func linebreaksSanitized() {
        let provider = makeProvider(
            rows: [["line1\nline2"]],
            columns: ["a"]
        )
        let result = provider.displayValue(atRow: 0, column: 0)
        #expect(result == "line1 line2")
    }

    @Test("updateRows clears display cache")
    func updateRowsClearsCache() {
        let provider = makeProvider(
            rows: [["old"]],
            columns: ["a"]
        )
        _ = provider.displayValue(atRow: 0, column: 0)
        provider.updateRows([["new"]])
        let result = provider.displayValue(atRow: 0, column: 0)
        #expect(result == "new")
    }
}
