//
//  MSSQLDriverTests.swift
//  TableProTests
//
//  Tests for MSSQL driver plugin — parts that don't require a live connection.
//

import Foundation
@testable import TablePro
import TableProPluginKit
import Testing

@MainActor
@Suite("MSSQL Driver")
struct MSSQLDriverTests {
    // MARK: - Helpers

    private func makeConnection(mssqlSchema: String? = nil) -> DatabaseConnection {
        var conn = TestFixtures.makeConnection(type: .mssql)
        conn.mssqlSchema = mssqlSchema
        return conn
    }

    private func makeAdapter(mssqlSchema: String? = nil) -> PluginDriverAdapter {
        let conn = makeConnection(mssqlSchema: mssqlSchema)
        let config = DriverConnectionConfig(
            host: conn.host,
            port: conn.port,
            username: conn.username,
            password: "",
            database: conn.database,
            additionalFields: [
                "mssqlSchema": mssqlSchema ?? "dbo"
            ]
        )
        guard let plugin = PluginManager.shared.driverPlugins["SQL Server"] else {
            fatalError("SQL Server plugin not loaded")
        }
        let pluginDriver = plugin.createDriver(config: config)
        return PluginDriverAdapter(connection: conn, pluginDriver: pluginDriver)
    }

    // MARK: - Initialization Tests

    @Test("Init sets currentSchema to dbo when mssqlSchema is nil")
    func initDefaultSchemaNil() {
        let adapter = makeAdapter(mssqlSchema: nil)
        #expect(adapter.currentSchema == "dbo")
    }

    @Test("Init sets currentSchema to dbo when mssqlSchema is empty string")
    func initDefaultSchemaEmpty() {
        let adapter = makeAdapter(mssqlSchema: "")
        #expect(adapter.currentSchema == "dbo")
    }

    @Test("Init uses mssqlSchema when provided and non-empty")
    func initCustomSchema() {
        let adapter = makeAdapter(mssqlSchema: "sales")
        #expect(adapter.currentSchema == "sales")
    }

    // MARK: - escapedSchema Tests

    @Test("escapedSchema returns schema unchanged when no single quotes")
    func escapedSchemaNoQuotes() {
        let adapter = makeAdapter(mssqlSchema: "sales")
        #expect(adapter.escapedSchema == "sales")
    }

    @Test("escapedSchema doubles single quote in schema name")
    func escapedSchemaDoublesSingleQuote() {
        let adapter = makeAdapter(mssqlSchema: "O'Brien")
        #expect(adapter.escapedSchema == "O''Brien")
    }

    @Test("escapedSchema doubles multiple single quotes")
    func escapedSchemaMultipleQuotes() {
        let adapter = makeAdapter(mssqlSchema: "O'Bri'en")
        #expect(adapter.escapedSchema == "O''Bri''en")
    }

    // MARK: - switchSchema Tests

    @Test("switchSchema updates currentSchema")
    func switchSchemaUpdatesCurrentSchema() async throws {
        let adapter = makeAdapter()
        try await adapter.switchSchema(to: "hr")
        #expect(adapter.currentSchema == "hr")
    }

    @Test("switchSchema updates escapedSchema accordingly")
    func switchSchemaUpdatesEscapedSchema() async throws {
        let adapter = makeAdapter()
        try await adapter.switchSchema(to: "O'Connor")
        #expect(adapter.escapedSchema == "O''Connor")
    }

    // MARK: - Status Tests

    @Test("Status starts as disconnected")
    func statusStartsDisconnected() {
        let adapter = makeAdapter()
        if case .disconnected = adapter.status {
            #expect(true)
        } else {
            Issue.record("Expected .disconnected status, got \(adapter.status)")
        }
    }

    // MARK: - Execute Tests

    @Test("Execute throws when not connected")
    func executeThrowsWhenNotConnected() async {
        let adapter = makeAdapter()
        await #expect(throws: (any Error).self) {
            _ = try await adapter.execute(query: "SELECT 1")
        }
    }
}
