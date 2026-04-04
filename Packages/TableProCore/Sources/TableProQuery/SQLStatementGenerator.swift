import Foundation
import TableProPluginKit

public struct SQLStatementGenerator: Sendable {
    private let dialect: SQLDialectDescriptor

    public init(dialect: SQLDialectDescriptor) {
        self.dialect = dialect
    }

    public func generateInsert(table: String, columns: [String], values: [String?]) -> String {
        let quotedTable = quoteIdentifier(table)
        let quotedColumns = columns.map { quoteIdentifier($0) }.joined(separator: ", ")
        let formattedValues = values.map { formatValue($0) }.joined(separator: ", ")
        return "INSERT INTO \(quotedTable) (\(quotedColumns)) VALUES (\(formattedValues))"
    }

    public func generateUpdate(
        table: String,
        changes: [String: String?],
        where whereConditions: [String: String]
    ) -> String {
        let quotedTable = quoteIdentifier(table)

        let setClauses = changes.map { key, value in
            "\(quoteIdentifier(key)) = \(formatValue(value))"
        }.joined(separator: ", ")

        let whereClauses = whereConditions.map { key, value in
            "\(quoteIdentifier(key)) = \(formatWhereValue(value))"
        }.joined(separator: " AND ")

        return "UPDATE \(quotedTable) SET \(setClauses) WHERE \(whereClauses)"
    }

    public func generateDelete(table: String, where whereConditions: [String: String]) -> String {
        let quotedTable = quoteIdentifier(table)

        let whereClauses = whereConditions.map { key, value in
            "\(quoteIdentifier(key)) = \(formatWhereValue(value))"
        }.joined(separator: " AND ")

        return "DELETE FROM \(quotedTable) WHERE \(whereClauses)"
    }

    private func quoteIdentifier(_ name: String) -> String {
        let q = dialect.identifierQuote
        let escaped = name.replacingOccurrences(of: q, with: "\(q)\(q)")
        return "\(q)\(escaped)\(q)"
    }

    private func formatValue(_ value: String?) -> String {
        guard let value else { return "NULL" }
        if Int64(value) != nil || Double(value) != nil {
            return value
        }
        let escaped = value
            .replacingOccurrences(of: "'", with: "''")
            .replacingOccurrences(of: "\0", with: "")
        return "'\(escaped)'"
    }

    private func formatWhereValue(_ value: String) -> String {
        formatValue(value)
    }
}
