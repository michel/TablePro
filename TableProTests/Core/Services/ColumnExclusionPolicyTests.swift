//
//  ColumnExclusionPolicyTests.swift
//  TableProTests
//
//  Tests for ColumnExclusionPolicy selective column exclusion logic.
//

import Foundation
@testable import TablePro
import Testing

@Suite("ColumnExclusionPolicy")
struct ColumnExclusionPolicyTests {
    private func quoteMySQL(_ name: String) -> String {
        "`\(name)`"
    }

    private func quoteStandard(_ name: String) -> String {
        "\"\(name)\""
    }

    @Test("BLOB column excluded with LENGTH expression")
    func blobColumnExcluded() {
        let columns = ["id", "name", "photo"]
        let types: [ColumnType] = [
            .integer(rawType: "INT"),
            .text(rawType: "VARCHAR"),
            .blob(rawType: "BLOB")
        ]
        let exclusions = ColumnExclusionPolicy.exclusions(
            columns: columns, columnTypes: types,
            databaseType: .mysql, quoteIdentifier: quoteMySQL
        )
        #expect(exclusions.count == 1)
        #expect(exclusions[0].columnName == "photo")
        #expect(exclusions[0].placeholderExpression == "LENGTH(`photo`)")
    }

    @Test("LONGTEXT column excluded with SUBSTRING expression")
    func longTextColumnExcluded() {
        let columns = ["id", "content"]
        let types: [ColumnType] = [
            .integer(rawType: "INT"),
            .text(rawType: "LONGTEXT")
        ]
        let exclusions = ColumnExclusionPolicy.exclusions(
            columns: columns, columnTypes: types,
            databaseType: .mysql, quoteIdentifier: quoteMySQL
        )
        #expect(exclusions.count == 1)
        #expect(exclusions[0].columnName == "content")
        #expect(exclusions[0].placeholderExpression == "SUBSTRING(`content`, 1, 256)")
    }

    @Test("VARCHAR and INTEGER columns NOT excluded")
    func normalColumnsNotExcluded() {
        let columns = ["id", "name", "age"]
        let types: [ColumnType] = [
            .integer(rawType: "INT"),
            .text(rawType: "VARCHAR"),
            .integer(rawType: "BIGINT")
        ]
        let exclusions = ColumnExclusionPolicy.exclusions(
            columns: columns, columnTypes: types,
            databaseType: .mysql, quoteIdentifier: quoteMySQL
        )
        #expect(exclusions.isEmpty)
    }

    @Test("DATE and TIMESTAMP columns NOT excluded")
    func dateColumnsNotExcluded() {
        let columns = ["created_at", "updated_at"]
        let types: [ColumnType] = [
            .date(rawType: "DATE"),
            .timestamp(rawType: "TIMESTAMP")
        ]
        let exclusions = ColumnExclusionPolicy.exclusions(
            columns: columns, columnTypes: types,
            databaseType: .postgresql, quoteIdentifier: quoteStandard
        )
        #expect(exclusions.isEmpty)
    }

    @Test("Empty columns produces no exclusions")
    func emptyColumnsNoExclusions() {
        let exclusions = ColumnExclusionPolicy.exclusions(
            columns: [], columnTypes: [],
            databaseType: .mysql, quoteIdentifier: quoteMySQL
        )
        #expect(exclusions.isEmpty)
    }

    @Test("MSSQL uses DATALENGTH for BLOB columns")
    func mssqlUsesDatalength() {
        let columns = ["data"]
        let types: [ColumnType] = [.blob(rawType: "VARBINARY")]
        let exclusions = ColumnExclusionPolicy.exclusions(
            columns: columns, columnTypes: types,
            databaseType: .mssql, quoteIdentifier: quoteStandard
        )
        #expect(exclusions.count == 1)
        #expect(exclusions[0].placeholderExpression == "DATALENGTH(\"data\")")
    }

    @Test("SQLite uses SUBSTR for LONGTEXT columns")
    func sqliteUsesSubstr() {
        let columns = ["body"]
        let types: [ColumnType] = [.text(rawType: "TEXT")]
        let exclusions = ColumnExclusionPolicy.exclusions(
            columns: columns, columnTypes: types,
            databaseType: .sqlite, quoteIdentifier: quoteStandard
        )
        // TEXT is isLongText = true for SQLite
        #expect(exclusions.count == 1)
        #expect(exclusions[0].placeholderExpression == "SUBSTR(\"body\", 1, 256)")
    }

    @Test("Mixed BLOB and LONGTEXT columns both excluded")
    func mixedExclusions() {
        let columns = ["id", "photo", "content", "name"]
        let types: [ColumnType] = [
            .integer(rawType: "INT"),
            .blob(rawType: "BLOB"),
            .text(rawType: "MEDIUMTEXT"),
            .text(rawType: "VARCHAR")
        ]
        let exclusions = ColumnExclusionPolicy.exclusions(
            columns: columns, columnTypes: types,
            databaseType: .postgresql, quoteIdentifier: quoteStandard
        )
        #expect(exclusions.count == 2)
        #expect(exclusions[0].columnName == "photo")
        #expect(exclusions[0].placeholderExpression == "LENGTH(\"photo\")")
        #expect(exclusions[1].columnName == "content")
        #expect(exclusions[1].placeholderExpression == "SUBSTRING(\"content\", 1, 256)")
    }

    @Test("Mismatched column/type counts handled safely")
    func mismatchedCounts() {
        let columns = ["id", "name", "photo"]
        let types: [ColumnType] = [
            .integer(rawType: "INT"),
            .text(rawType: "VARCHAR")
        ]
        let exclusions = ColumnExclusionPolicy.exclusions(
            columns: columns, columnTypes: types,
            databaseType: .mysql, quoteIdentifier: quoteMySQL
        )
        #expect(exclusions.isEmpty)
    }
}
