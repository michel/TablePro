//
//  DatabaseTypeTests.swift
//  TableProTests
//
//  Tests for DatabaseType enum
//

import Foundation
import Testing
@testable import TablePro

@Suite("DatabaseType")
struct DatabaseTypeTests {

    @Test("MySQL default port is 3306")
    func testMySQLDefaultPort() {
        #expect(DatabaseType.mysql.defaultPort == 3306)
    }

    @Test("MariaDB default port is 3306")
    func testMariaDBDefaultPort() {
        #expect(DatabaseType.mariadb.defaultPort == 3306)
    }

    @Test("PostgreSQL default port is 5432")
    func testPostgreSQLDefaultPort() {
        #expect(DatabaseType.postgresql.defaultPort == 5432)
    }

    @Test("SQLite default port is 0")
    func testSQLiteDefaultPort() {
        #expect(DatabaseType.sqlite.defaultPort == 0)
    }

    @Test("MongoDB default port is 27017")
    func testMongoDBDefaultPort() {
        #expect(DatabaseType.mongodb.defaultPort == 27_017)
    }

    @Test("MySQL identifier quote is backtick")
    func testMySQLIdentifierQuote() {
        #expect(DatabaseType.mysql.identifierQuote == "`")
    }

    @Test("PostgreSQL identifier quote is double quote")
    func testPostgreSQLIdentifierQuote() {
        #expect(DatabaseType.postgresql.identifierQuote == "\"")
    }

    @Test("Quote identifier simple name for MySQL")
    func testQuoteIdentifierSimpleNameMySQL() {
        let result = DatabaseType.mysql.quoteIdentifier("users")
        #expect(result == "`users`")
    }

    @Test("Quote identifier simple name for PostgreSQL")
    func testQuoteIdentifierSimpleNamePostgreSQL() {
        let result = DatabaseType.postgresql.quoteIdentifier("users")
        #expect(result == "\"users\"")
    }

    @Test("Quote identifier with embedded backtick for MySQL")
    func testQuoteIdentifierWithEmbeddedBacktickMySQL() {
        let result = DatabaseType.mysql.quoteIdentifier("user`s")
        #expect(result == "`user``s`")
    }

    @Test("Quote identifier with embedded double quote for PostgreSQL")
    func testQuoteIdentifierWithEmbeddedDoubleQuotePostgreSQL() {
        let result = DatabaseType.postgresql.quoteIdentifier("user\"s")
        #expect(result == "\"user\"\"s\"")
    }

    @Test("CaseIterable count is 10")
    func testCaseIterableCount() {
        #expect(DatabaseType.allCases.count == 10)
    }

    @Test("Raw value matches display name", arguments: [
        (DatabaseType.mysql, "MySQL"),
        (DatabaseType.mariadb, "MariaDB"),
        (DatabaseType.postgresql, "PostgreSQL"),
        (DatabaseType.sqlite, "SQLite"),
        (DatabaseType.mongodb, "MongoDB"),
        (DatabaseType.redis, "Redis"),
        (DatabaseType.redshift, "Redshift"),
        (DatabaseType.mssql, "SQL Server"),
        (DatabaseType.oracle, "Oracle"),
        (DatabaseType.clickhouse, "ClickHouse")
    ])
    func testRawValueMatchesDisplayName(dbType: DatabaseType, expectedRawValue: String) {
        #expect(dbType.rawValue == expectedRawValue)
    }

    // MARK: - ClickHouse Tests

    @Test("ClickHouse default port is 8123")
    func testClickHouseDefaultPort() {
        #expect(DatabaseType.clickhouse.defaultPort == 8_123)
    }

    @Test("ClickHouse identifier quote is backtick")
    func testClickHouseIdentifierQuote() {
        #expect(DatabaseType.clickhouse.identifierQuote == "`")
    }

    @Test("ClickHouse requires authentication")
    func testClickHouseRequiresAuth() {
        #expect(DatabaseType.clickhouse.requiresAuthentication == true)
    }

    @Test("ClickHouse does not support foreign keys")
    func testClickHouseSupportsForeignKeys() {
        #expect(DatabaseType.clickhouse.supportsForeignKeys == false)
    }

    @Test("ClickHouse supports schema editing")
    func testClickHouseSupportsSchemaEditing() {
        #expect(DatabaseType.clickhouse.supportsSchemaEditing == true)
    }

    @Test("ClickHouse icon name is clickhouse-icon")
    func testClickHouseIconName() {
        #expect(DatabaseType.clickhouse.iconName == "clickhouse-icon")
    }
}
