//
//  ExportServiceStateTests.swift
//  TableProTests
//
//  Tests for ExportServiceState wrapper that delegates to ExportService.
//

import Foundation
@testable import TablePro
import Testing

@MainActor
@Suite("ExportServiceState")
struct ExportServiceStateTests {
    // MARK: - Default Values (No Service)

    @Test("Default values when no service is set")
    func defaultValuesNoService() {
        let state = ExportServiceState()

        #expect(state.service == nil)
        #expect(state.currentTable == "")
        #expect(state.currentTableIndex == 0)
        #expect(state.totalTables == 0)
        #expect(state.processedRows == 0)
        #expect(state.totalRows == 0)
        #expect(state.statusMessage == "")
    }

    // MARK: - Service Delegation

    @Test("Properties delegate to service state after setting service")
    func propertiesDelegateToService() {
        let state = ExportServiceState()
        let connection = DatabaseConnection(name: "Test", type: .sqlite)
        let driver = SQLiteDriver(connection: connection)
        let service = ExportService(driver: driver, databaseType: .sqlite)

        service.state = ExportState(
            currentTable: "users",
            currentTableIndex: 2,
            totalTables: 5,
            processedRows: 100,
            totalRows: 500,
            statusMessage: "Exporting..."
        )

        state.setService(service)

        #expect(state.currentTable == "users")
        #expect(state.currentTableIndex == 2)
        #expect(state.totalTables == 5)
        #expect(state.processedRows == 100)
        #expect(state.totalRows == 500)
        #expect(state.statusMessage == "Exporting...")
    }

    // MARK: - State Mutation

    @Test("Wrapper reflects changes after mutating service state")
    func wrapperReflectsServiceStateMutation() {
        let state = ExportServiceState()
        let connection = DatabaseConnection(name: "Test", type: .sqlite)
        let driver = SQLiteDriver(connection: connection)
        let service = ExportService(driver: driver, databaseType: .sqlite)

        state.setService(service)

        #expect(state.currentTable == "")
        #expect(state.processedRows == 0)

        service.state.currentTable = "orders"
        service.state.processedRows = 42
        service.state.totalRows = 200
        service.state.statusMessage = "Processing..."

        #expect(state.currentTable == "orders")
        #expect(state.processedRows == 42)
        #expect(state.totalRows == 200)
        #expect(state.statusMessage == "Processing...")
    }

    // MARK: - Service Replacement

    @Test("Setting a new service replaces the old one")
    func settingNewServiceReplacesOld() {
        let state = ExportServiceState()
        let connection = DatabaseConnection(name: "Test", type: .sqlite)
        let driver = SQLiteDriver(connection: connection)

        let service1 = ExportService(driver: driver, databaseType: .sqlite)
        service1.state.currentTable = "old_table"
        service1.state.processedRows = 999

        state.setService(service1)
        #expect(state.currentTable == "old_table")
        #expect(state.processedRows == 999)

        let service2 = ExportService(driver: driver, databaseType: .sqlite)
        service2.state.currentTable = "new_table"
        service2.state.processedRows = 1

        state.setService(service2)
        #expect(state.currentTable == "new_table")
        #expect(state.processedRows == 1)
        #expect(state.service === service2)
    }
}
