//
//  RedisStatementGeneratorTests.swift
//  TableProTests
//

import Foundation
import Testing
@testable import TablePro

@Suite("Redis Statement Generator")
struct RedisStatementGeneratorTests {
    private let defaultColumns = ["Key", "Type", "TTL", "Value"]

    private func makeGenerator(columns: [String]? = nil) -> RedisStatementGenerator {
        RedisStatementGenerator(namespaceName: "test", columns: columns ?? defaultColumns)
    }

    // MARK: - INSERT Tests

    @Test("Basic insert with key and value from insertedRowData")
    func testBasicInsert() {
        let gen = makeGenerator()
        let changes = [TestFixtures.makeRowChange(row: 0, type: .insert)]
        let insertedRowData: [Int: [String?]] = [0: ["mykey", "string", "60", "hello"]]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(stmts.count == 2)
        #expect(stmts[0].sql == "SET mykey hello")
        #expect(stmts[0].parameters.isEmpty)
    }

    @Test("Insert with TTL from insertedRowData emits SET + EXPIRE")
    func testInsertWithTtl() {
        let gen = makeGenerator()
        let changes = [TestFixtures.makeRowChange(row: 0, type: .insert)]
        let insertedRowData: [Int: [String?]] = [0: ["mykey", "string", "120", "hello"]]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(stmts.count == 2)
        #expect(stmts[0].sql == "SET mykey hello")
        #expect(stmts[1].sql == "EXPIRE mykey 120")
    }

    @Test("Insert with TTL = 0 emits SET only, no EXPIRE")
    func testInsertWithZeroTtl() {
        let gen = makeGenerator()
        let changes = [TestFixtures.makeRowChange(row: 0, type: .insert)]
        let insertedRowData: [Int: [String?]] = [0: ["mykey", "string", "0", "hello"]]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "SET mykey hello")
    }

    @Test("Insert without key is skipped")
    func testInsertWithoutKey() {
        let gen = makeGenerator()
        let changes = [TestFixtures.makeRowChange(row: 0, type: .insert)]
        let insertedRowData: [Int: [String?]] = [0: [nil, "string", nil, "hello"]]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(stmts.isEmpty)
    }

    @Test("Insert with empty key is skipped")
    func testInsertWithEmptyKey() {
        let gen = makeGenerator()
        let changes = [TestFixtures.makeRowChange(row: 0, type: .insert)]
        let insertedRowData: [Int: [String?]] = [0: ["", "string", nil, "hello"]]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(stmts.isEmpty)
    }

    @Test("Insert falls back to cellChanges when insertedRowData has no entry")
    func testInsertFromCellChangesFallback() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 0, colName: "Key", new: "fallbackkey"),
            TestFixtures.makeCellChange(row: 0, col: 3, colName: "Value", new: "fallbackval")
        ]
        let changes = [TestFixtures.makeRowChange(row: 0, type: .insert, cells: cells)]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "SET fallbackkey fallbackval")
    }

    @Test("Insert not in insertedRowIndices is skipped")
    func testInsertNotInInsertedRowIndices() {
        let gen = makeGenerator()
        let changes = [TestFixtures.makeRowChange(row: 0, type: .insert)]
        let insertedRowData: [Int: [String?]] = [0: ["mykey", "string", nil, "hello"]]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [5]
        )

        #expect(stmts.isEmpty)
    }

    // MARK: - UPDATE Tests

    @Test("Value-only update emits SET")
    func testUpdateValueOnly() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 3, colName: "Value", old: "old", new: "new")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["mykey", "string", "60", "old"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "SET mykey new")
    }

    @Test("Key rename emits RENAME and uses new key for subsequent commands")
    func testUpdateKeyRename() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 0, colName: "Key", old: "oldkey", new: "newkey"),
            TestFixtures.makeCellChange(row: 0, col: 3, colName: "Value", old: "val", new: "updated")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["oldkey", "string", "60", "val"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.count == 2)
        #expect(stmts[0].sql == "RENAME oldkey newkey")
        #expect(stmts[1].sql == "SET newkey updated")
    }

    @Test("TTL update to positive value emits EXPIRE")
    func testUpdateTtlPositive() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 2, colName: "TTL", old: "60", new: "300")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["mykey", "string", "60", "hello"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "EXPIRE mykey 300")
    }

    @Test("TTL update to nil emits PERSIST")
    func testUpdateTtlNil() {
        let gen = makeGenerator()
        let cells = [
            CellChange(rowIndex: 0, columnIndex: 2, columnName: "TTL", oldValue: "60", newValue: nil)
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["mykey", "string", "60", "hello"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "PERSIST mykey")
    }

    @Test("TTL update to -1 emits PERSIST")
    func testUpdateTtlMinusOne() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 2, colName: "TTL", old: "60", new: "-1")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["mykey", "string", "60", "hello"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "PERSIST mykey")
    }

    @Test("TTL update to 0 emits neither EXPIRE nor PERSIST")
    func testUpdateTtlZero() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 2, colName: "TTL", old: "60", new: "0")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["mykey", "string", "60", "hello"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.isEmpty)
    }

    @Test("Combined rename + value + TTL change")
    func testUpdateCombinedChanges() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 0, colName: "Key", old: "oldkey", new: "newkey"),
            TestFixtures.makeCellChange(row: 0, col: 3, colName: "Value", old: "oldval", new: "newval"),
            TestFixtures.makeCellChange(row: 0, col: 2, colName: "TTL", old: "60", new: "999")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["oldkey", "string", "60", "oldval"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.count == 3)
        #expect(stmts[0].sql == "RENAME oldkey newkey")
        #expect(stmts[1].sql == "SET newkey newval")
        #expect(stmts[2].sql == "EXPIRE newkey 999")
    }

    @Test("Update with empty cellChanges returns empty result")
    func testUpdateEmptyCellChanges() {
        let gen = makeGenerator()
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: [],
            originalRow: ["mykey", "string", "60", "hello"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.isEmpty)
    }

    @Test("Update without originalRow returns empty result")
    func testUpdateNoOriginalRow() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 3, colName: "Value", old: "old", new: "new")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: nil
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.isEmpty)
    }

    // MARK: - DELETE Tests

    @Test("Single delete emits DEL key")
    func testSingleDelete() {
        let gen = makeGenerator()
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .delete,
            cells: [],
            originalRow: ["mykey", "string", "60", "hello"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [0],
            insertedRowIndices: []
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "DEL mykey")
        #expect(stmts[0].parameters.isEmpty)
    }

    @Test("Multiple deletes batch into single DEL command")
    func testMultipleDeletesBatched() {
        let gen = makeGenerator()
        let changes = [
            TestFixtures.makeRowChange(row: 0, type: .delete, cells: [], originalRow: ["key1", "string", nil, "v1"]),
            TestFixtures.makeRowChange(row: 1, type: .delete, cells: [], originalRow: ["key2", "string", nil, "v2"]),
            TestFixtures.makeRowChange(row: 2, type: .delete, cells: [], originalRow: ["key3", "string", nil, "v3"])
        ]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [0, 1, 2],
            insertedRowIndices: []
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "DEL key1 key2 key3")
    }

    @Test("Delete not in deletedRowIndices is skipped")
    func testDeleteNotInDeletedRowIndices() {
        let gen = makeGenerator()
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .delete,
            cells: [],
            originalRow: ["mykey", "string", "60", "hello"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [5],
            insertedRowIndices: []
        )

        #expect(stmts.isEmpty)
    }

    // MARK: - escapeArgument Tests

    @Test("Simple value without special chars returned as-is")
    func testEscapeSimpleValue() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 3, colName: "Value", old: "old", new: "simplevalue")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["mykey", "string", nil, "old"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "SET mykey simplevalue")
    }

    @Test("Value with space is double-quoted")
    func testEscapeValueWithSpace() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 3, colName: "Value", old: "old", new: "hello world")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["mykey", "string", nil, "old"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "SET mykey \"hello world\"")
    }

    @Test("Value with double quote is escaped and quoted")
    func testEscapeValueWithDoubleQuote() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 3, colName: "Value", old: "old", new: "say \"hi\"")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["mykey", "string", nil, "old"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "SET mykey \"say \\\"hi\\\"\"")
    }

    @Test("Empty string value is quoted as empty double quotes")
    func testEscapeEmptyString() {
        let gen = makeGenerator()
        let changes = [TestFixtures.makeRowChange(row: 0, type: .insert)]
        let insertedRowData: [Int: [String?]] = [0: ["mykey", "string", nil, nil]]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "SET mykey \"\"")
    }

    // MARK: - Column Index Tests

    @Test("Columns without Key column result in nil keyColumnIndex")
    func testMissingKeyColumn() {
        let gen = makeGenerator(columns: ["Name", "Type", "TTL", "Value"])
        #expect(gen.keyColumnIndex == nil)
    }
}

// MARK: - Escape Argument Edge Cases

@Suite("Escape Argument Edge Cases")
struct RedisStatementGeneratorEscapeEdgeCaseTests {
    private let defaultColumns = ["Key", "Type", "TTL", "Value"]

    private func makeGenerator(columns: [String]? = nil) -> RedisStatementGenerator {
        RedisStatementGenerator(namespaceName: "test", columns: columns ?? defaultColumns)
    }

    @Test("Backslash in value without other special chars is not quoted")
    func testBackslashInValueNotQuoted() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 3, colName: "Value", old: "old", new: "path\\to")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["mykey", "string", nil, "old"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.count == 1)
        // Backslash alone does not trigger quoting — returned as-is
        #expect(stmts[0].sql == "SET mykey path\\to")
    }

    @Test("Single quote in value triggers quoting")
    func testSingleQuoteInValue() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 3, colName: "Value", old: "old", new: "it's")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["mykey", "string", nil, "old"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "SET mykey \"it's\"")
    }

    @Test("Tab character in value triggers quoting")
    func testTabInValue() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 3, colName: "Value", old: "old", new: "a\tb")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["mykey", "string", nil, "old"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "SET mykey \"a\tb\"")
    }

    @Test("Newline in value triggers quoting")
    func testNewlineInValue() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 3, colName: "Value", old: "old", new: "a\nb")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["mykey", "string", nil, "old"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "SET mykey \"a\nb\"")
    }

    @Test("Value with both space and double-quote escapes properly")
    func testValueWithSpaceAndDoubleQuote() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 3, colName: "Value", old: "old", new: "say \"hi\" now")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["mykey", "string", nil, "old"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "SET mykey \"say \\\"hi\\\" now\"")
    }
}

// MARK: - Mixed Operations

@Suite("Mixed Operations")
struct RedisStatementGeneratorMixedOperationsTests {
    private let defaultColumns = ["Key", "Type", "TTL", "Value"]

    private func makeGenerator(columns: [String]? = nil) -> RedisStatementGenerator {
        RedisStatementGenerator(namespaceName: "test", columns: columns ?? defaultColumns)
    }

    @Test("Mixed insert, update, and delete in one call")
    func testMixedInsertUpdateDelete() {
        let gen = makeGenerator()

        let updateCells = [
            TestFixtures.makeCellChange(row: 1, col: 3, colName: "Value", old: "oldval", new: "newval")
        ]

        let changes = [
            TestFixtures.makeRowChange(row: 0, type: .insert),
            TestFixtures.makeRowChange(
                row: 1,
                type: .update,
                cells: updateCells,
                originalRow: ["updatekey", "string", nil, "oldval"]
            ),
            TestFixtures.makeRowChange(
                row: 2,
                type: .delete,
                cells: [],
                originalRow: ["delkey", "string", nil, "v"]
            )
        ]
        let insertedRowData: [Int: [String?]] = [0: ["insertkey", "string", nil, "insertval"]]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [2],
            insertedRowIndices: [0]
        )

        // Should have: SET insertkey insertval, SET updatekey newval, DEL delkey
        #expect(stmts.count == 3)
        #expect(stmts[0].sql == "SET insertkey insertval")
        #expect(stmts[1].sql == "SET updatekey newval")
        #expect(stmts[2].sql == "DEL delkey")
    }

    @Test("Delete key with space is quoted in DEL command")
    func testDeleteKeyWithSpace() {
        let gen = makeGenerator()
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .delete,
            cells: [],
            originalRow: ["my key", "string", nil, "hello"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [0],
            insertedRowIndices: []
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "DEL \"my key\"")
    }

    @Test("TTL update with non-integer string produces no TTL command")
    func testTtlNonIntegerString() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 2, colName: "TTL", old: "60", new: "abc")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["mykey", "string", "60", "hello"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        // "abc" is not parseable as Int, and is neither nil nor "-1", so no command
        #expect(stmts.isEmpty)
    }

    @Test("Key rename where new equals old produces no RENAME command")
    func testKeyRenameNewEqualsOld() {
        let gen = makeGenerator()
        let cells = [
            TestFixtures.makeCellChange(row: 0, col: 0, colName: "Key", old: "samekey", new: "samekey"),
            TestFixtures.makeCellChange(row: 0, col: 3, colName: "Value", old: "old", new: "new")
        ]
        let changes = [TestFixtures.makeRowChange(
            row: 0,
            type: .update,
            cells: cells,
            originalRow: ["samekey", "string", nil, "old"]
        )]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        // No RENAME since new key == old key; only a SET for the value change
        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "SET samekey new")
    }

    @Test("Insert from insertedRowData with nil value emits SET key with empty quoted string")
    func testInsertNilValueEmitsEmptyString() {
        let gen = makeGenerator()
        let changes = [TestFixtures.makeRowChange(row: 0, type: .insert)]
        let insertedRowData: [Int: [String?]] = [0: ["mykey", "string", nil, nil]]

        let stmts = gen.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(stmts.count == 1)
        #expect(stmts[0].sql == "SET mykey \"\"")
    }
}
