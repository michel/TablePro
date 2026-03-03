//
//  RedshiftDriverTests.swift
//  TableProTests
//
//  Tests for Redshift database type properties and driver factory
//

import Foundation
import Testing
@testable import TablePro

@Suite("Redshift Database Type")
struct RedshiftDatabaseTypeTests {

    // MARK: - DatabaseType Properties

    @Test("Redshift default port is 5439")
    func testDefaultPort() {
        #expect(DatabaseType.redshift.defaultPort == 5_439)
    }

    @Test("Redshift icon name is redshift-icon")
    func testIconName() {
        #expect(DatabaseType.redshift.iconName == "redshift-icon")
    }

    @Test("Redshift uses double-quote identifier quoting")
    func testIdentifierQuote() {
        #expect(DatabaseType.redshift.identifierQuote == "\"")
    }

    @Test("Redshift requires authentication")
    func testRequiresAuthentication() {
        #expect(DatabaseType.redshift.requiresAuthentication == true)
    }

    @Test("Redshift supports foreign keys")
    func testSupportsForeignKeys() {
        #expect(DatabaseType.redshift.supportsForeignKeys == true)
    }

    @Test("Redshift does not support schema editing")
    func testSupportsSchemaEditing() {
        #expect(DatabaseType.redshift.supportsSchemaEditing == false)
    }

    @Test("Redshift raw value is Redshift")
    func testRawValue() {
        #expect(DatabaseType.redshift.rawValue == "Redshift")
    }

    @Test("Redshift identifier is its raw value")
    func testIdentifiable() {
        #expect(DatabaseType.redshift.id == "Redshift")
    }

    // MARK: - Identifier Quoting

    @Test("Redshift quotes identifier with double quotes")
    func testQuoteIdentifier() {
        let quoted = DatabaseType.redshift.quoteIdentifier("my_table")
        #expect(quoted == "\"my_table\"")
    }

    @Test("Redshift escapes embedded double quotes in identifiers")
    func testQuoteIdentifierEscaping() {
        let quoted = DatabaseType.redshift.quoteIdentifier("my\"table")
        #expect(quoted == "\"my\"\"table\"")
    }

    // MARK: - Driver Factory

    @Test("DatabaseDriverFactory creates RedshiftDriver for .redshift")
    func testDriverFactory() {
        let connection = TestFixtures.makeConnection(type: .redshift)
        let driver = DatabaseDriverFactory.createDriver(for: connection)
        #expect(driver is RedshiftDriver)
    }

    // MARK: - Connection URL Formatter

    @Test("ConnectionURLFormatter formats .redshift as redshift scheme")
    func testURLFormatterScheme() {
        let connection = DatabaseConnection(
            name: "Test Redshift",
            host: "cluster.example.com",
            port: 5_439,
            database: "analytics",
            username: "admin",
            type: .redshift
        )
        let url = ConnectionURLFormatter.format(connection, password: "secret", sshPassword: nil)
        #expect(url.hasPrefix("redshift://"))
        #expect(url.contains("cluster.example.com"))
        #expect(url.contains("analytics"))
    }

    @Test("ConnectionURLFormatter omits default port for Redshift")
    func testURLFormatterOmitsDefaultPort() {
        let connection = DatabaseConnection(
            name: "Test",
            host: "host",
            port: 5_439,
            database: "db",
            username: "user",
            type: .redshift
        )
        let url = ConnectionURLFormatter.format(connection, password: "pass", sshPassword: nil)
        #expect(!url.contains(":5439"))
    }

    @Test("ConnectionURLFormatter includes non-default port for Redshift")
    func testURLFormatterIncludesNonDefaultPort() {
        let connection = DatabaseConnection(
            name: "Test",
            host: "host",
            port: 5440,
            database: "db",
            username: "user",
            type: .redshift
        )
        let url = ConnectionURLFormatter.format(connection, password: "pass", sshPassword: nil)
        #expect(url.contains(":5440"))
    }

    // MARK: - CaseIterable

    @Test("DatabaseType.allCases includes redshift")
    func testAllCasesIncludesRedshift() {
        #expect(DatabaseType.allCases.contains(.redshift))
    }

    // MARK: - Codable Round-Trip

    @Test("Redshift DatabaseType encodes and decodes")
    func testCodableRoundTrip() throws {
        let original = DatabaseType.redshift
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DatabaseType.self, from: data)
        #expect(decoded == .redshift)
    }

    @Test("Redshift DatabaseConnection encodes and decodes")
    func testConnectionCodableRoundTrip() throws {
        let original = DatabaseConnection(
            name: "My Redshift",
            host: "cluster.example.com",
            port: 5_439,
            database: "analytics",
            username: "admin",
            type: .redshift
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DatabaseConnection.self, from: data)
        #expect(decoded.type == .redshift)
        #expect(decoded.name == "My Redshift")
        #expect(decoded.host == "cluster.example.com")
        #expect(decoded.port == 5_439)
        #expect(decoded.database == "analytics")
    }
}
