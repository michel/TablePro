//
//  MainContentCoordinator+SidebarSave.swift
//  TablePro
//
//  Sidebar save logic extracted from MainContentView.
//

import Foundation

extension MainContentCoordinator {
    // MARK: - Sidebar Save

    func saveSidebarEdits(
        selectedRowIndices: Set<Int>,
        editState: MultiRowEditState
    ) async throws {
        guard let tab = tabManager.selectedTab,
              !selectedRowIndices.isEmpty,
              let tableName = tab.tableName
        else {
            return
        }

        let editedFields = editState.getEditedFields()
        guard !editedFields.isEmpty else { return }

        var statements: [String] = []
        for rowIndex in selectedRowIndices.sorted() {
            guard rowIndex < tab.resultRows.count else { continue }
            let row = tab.resultRows[rowIndex]
            if let sql = generateSidebarUpdateSQL(
                tableName: tableName,
                originalRow: row.values,
                editedFields: editedFields,
                columns: tab.resultColumns,
                primaryKeyColumn: changeManager.primaryKeyColumn
            ) {
                statements.append(sql)
            }
        }

        guard !statements.isEmpty else { return }
        try await executeSidebarChanges(statements: statements)
        runQuery()
    }

    private func generateSidebarUpdateSQL(
        tableName: String,
        originalRow: [String?],
        editedFields: [(columnIndex: Int, columnName: String, newValue: String?)],
        columns: [String],
        primaryKeyColumn: String?
    ) -> String? {
        guard let pkColumn = primaryKeyColumn,
              let pkIndex = columns.firstIndex(of: pkColumn),
              pkIndex < originalRow.count,
              let pkValue = originalRow[pkIndex]
        else {
            return nil
        }

        let dbType = connection.type

        let setClauses = editedFields.map { field -> String in
            let quotedColumn = dbType.quoteIdentifier(field.columnName)
            let value: String
            if field.newValue == "__DEFAULT__" {
                value = "DEFAULT"
            } else if let newValue = field.newValue {
                if isSidebarSQLFunction(newValue) {
                    value = newValue.trimmingCharacters(in: .whitespaces)
                } else {
                    value = "'\(SQLEscaping.escapeStringLiteral(newValue))'"
                }
            } else {
                value = "NULL"
            }
            return "\(quotedColumn) = \(value)"
        }.joined(separator: ", ")

        let quotedPK = dbType.quoteIdentifier(pkColumn)
        let quotedPKValue = "'\(SQLEscaping.escapeStringLiteral(pkValue))'"
        let whereClause = "\(quotedPK) = \(quotedPKValue)"
        let limitClause = (dbType == .mysql || dbType == .mariadb) ? " LIMIT 1" : ""

        return "UPDATE \(dbType.quoteIdentifier(tableName)) SET \(setClauses) WHERE \(whereClause)\(limitClause)"
    }

    private func isSidebarSQLFunction(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces).uppercased()
        let sqlFunctions = [
            "NOW()", "CURRENT_TIMESTAMP()", "CURRENT_TIMESTAMP",
            "CURDATE()", "CURTIME()", "UTC_TIMESTAMP()", "UTC_DATE()", "UTC_TIME()",
            "LOCALTIME()", "LOCALTIME", "LOCALTIMESTAMP()", "LOCALTIMESTAMP",
            "SYSDATE()", "UNIX_TIMESTAMP()", "CURRENT_DATE()", "CURRENT_DATE",
            "CURRENT_TIME()", "CURRENT_TIME",
        ]
        return sqlFunctions.contains(trimmed)
    }
}
