//
//  ImportServiceStateTests.swift
//  TableProTests
//
//  Tests for ImportServiceState wrapper that delegates to ImportService.
//

import Foundation
@testable import TablePro
import Testing

@MainActor
@Suite("ImportServiceState")
struct ImportServiceStateTests {
    // MARK: - Default Values (No Service)

    @Test("Default values when no service is set")
    func defaultValuesNoService() {
        let state = ImportServiceState()

        #expect(state.service == nil)
        #expect(state.isImporting == false)
        #expect(state.currentStatement == "")
        #expect(state.currentStatementIndex == 0)
        #expect(state.totalStatements == 0)
        #expect(state.statusMessage == "")
    }

    // MARK: - Service Delegation

    @Test("Properties delegate to service state after setting service")
    func propertiesDelegateToService() {
        let state = ImportServiceState()
        let connection = DatabaseConnection(name: "Test", type: .sqlite)
        let service = ImportService(connection: connection)

        service.state = ImportState(
            isImporting: true,
            currentStatement: "CREATE TABLE users",
            currentStatementIndex: 3,
            totalStatements: 10,
            statusMessage: "Importing..."
        )

        state.setService(service)

        #expect(state.isImporting == true)
        #expect(state.currentStatement == "CREATE TABLE users")
        #expect(state.currentStatementIndex == 3)
        #expect(state.totalStatements == 10)
        #expect(state.statusMessage == "Importing...")
    }

    // MARK: - State Mutation

    @Test("Wrapper reflects changes after mutating service state")
    func wrapperReflectsServiceStateMutation() {
        let state = ImportServiceState()
        let connection = DatabaseConnection(name: "Test", type: .sqlite)
        let service = ImportService(connection: connection)

        state.setService(service)

        #expect(state.isImporting == false)
        #expect(state.currentStatement == "")

        service.state.isImporting = true
        service.state.currentStatement = "INSERT INTO orders"
        service.state.currentStatementIndex = 7
        service.state.totalStatements = 20
        service.state.statusMessage = "Processing statements..."

        #expect(state.isImporting == true)
        #expect(state.currentStatement == "INSERT INTO orders")
        #expect(state.currentStatementIndex == 7)
        #expect(state.totalStatements == 20)
        #expect(state.statusMessage == "Processing statements...")
    }
}
