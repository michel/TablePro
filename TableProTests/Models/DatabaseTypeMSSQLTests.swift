//
//  DatabaseTypeMSSQLTests.swift
//  TableProTests
//
//  Tests for DatabaseType(rawValue: "SQL Server") properties and methods.
//

import Foundation
@testable import TablePro
import Testing

@Suite("DatabaseType MSSQL")
struct DatabaseTypeMSSQLTests {
    // MARK: - Basic Properties

    @Test("defaultPort is 1433")
    func defaultPort() {
        #expect(DatabaseType(rawValue: "SQL Server").defaultPort == 1_433)
    }

    @Test("rawValue is SQL Server")
    func rawValue() {
        #expect(DatabaseType(rawValue: "SQL Server").rawValue == "SQL Server")
    }

    @Test("requiresAuthentication is true")
    func requiresAuthentication() {
        #expect(DatabaseType(rawValue: "SQL Server").requiresAuthentication == true)
    }

    @Test("supportsForeignKeys is true")
    func supportsForeignKeys() {
        #expect(DatabaseType(rawValue: "SQL Server").supportsForeignKeys == true)
    }

    @Test("supportsSchemaEditing is true")
    func supportsSchemaEditing() {
        #expect(DatabaseType(rawValue: "SQL Server").supportsSchemaEditing == true)
    }

    @Test("iconName is mssql-icon")
    func iconName() {
        #expect(DatabaseType(rawValue: "SQL Server").iconName == "mssql-icon")
    }

    // MARK: - allKnownTypes Tests

    @Test("allKnownTypes contains mssql")
    func allKnownTypesContainsMSSql() {
        #expect(DatabaseType.allKnownTypes.contains(DatabaseType(rawValue: "SQL Server")))
    }

    @Test("allCases shim contains mssql")
    func allCasesContainsMSSql() {
        #expect(DatabaseType.allCases.contains(DatabaseType(rawValue: "SQL Server")))
    }
}
