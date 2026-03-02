//
//  MongoDBStatementGeneratorTests.swift
//  TableProTests
//
//  Tests for MongoDBStatementGenerator
//

import Foundation
import Testing
@testable import TablePro

@Suite("MongoDB Statement Generator")
struct MongoDBStatementGeneratorTests {

    // MARK: - Helper Methods

    private func makeGenerator(
        collection: String = "users",
        columns: [String] = ["_id", "name", "email"]
    ) -> MongoDBStatementGenerator {
        MongoDBStatementGenerator(collectionName: collection, columns: columns)
    }

    // MARK: - INSERT Tests

    @Test("Simple insert generates insertOne with sorted keys, skipping _id")
    func testSimpleInsert() {
        let generator = makeGenerator()
        let insertedRowData: [Int: [String?]] = [
            0: [nil, "John", "john@test.com"]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil)
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql == "db[\"users\"].insertOne({\"email\": \"john@test.com\", \"name\": \"John\"})")
        #expect(stmt.parameters.isEmpty)
    }

    @Test("Insert skips __DEFAULT__ sentinel values")
    func testInsertSkipsDefaultSentinel() {
        let generator = makeGenerator()
        let insertedRowData: [Int: [String?]] = [
            0: [nil, "__DEFAULT__", "john@test.com"]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil)
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("\"email\": \"john@test.com\""))
        #expect(!stmt.sql.contains("name"))
        #expect(!stmt.sql.contains("__DEFAULT__"))
    }

    @Test("Insert skips _id column to let MongoDB auto-generate")
    func testInsertSkipsIdColumn() {
        let generator = makeGenerator()
        let insertedRowData: [Int: [String?]] = [
            0: ["some_id_value", "John", "john@test.com"]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil)
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(!stmt.sql.contains("_id"))
        #expect(stmt.sql.contains("\"name\": \"John\""))
        #expect(stmt.sql.contains("\"email\": \"john@test.com\""))
    }

    @Test("Insert with nil values omits those fields from document")
    func testInsertWithNilValuesOmitted() {
        let generator = makeGenerator()
        let insertedRowData: [Int: [String?]] = [
            0: [nil, "John", nil]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil)
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("\"name\": \"John\""))
        #expect(!stmt.sql.contains("email"))
    }

    @Test("Empty insert with all nil/default values returns no statement")
    func testEmptyInsertReturnsEmpty() {
        let generator = makeGenerator()
        let insertedRowData: [Int: [String?]] = [
            0: [nil, nil, nil]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil)
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(statements.isEmpty)
    }

    @Test("Insert falls back to cellChanges when insertedRowData missing")
    func testInsertFromCellChangesFallback() {
        let generator = makeGenerator()
        let changes: [RowChange] = [
            RowChange(
                rowIndex: 0,
                type: .insert,
                cellChanges: [
                    CellChange(rowIndex: 0, columnIndex: 1, columnName: "name", oldValue: nil, newValue: "John"),
                    CellChange(rowIndex: 0, columnIndex: 2, columnName: "email", oldValue: nil, newValue: "john@test.com")
                ],
                originalRow: nil
            )
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("insertOne"))
        #expect(stmt.sql.contains("\"name\": \"John\""))
        #expect(stmt.sql.contains("\"email\": \"john@test.com\""))
        #expect(stmt.parameters.isEmpty)
    }

    // MARK: - UPDATE Tests

    @Test("Simple update with ObjectId _id uses $oid extended JSON")
    func testSimpleUpdateWithObjectId() {
        let generator = makeGenerator()
        let changes: [RowChange] = [
            RowChange(
                rowIndex: 0,
                type: .update,
                cellChanges: [
                    CellChange(rowIndex: 0, columnIndex: 1, columnName: "name", oldValue: "John", newValue: "Jane")
                ],
                originalRow: ["abc123def456abc123def456", "John", "john@test.com"]
            )
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("db[\"users\"].updateOne("))
        #expect(stmt.sql.contains("{\"_id\": {\"$oid\": \"abc123def456abc123def456\"}}"))
        #expect(stmt.sql.contains("{\"$set\": {\"name\": \"Jane\"}}"))
        #expect(stmt.parameters.isEmpty)
    }

    @Test("Update with numeric _id uses raw number")
    func testUpdateWithNumericId() {
        let generator = makeGenerator()
        let changes: [RowChange] = [
            RowChange(
                rowIndex: 0,
                type: .update,
                cellChanges: [
                    CellChange(rowIndex: 0, columnIndex: 1, columnName: "name", oldValue: "John", newValue: "Jane")
                ],
                originalRow: ["42", "John", "john@test.com"]
            )
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("{\"_id\": 42}"))
    }

    @Test("Update with non-ObjectId string _id uses quoted string")
    func testUpdateWithStringId() {
        let generator = makeGenerator()
        let changes: [RowChange] = [
            RowChange(
                rowIndex: 0,
                type: .update,
                cellChanges: [
                    CellChange(rowIndex: 0, columnIndex: 1, columnName: "name", oldValue: "John", newValue: "Jane")
                ],
                originalRow: ["some-string", "John", "john@test.com"]
            )
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("{\"_id\": \"some-string\"}"))
    }

    @Test("Update setting value to null uses $unset to remove the field")
    func testUpdateSetValueToNull() {
        let generator = makeGenerator()
        let changes: [RowChange] = [
            RowChange(
                rowIndex: 0,
                type: .update,
                cellChanges: [
                    CellChange(rowIndex: 0, columnIndex: 2, columnName: "email", oldValue: "john@test.com", newValue: nil)
                ],
                originalRow: ["abc123def456abc123def456", "John", "john@test.com"]
            )
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("\"$unset\": {\"email\": \"\"}"))
        #expect(!stmt.sql.contains("\"$set\""))
    }

    @Test("Update with mixed null and non-null values uses both $set and $unset")
    func testUpdateMixedSetAndUnset() {
        let generator = makeGenerator()
        let changes: [RowChange] = [
            RowChange(
                rowIndex: 0,
                type: .update,
                cellChanges: [
                    CellChange(rowIndex: 0, columnIndex: 1, columnName: "name", oldValue: "John", newValue: "Jane"),
                    CellChange(rowIndex: 0, columnIndex: 2, columnName: "email", oldValue: "john@test.com", newValue: nil)
                ],
                originalRow: ["abc123def456abc123def456", "John", "john@test.com"]
            )
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("\"$set\": {\"name\": \"Jane\"}"))
        #expect(stmt.sql.contains("\"$unset\": {\"email\": \"\"}"))
    }

    @Test("Update without _id column returns no statement")
    func testUpdateWithoutIdColumn() {
        let generator = makeGenerator(columns: ["name", "email", "age"])
        let changes: [RowChange] = [
            RowChange(
                rowIndex: 0,
                type: .update,
                cellChanges: [
                    CellChange(rowIndex: 0, columnIndex: 0, columnName: "name", oldValue: "John", newValue: "Jane")
                ],
                originalRow: ["John", "john@test.com", "30"]
            )
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(statements.isEmpty)
    }

    @Test("Multiple cell changes in one update produce single $set document")
    func testUpdateMultipleCellChanges() {
        let generator = makeGenerator()
        let changes: [RowChange] = [
            RowChange(
                rowIndex: 0,
                type: .update,
                cellChanges: [
                    CellChange(rowIndex: 0, columnIndex: 1, columnName: "name", oldValue: "John", newValue: "Jane"),
                    CellChange(rowIndex: 0, columnIndex: 2, columnName: "email", oldValue: "john@test.com", newValue: "jane@test.com")
                ],
                originalRow: ["abc123def456abc123def456", "John", "john@test.com"]
            )
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("updateOne"))
        #expect(stmt.sql.contains("\"$set\":"))
        #expect(stmt.sql.contains("\"name\": \"Jane\""))
        #expect(stmt.sql.contains("\"email\": \"jane@test.com\""))
    }

    // MARK: - DELETE Tests

    @Test("Delete with ObjectId _id uses $oid extended JSON")
    func testDeleteWithObjectId() {
        let generator = makeGenerator()
        let changes: [RowChange] = [
            RowChange(
                rowIndex: 0,
                type: .delete,
                cellChanges: [],
                originalRow: ["abc123def456abc123def456", "John", "john@test.com"]
            )
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [0],
            insertedRowIndices: []
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("db[\"users\"].deleteOne("))
        #expect(stmt.sql.contains("{\"_id\": {\"$oid\": \"abc123def456abc123def456\"}}"))
        #expect(stmt.parameters.isEmpty)
    }

    @Test("Delete with numeric _id uses raw number")
    func testDeleteWithNumericId() {
        let generator = makeGenerator()
        let changes: [RowChange] = [
            RowChange(
                rowIndex: 0,
                type: .delete,
                cellChanges: [],
                originalRow: ["42", "John", "john@test.com"]
            )
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [0],
            insertedRowIndices: []
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("{\"_id\": 42}"))
    }

    @Test("Delete without _id falls back to matching all fields")
    func testDeleteWithoutIdFallbackToAllFields() {
        let generator = makeGenerator(columns: ["name", "email", "age"])
        let changes: [RowChange] = [
            RowChange(
                rowIndex: 0,
                type: .delete,
                cellChanges: [],
                originalRow: ["John", "john@test.com", "30"]
            )
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [0],
            insertedRowIndices: []
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("deleteOne"))
        #expect(stmt.sql.contains("\"name\": \"John\""))
        #expect(stmt.sql.contains("\"email\": \"john@test.com\""))
        #expect(stmt.sql.contains("\"age\": 30"))
    }

    @Test("Delete without originalRow returns no statement")
    func testDeleteWithoutOriginalRow() {
        let generator = makeGenerator()
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .delete, cellChanges: [], originalRow: nil)
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [0],
            insertedRowIndices: []
        )

        #expect(statements.isEmpty)
    }

    // MARK: - Mixed Operations

    @Test("Multiple changes generate all statements in order")
    func testMixedOperationsGenerateAllStatements() {
        let generator = makeGenerator()
        let insertedRowData: [Int: [String?]] = [
            0: [nil, "Bob", "bob@test.com"]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil),
            RowChange(
                rowIndex: 1,
                type: .update,
                cellChanges: [
                    CellChange(rowIndex: 1, columnIndex: 1, columnName: "name", oldValue: "John", newValue: "Jane")
                ],
                originalRow: ["abc123def456abc123def456", "John", "john@test.com"]
            ),
            RowChange(
                rowIndex: 2,
                type: .delete,
                cellChanges: [],
                originalRow: ["def456abc123def456abc123", "Alice", "alice@test.com"]
            )
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [2],
            insertedRowIndices: [0]
        )

        #expect(statements.count == 3)
        #expect(statements[0].sql.contains("insertOne"))
        #expect(statements[1].sql.contains("updateOne"))
        #expect(statements[2].sql.contains("deleteOne"))
    }

    // MARK: - JSON Value Detection Tests

    @Test("Boolean string true is unquoted in JSON")
    func testBooleanTrueUnquoted() {
        let generator = makeGenerator(columns: ["_id", "active"])
        let insertedRowData: [Int: [String?]] = [
            0: [nil, "true"]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil)
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("\"active\": true"))
        #expect(!stmt.sql.contains("\"active\": \"true\""))
    }

    @Test("Boolean string false is unquoted in JSON")
    func testBooleanFalseUnquoted() {
        let generator = makeGenerator(columns: ["_id", "active"])
        let insertedRowData: [Int: [String?]] = [
            0: [nil, "false"]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil)
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("\"active\": false"))
        #expect(!stmt.sql.contains("\"active\": \"false\""))
    }

    @Test("Integer string is unquoted in JSON")
    func testIntegerUnquoted() {
        let generator = makeGenerator(columns: ["_id", "age"])
        let insertedRowData: [Int: [String?]] = [
            0: [nil, "42"]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil)
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("\"age\": 42"))
        #expect(!stmt.sql.contains("\"age\": \"42\""))
    }

    @Test("Double string is unquoted in JSON")
    func testDoubleUnquoted() {
        let generator = makeGenerator(columns: ["_id", "score"])
        let insertedRowData: [Int: [String?]] = [
            0: [nil, "3.14"]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil)
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("\"score\": 3.14"))
        #expect(!stmt.sql.contains("\"score\": \"3.14\""))
    }

    @Test("JSON object string is passed through as-is")
    func testJsonObjectPassedThrough() {
        let generator = makeGenerator(columns: ["_id", "metadata"])
        let insertedRowData: [Int: [String?]] = [
            0: [nil, "{\"key\": \"val\"}"]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil)
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("\"metadata\": {\"key\": \"val\"}"))
    }

    @Test("Regular string is quoted with escaping")
    func testRegularStringQuoted() {
        let generator = makeGenerator(columns: ["_id", "name"])
        let insertedRowData: [Int: [String?]] = [
            0: [nil, "hello world"]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil)
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("\"name\": \"hello world\""))
    }

    // MARK: - Bulk Insert Tests

    @Test("Bulk insert with multiple rows generates insertMany")
    func testBulkInsertMultipleRows() {
        let generator = makeGenerator()
        let insertedRowData: [Int: [String?]] = [
            0: [nil, "John", "john@test.com"],
            1: [nil, "Jane", "jane@test.com"]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil),
            RowChange(rowIndex: 1, type: .insert, cellChanges: [], originalRow: nil)
        ]

        let stmt = generator.generateBulkInsert(
            from: changes,
            insertedRowData: insertedRowData,
            insertedRowIndices: [0, 1]
        )

        #expect(stmt != nil)
        #expect(stmt?.sql.contains("insertMany") == true)
        #expect(stmt?.sql.contains("\"name\": \"John\"") == true)
        #expect(stmt?.sql.contains("\"name\": \"Jane\"") == true)
        #expect(stmt?.parameters.isEmpty == true)
    }

    @Test("Bulk insert with single row returns nil")
    func testBulkInsertSingleRowReturnsNil() {
        let generator = makeGenerator()
        let insertedRowData: [Int: [String?]] = [
            0: [nil, "John", "john@test.com"]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil)
        ]

        let stmt = generator.generateBulkInsert(
            from: changes,
            insertedRowData: insertedRowData,
            insertedRowIndices: [0]
        )

        #expect(stmt == nil)
    }

    @Test("Bulk insert skips _id and __DEFAULT__ values")
    func testBulkInsertSkipsIdAndDefault() {
        let generator = makeGenerator()
        let insertedRowData: [Int: [String?]] = [
            0: ["some_id", "John", "__DEFAULT__"],
            1: [nil, "Jane", "jane@test.com"]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil),
            RowChange(rowIndex: 1, type: .insert, cellChanges: [], originalRow: nil)
        ]

        let stmt = generator.generateBulkInsert(
            from: changes,
            insertedRowData: insertedRowData,
            insertedRowIndices: [0, 1]
        )

        #expect(stmt != nil)
        #expect(stmt?.sql.contains("_id") == false)
        #expect(stmt?.sql.contains("__DEFAULT__") == false)
    }

    @Test("Bulk insert filters out non-insert changes")
    func testBulkInsertFiltersNonInsertChanges() {
        let generator = makeGenerator()
        let insertedRowData: [Int: [String?]] = [
            0: [nil, "John", "john@test.com"]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil),
            RowChange(
                rowIndex: 1,
                type: .update,
                cellChanges: [
                    CellChange(rowIndex: 1, columnIndex: 1, columnName: "name", oldValue: "John", newValue: "Jane")
                ],
                originalRow: ["abc123def456abc123def456", "John", "john@test.com"]
            )
        ]

        let stmt = generator.generateBulkInsert(
            from: changes,
            insertedRowData: insertedRowData,
            insertedRowIndices: [0]
        )

        #expect(stmt == nil)
    }

    // MARK: - Bulk Delete Tests

    @Test("Bulk delete with ObjectId _ids generates deleteMany with $in")
    func testBulkDeleteWithObjectIds() {
        let generator = makeGenerator()
        let changes: [RowChange] = [
            RowChange(
                rowIndex: 0,
                type: .delete,
                cellChanges: [],
                originalRow: ["abc123def456abc123def456", "John", "john@test.com"]
            ),
            RowChange(
                rowIndex: 1,
                type: .delete,
                cellChanges: [],
                originalRow: ["def456abc123def456abc123", "Jane", "jane@test.com"]
            )
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [0, 1],
            insertedRowIndices: []
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("deleteMany"))
        #expect(stmt.sql.contains("\"$in\""))
        #expect(stmt.sql.contains("{\"$oid\": \"abc123def456abc123def456\"}"))
        #expect(stmt.sql.contains("{\"$oid\": \"def456abc123def456abc123\"}"))
    }

    @Test("Bulk delete without _id falls back to individual deleteOne statements")
    func testBulkDeleteWithoutIdFallsBackToIndividual() {
        let generator = makeGenerator(columns: ["name", "email", "age"])
        let changes: [RowChange] = [
            RowChange(
                rowIndex: 0,
                type: .delete,
                cellChanges: [],
                originalRow: ["John", "john@test.com", "30"]
            ),
            RowChange(
                rowIndex: 1,
                type: .delete,
                cellChanges: [],
                originalRow: ["Jane", "jane@test.com", "25"]
            )
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: [:],
            deletedRowIndices: [0, 1],
            insertedRowIndices: []
        )

        #expect(statements.count == 2)
        #expect(statements[0].sql.contains("deleteOne"))
        #expect(statements[1].sql.contains("deleteOne"))
    }

    // MARK: - JSON String Escaping Tests

    @Test("escapeJsonString handles special characters and control chars")
    func testEscapeJsonStringSpecialChars() {
        let generator = makeGenerator(columns: ["_id", "text"])
        let insertedRowData: [Int: [String?]] = [
            0: [nil, "line1\nline2\ttab\\slash\"quote"]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil)
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )

        #expect(statements.count == 1)
        let stmt = statements[0]
        #expect(stmt.sql.contains("\\n"))
        #expect(stmt.sql.contains("\\t"))
        #expect(stmt.sql.contains("\\\\"))
        #expect(stmt.sql.contains("\\\""))
    }

    // MARK: - Parameters Always Empty

    @Test("All MongoDB statements have empty parameters array")
    func testParametersAlwaysEmpty() {
        let generator = makeGenerator()
        let insertedRowData: [Int: [String?]] = [
            0: [nil, "Bob", "bob@test.com"]
        ]
        let changes: [RowChange] = [
            RowChange(rowIndex: 0, type: .insert, cellChanges: [], originalRow: nil),
            RowChange(
                rowIndex: 1,
                type: .update,
                cellChanges: [
                    CellChange(rowIndex: 1, columnIndex: 1, columnName: "name", oldValue: "John", newValue: "Jane")
                ],
                originalRow: ["abc123def456abc123def456", "John", "john@test.com"]
            ),
            RowChange(
                rowIndex: 2,
                type: .delete,
                cellChanges: [],
                originalRow: ["def456abc123def456abc123", "Alice", "alice@test.com"]
            )
        ]

        let statements = generator.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: [2],
            insertedRowIndices: [0]
        )

        for stmt in statements {
            #expect(stmt.parameters.isEmpty)
        }
    }
}
