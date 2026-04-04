//
//  SQLBuilder.swift
//  TableProMobile
//

import Foundation
import TableProModels

enum SQLBuilder {
    static func quoteIdentifier(_ name: String, for type: DatabaseType) -> String {
        switch type {
        case .mysql, .mariadb:
            return "`\(name.replacingOccurrences(of: "`", with: "``"))`"
        case .postgresql, .redshift:
            return "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
        default:
            return "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
    }

    static func escapeString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "''")
    }

    static func buildSelect(table: String, type: DatabaseType, limit: Int, offset: Int) -> String {
        let quoted = quoteIdentifier(table, for: type)
        return "SELECT * FROM \(quoted) LIMIT \(limit) OFFSET \(offset)"
    }

    static func buildDelete(
        table: String,
        type: DatabaseType,
        primaryKeys: [(column: String, value: String)]
    ) -> String {
        let quotedTable = quoteIdentifier(table, for: type)
        let where_ = primaryKeys.map {
            "\(quoteIdentifier($0.column, for: type)) = '\(escapeString($0.value))'"
        }.joined(separator: " AND ")
        return "DELETE FROM \(quotedTable) WHERE \(where_)"
    }

    static func buildUpdate(
        table: String,
        type: DatabaseType,
        changes: [(column: String, value: String?)],
        primaryKeys: [(column: String, value: String)]
    ) -> String {
        let quotedTable = quoteIdentifier(table, for: type)
        let set_ = changes.map { col, val in
            let qcol = quoteIdentifier(col, for: type)
            if let val { return "\(qcol) = '\(escapeString(val))'" }
            return "\(qcol) = NULL"
        }.joined(separator: ", ")
        let where_ = primaryKeys.map {
            "\(quoteIdentifier($0.column, for: type)) = '\(escapeString($0.value))'"
        }.joined(separator: " AND ")
        return "UPDATE \(quotedTable) SET \(set_) WHERE \(where_)"
    }

    static func buildInsert(
        table: String,
        type: DatabaseType,
        columns: [String],
        values: [String?]
    ) -> String {
        let quotedTable = quoteIdentifier(table, for: type)
        let cols = columns.map { quoteIdentifier($0, for: type) }.joined(separator: ", ")
        let vals = values.map { val in
            if let val { return "'\(escapeString(val))'" }
            return "NULL"
        }.joined(separator: ", ")
        return "INSERT INTO \(quotedTable) (\(cols)) VALUES (\(vals))"
    }
}
