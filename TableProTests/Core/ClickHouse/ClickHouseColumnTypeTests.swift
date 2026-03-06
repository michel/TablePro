//
//  ClickHouseColumnTypeTests.swift
//  TableProTests
//
//  Tests for ColumnType(fromClickHouseType:) initialization
//

import Foundation
import Testing
@testable import TablePro

@Suite("ClickHouse Column Type")
struct ClickHouseColumnTypeTests {

    // MARK: - Integer Types

    @Test("Int8 maps to integer", arguments: ["Int8", "Int16", "Int32", "Int64"])
    func testSignedIntegerTypes(type: String) {
        let columnType = ColumnType(fromClickHouseType: type)
        #expect(columnType == .integer(rawType: type))
    }

    @Test("UInt types map to integer", arguments: ["UInt8", "UInt16", "UInt32", "UInt64"])
    func testUnsignedIntegerTypes(type: String) {
        let columnType = ColumnType(fromClickHouseType: type)
        #expect(columnType == .integer(rawType: type))
    }

    @Test("Int128 and Int256 map to integer", arguments: ["Int128", "Int256", "UInt128", "UInt256"])
    func testLargeIntegerTypes(type: String) {
        let columnType = ColumnType(fromClickHouseType: type)
        #expect(columnType == .integer(rawType: type))
    }

    // MARK: - Decimal Types

    @Test("Float32 maps to decimal")
    func testFloat32() {
        let columnType = ColumnType(fromClickHouseType: "Float32")
        #expect(columnType == .decimal(rawType: "Float32"))
    }

    @Test("Float64 maps to decimal")
    func testFloat64() {
        let columnType = ColumnType(fromClickHouseType: "Float64")
        #expect(columnType == .decimal(rawType: "Float64"))
    }

    @Test("Decimal(18,2) maps to decimal")
    func testDecimalWithPrecision() {
        let columnType = ColumnType(fromClickHouseType: "Decimal(18,2)")
        #expect(columnType == .decimal(rawType: "Decimal(18,2)"))
    }

    @Test("Decimal32 maps to decimal")
    func testDecimal32() {
        let columnType = ColumnType(fromClickHouseType: "Decimal32")
        #expect(columnType == .decimal(rawType: "Decimal32"))
    }

    // MARK: - Date Types

    @Test("Date maps to date")
    func testDate() {
        let columnType = ColumnType(fromClickHouseType: "Date")
        #expect(columnType == .date(rawType: "Date"))
    }

    @Test("Date32 maps to date")
    func testDate32() {
        let columnType = ColumnType(fromClickHouseType: "Date32")
        #expect(columnType == .date(rawType: "Date32"))
    }

    // MARK: - DateTime Types

    @Test("DateTime maps to datetime")
    func testDateTime() {
        let columnType = ColumnType(fromClickHouseType: "DateTime")
        #expect(columnType == .datetime(rawType: "DateTime"))
    }

    @Test("DateTime64(3) maps to datetime")
    func testDateTime64() {
        let columnType = ColumnType(fromClickHouseType: "DateTime64(3)")
        #expect(columnType == .datetime(rawType: "DateTime64(3)"))
    }

    // MARK: - Boolean Type

    @Test("Bool maps to boolean")
    func testBool() {
        let columnType = ColumnType(fromClickHouseType: "Bool")
        #expect(columnType == .boolean(rawType: "Bool"))
    }

    // MARK: - Text Types

    @Test("String maps to text")
    func testString() {
        let columnType = ColumnType(fromClickHouseType: "String")
        #expect(columnType == .text(rawType: "String"))
    }

    @Test("FixedString(100) maps to text")
    func testFixedString() {
        let columnType = ColumnType(fromClickHouseType: "FixedString(100)")
        #expect(columnType == .text(rawType: "FixedString(100)"))
    }

    @Test("UUID maps to text")
    func testUuid() {
        let columnType = ColumnType(fromClickHouseType: "UUID")
        #expect(columnType == .text(rawType: "UUID"))
    }

    @Test("IPv4 maps to text")
    func testIpv4() {
        let columnType = ColumnType(fromClickHouseType: "IPv4")
        #expect(columnType == .text(rawType: "IPv4"))
    }

    @Test("IPv6 maps to text")
    func testIpv6() {
        let columnType = ColumnType(fromClickHouseType: "IPv6")
        #expect(columnType == .text(rawType: "IPv6"))
    }

    @Test("Enum8 maps to text")
    func testEnum8() {
        let columnType = ColumnType(fromClickHouseType: "Enum8('a' = 1, 'b' = 2)")
        #expect(columnType == .text(rawType: "Enum8('a' = 1, 'b' = 2)"))
    }

    @Test("Enum16 maps to text")
    func testEnum16() {
        let columnType = ColumnType(fromClickHouseType: "Enum16('x' = 1)")
        #expect(columnType == .text(rawType: "Enum16('x' = 1)"))
    }

    // MARK: - JSON / Structured Types

    @Test("Array(String) maps to json")
    func testArray() {
        let columnType = ColumnType(fromClickHouseType: "Array(String)")
        #expect(columnType == .json(rawType: "Array(String)"))
    }

    @Test("Tuple(Int32, String) maps to json")
    func testTuple() {
        let columnType = ColumnType(fromClickHouseType: "Tuple(Int32, String)")
        #expect(columnType == .json(rawType: "Tuple(Int32, String)"))
    }

    @Test("Map(String, Int64) maps to json")
    func testMap() {
        let columnType = ColumnType(fromClickHouseType: "Map(String, Int64)")
        #expect(columnType == .json(rawType: "Map(String, Int64)"))
    }

    @Test("JSON maps to json")
    func testJson() {
        let columnType = ColumnType(fromClickHouseType: "JSON")
        #expect(columnType == .json(rawType: "JSON"))
    }

    // MARK: - Nullable Wrapper

    @Test("Nullable(Int32) maps to integer with original rawType")
    func testNullableInt() {
        let columnType = ColumnType(fromClickHouseType: "Nullable(Int32)")
        #expect(columnType == .integer(rawType: "Nullable(Int32)"))
    }

    @Test("Nullable(String) maps to text")
    func testNullableString() {
        let columnType = ColumnType(fromClickHouseType: "Nullable(String)")
        #expect(columnType == .text(rawType: "Nullable(String)"))
    }

    @Test("Nullable(Float64) maps to decimal")
    func testNullableFloat() {
        let columnType = ColumnType(fromClickHouseType: "Nullable(Float64)")
        #expect(columnType == .decimal(rawType: "Nullable(Float64)"))
    }

    @Test("Nullable(DateTime) maps to datetime")
    func testNullableDateTime() {
        let columnType = ColumnType(fromClickHouseType: "Nullable(DateTime)")
        #expect(columnType == .datetime(rawType: "Nullable(DateTime)"))
    }

    // MARK: - LowCardinality Wrapper

    @Test("LowCardinality(String) maps to text")
    func testLowCardinalityString() {
        let columnType = ColumnType(fromClickHouseType: "LowCardinality(String)")
        #expect(columnType == .text(rawType: "LowCardinality(String)"))
    }

    @Test("LowCardinality(UInt32) maps to integer")
    func testLowCardinalityUint() {
        let columnType = ColumnType(fromClickHouseType: "LowCardinality(UInt32)")
        #expect(columnType == .integer(rawType: "LowCardinality(UInt32)"))
    }

    // MARK: - Nested Wrappers

    @Test("Nullable(LowCardinality(String)) maps to text")
    func testNestedNullableLowCardinality() {
        let columnType = ColumnType(fromClickHouseType: "Nullable(LowCardinality(String))")
        #expect(columnType == .text(rawType: "Nullable(LowCardinality(String))"))
    }

    // MARK: - Nil Input

    @Test("nil input maps to text with nil rawType")
    func testNilInput() {
        let columnType = ColumnType(fromClickHouseType: nil)
        #expect(columnType == .text(rawType: nil))
    }
}
