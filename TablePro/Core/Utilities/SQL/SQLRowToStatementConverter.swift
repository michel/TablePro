//
//  SQLRowToStatementConverter.swift
//  TablePro

import Foundation

struct SQLRowToStatementConverter {
    let tableName: String
    let columns: [String]
    let primaryKeyColumn: String?
    let databaseType: DatabaseType

    private static let maxRows = 50_000

    func generateInserts(rows: [[String?]]) -> String {
        let capped = rows.prefix(Self.maxRows)
        let quotedTable = quoteColumn(tableName)
        let quotedColumns = columns.map { quoteColumn($0) }.joined(separator: ", ")

        return capped.map { row in
            let values = row.map { formatValue($0) }.joined(separator: ", ")
            return "INSERT INTO \(quotedTable) (\(quotedColumns)) VALUES (\(values));"
        }.joined(separator: "\n")
    }

    func generateUpdates(rows: [[String?]]) -> String {
        let capped = rows.prefix(Self.maxRows)

        return capped.map { row in
            buildUpdateStatement(row: row)
        }.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func buildUpdateStatement(row: [String?]) -> String {
        let quotedTable = quoteColumn(tableName)

        let setClause: String
        let whereClause: String

        if let pkColumn = primaryKeyColumn {
            let pkIndex = columns.firstIndex(of: pkColumn)
            let pkValue = pkIndex.map { row.indices.contains($0) ? row[$0] : nil } ?? nil

            let setClauses = columns.enumerated().compactMap { index, col -> String? in
                guard col != pkColumn else { return nil }
                let value = row.indices.contains(index) ? row[index] : nil
                return "\(quoteColumn(col)) = \(formatValue(value))"
            }
            setClause = setClauses.joined(separator: ", ")
            if pkValue == nil {
                whereClause = "\(quoteColumn(pkColumn)) IS NULL"
            } else {
                whereClause = "\(quoteColumn(pkColumn)) = \(formatValue(pkValue))"
            }
        } else {
            let allClauses = columns.enumerated().map { index, col -> String in
                let value = row.indices.contains(index) ? row[index] : nil
                return "\(quoteColumn(col)) = \(formatValue(value))"
            }
            setClause = allClauses.joined(separator: ", ")

            let whereParts = columns.enumerated().map { index, col -> String in
                let value = row.indices.contains(index) ? row[index] : nil
                if value == nil {
                    return "\(quoteColumn(col)) IS NULL"
                }
                return "\(quoteColumn(col)) = \(formatValue(value))"
            }
            whereClause = whereParts.joined(separator: " AND ")
        }

        switch databaseType {
        case .clickhouse:
            return "ALTER TABLE \(quotedTable) UPDATE \(setClause) WHERE \(whereClause);"
        default:
            return "UPDATE \(quotedTable) SET \(setClause) WHERE \(whereClause);"
        }
    }

    private func formatValue(_ value: String?) -> String {
        guard let value else {
            return "NULL"
        }
        return "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func quoteColumn(_ name: String) -> String {
        databaseType.quoteIdentifier(name)
    }
}
