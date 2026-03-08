//
//  SaveCompletionTests.swift
//  TableProTests
//
//  Tests for the save completion paths in MainContentCoordinator.saveChanges(),
//  verifying that every exit path produces the correct outcome (error message
//  or silent success) and does not leave the coordinator in an inconsistent state.
//

import Foundation
@testable import TablePro
import Testing

@MainActor @Suite("Save Completion")
struct SaveCompletionTests {
    // MARK: - Helpers

    private func makeCoordinator(
        isReadOnly: Bool = false,
        type: DatabaseType = .mysql
    ) -> (MainContentCoordinator, QueryTabManager, DataChangeManager) {
        var conn = TestFixtures.makeConnection(type: type)
        conn.isReadOnly = isReadOnly
        let state = SessionStateFactory.create(connection: conn, payload: nil)
        return (state.coordinator, state.tabManager, state.changeManager)
    }

    // MARK: - No Changes

    @Test("saveChanges with no changes returns immediately without error")
    func noChanges_returnsWithoutError() {
        let (coordinator, tabManager, _) = makeCoordinator()
        tabManager.addTab(databaseName: "testdb")

        var truncates: Set<String> = []
        var deletes: Set<String> = []
        var options: [String: TableOperationOptions] = [:]

        coordinator.saveChanges(
            pendingTruncates: &truncates,
            pendingDeletes: &deletes,
            tableOperationOptions: &options
        )

        #expect(tabManager.tabs.first?.errorMessage == nil)
    }

    // MARK: - Read-Only Connection

    @Test("saveChanges on read-only connection sets error message")
    func readOnly_setsErrorMessage() {
        let (coordinator, tabManager, changeManager) = makeCoordinator(isReadOnly: true)
        tabManager.addTab(databaseName: "testdb")

        changeManager.hasChanges = true

        var truncates: Set<String> = []
        var deletes: Set<String> = []
        var options: [String: TableOperationOptions] = [:]

        coordinator.saveChanges(
            pendingTruncates: &truncates,
            pendingDeletes: &deletes,
            tableOperationOptions: &options
        )

        let errorMessage = tabManager.tabs.first?.errorMessage
        #expect(errorMessage != nil)
        #expect(errorMessage?.contains("read-only") == true)
    }

    @Test("saveChanges on read-only connection does not clear changes")
    func readOnly_doesNotClearChanges() {
        let (coordinator, _, changeManager) = makeCoordinator(isReadOnly: true)

        changeManager.hasChanges = true

        var truncates: Set<String> = []
        var deletes: Set<String> = []
        var options: [String: TableOperationOptions] = [:]

        coordinator.saveChanges(
            pendingTruncates: &truncates,
            pendingDeletes: &deletes,
            tableOperationOptions: &options
        )

        #expect(changeManager.hasChanges == true)
    }

    // MARK: - Empty Generated Statements

    @Test("saveChanges with hasChanges true but no generated SQL sets error")
    func hasChangesButNoSQL_setsError() {
        let (coordinator, tabManager, changeManager) = makeCoordinator()
        tabManager.addTab(databaseName: "testdb")

        changeManager.hasChanges = true

        var truncates: Set<String> = []
        var deletes: Set<String> = []
        var options: [String: TableOperationOptions] = [:]

        coordinator.saveChanges(
            pendingTruncates: &truncates,
            pendingDeletes: &deletes,
            tableOperationOptions: &options
        )

        let errorMessage = tabManager.tabs.first?.errorMessage
        #expect(errorMessage != nil)
    }

    // MARK: - Pending Table Operations

    @Test("saveChanges with pending truncates but read-only sets error")
    func pendingTruncatesReadOnly_setsError() {
        let (coordinator, tabManager, _) = makeCoordinator(isReadOnly: true)
        tabManager.addTab(databaseName: "testdb")

        var truncates: Set<String> = ["users"]
        var deletes: Set<String> = []
        var options: [String: TableOperationOptions] = [:]

        coordinator.saveChanges(
            pendingTruncates: &truncates,
            pendingDeletes: &deletes,
            tableOperationOptions: &options
        )

        let errorMessage = tabManager.tabs.first?.errorMessage
        #expect(errorMessage != nil)
        #expect(errorMessage?.contains("read-only") == true)
        #expect(truncates.contains("users"))
    }

    @Test("saveChanges with no tab selected and read-only does not crash")
    func noTabSelected_readOnly_doesNotCrash() {
        let (coordinator, _, changeManager) = makeCoordinator(isReadOnly: true)
        changeManager.hasChanges = true

        var truncates: Set<String> = []
        var deletes: Set<String> = []
        var options: [String: TableOperationOptions] = [:]

        coordinator.saveChanges(
            pendingTruncates: &truncates,
            pendingDeletes: &deletes,
            tableOperationOptions: &options
        )

        #expect(changeManager.hasChanges == true)
    }

    @Test("saveChanges with no changes and no pending ops does nothing")
    func noChangesNoPendingOps_noop() {
        let (coordinator, tabManager, _) = makeCoordinator()
        tabManager.addTab(databaseName: "testdb")

        var truncates: Set<String> = []
        var deletes: Set<String> = []
        var options: [String: TableOperationOptions] = [:]

        coordinator.saveChanges(
            pendingTruncates: &truncates,
            pendingDeletes: &deletes,
            tableOperationOptions: &options
        )

        #expect(tabManager.tabs.first?.errorMessage == nil)
        #expect(truncates.isEmpty)
        #expect(deletes.isEmpty)
    }
}
