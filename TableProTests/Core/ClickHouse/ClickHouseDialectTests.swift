//
//  ClickHouseDialectTests.swift
//  TableProTests
//
//  Tests for ClickHouseDialect and SQLDialectFactory integration
//

import Foundation
import Testing
@testable import TablePro

@Suite("ClickHouse Dialect")
struct ClickHouseDialectTests {

    let dialect = ClickHouseDialect()

    // MARK: - Identifier Quote

    @Test("ClickHouse identifier quote is backtick")
    func testIdentifierQuote() {
        #expect(dialect.identifierQuote == "`")
    }

    // MARK: - ClickHouse-Specific Keywords

    @Test("Contains ClickHouse-specific keywords", arguments: [
        "FINAL", "SAMPLE", "PREWHERE", "FORMAT", "SETTINGS",
        "OPTIMIZE", "SYSTEM", "PARTITION", "TTL", "ENGINE", "CODEC"
    ])
    func testClickHouseSpecificKeywords(keyword: String) {
        #expect(dialect.keywords.contains(keyword))
    }

    @Test("Contains standard SQL keywords", arguments: [
        "SELECT", "FROM", "WHERE", "JOIN", "INSERT", "UPDATE", "DELETE",
        "CREATE", "ALTER", "DROP", "TABLE"
    ])
    func testStandardKeywords(keyword: String) {
        #expect(dialect.keywords.contains(keyword))
    }

    // MARK: - ClickHouse-Specific Functions

    @Test("Contains ClickHouse-specific functions", arguments: [
        "UNIQ", "UNIQEXACT", "ARGMIN", "ARGMAX", "GROUPARRAY",
        "TOSTRING", "TOINT32", "FORMATDATETIME",
        "MULTIIF", "ARRAYMAP", "ARRAYJOIN",
        "MATCH", "CURRENTDATABASE", "VERSION",
        "QUANTILE", "TOPK"
    ])
    func testClickHouseSpecificFunctions(function: String) {
        #expect(dialect.functions.contains(function))
    }

    @Test("Contains standard SQL functions", arguments: [
        "COUNT", "SUM", "AVG", "MAX", "MIN", "CONCAT", "CAST"
    ])
    func testStandardFunctions(function: String) {
        #expect(dialect.functions.contains(function))
    }

    // MARK: - ClickHouse-Specific Data Types

    @Test("Contains ClickHouse integer types", arguments: [
        "INT8", "INT16", "INT32", "INT64", "INT128", "INT256",
        "UINT8", "UINT16", "UINT32", "UINT64", "UINT128", "UINT256"
    ])
    func testIntegerDataTypes(dataType: String) {
        #expect(dialect.dataTypes.contains(dataType))
    }

    @Test("Contains ClickHouse float/decimal types", arguments: [
        "FLOAT32", "FLOAT64", "DECIMAL", "DECIMAL32", "DECIMAL64", "DECIMAL128", "DECIMAL256"
    ])
    func testFloatDecimalDataTypes(dataType: String) {
        #expect(dialect.dataTypes.contains(dataType))
    }

    @Test("Contains ClickHouse date/time types", arguments: [
        "DATE", "DATE32", "DATETIME", "DATETIME64"
    ])
    func testDateTimeDataTypes(dataType: String) {
        #expect(dialect.dataTypes.contains(dataType))
    }

    @Test("Contains ClickHouse complex types", arguments: [
        "ARRAY", "TUPLE", "MAP", "NULLABLE", "LOWCARDINALITY",
        "ENUM8", "ENUM16"
    ])
    func testComplexDataTypes(dataType: String) {
        #expect(dialect.dataTypes.contains(dataType))
    }

    @Test("Contains ClickHouse other types", arguments: [
        "STRING", "FIXEDSTRING", "UUID", "IPV4", "IPV6", "JSON", "BOOL"
    ])
    func testOtherDataTypes(dataType: String) {
        #expect(dialect.dataTypes.contains(dataType))
    }

    // MARK: - Dialect Factory

    @Test("Factory returns ClickHouseDialect for .clickhouse")
    func testFactoryReturnsClickHouseDialect() {
        let created = SQLDialectFactory.createDialect(for: .clickhouse)
        #expect(created is ClickHouseDialect)
    }
}
