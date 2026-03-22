//
//  ColumnExclusionPolicy.swift
//  TablePro
//
//  Determines which columns should be excluded from table browse queries
//  to avoid fetching large BLOB/TEXT data unnecessarily.
//

import Foundation

/// Describes a column excluded from SELECT with a placeholder expression
struct ColumnExclusion {
    let columnName: String
    let placeholderExpression: String
}

/// Determines which columns to exclude from table browse queries
enum ColumnExclusionPolicy {
    static func exclusions(
        columns: [String],
        columnTypes: [ColumnType],
        databaseType: DatabaseType,
        quoteIdentifier: (String) -> String
    ) -> [ColumnExclusion] {
        // NoSQL databases use custom query builders, not SQL SELECT
        if databaseType == .mongodb || databaseType == .redis { return [] }

        var result: [ColumnExclusion] = []
        let count = min(columns.count, columnTypes.count)

        for i in 0..<count {
            let col = columns[i]
            let colType = columnTypes[i]
            let quoted = quoteIdentifier(col)

            // Only exclude very large text types (MEDIUMTEXT, LONGTEXT, CLOB).
            // Plain TEXT/TINYTEXT are small enough to fetch in full.
            // BLOB columns are NOT excluded because no lazy-load fetch path exists
            // for editing, export, or change tracking — placeholder values would corrupt data.
            if colType.isVeryLongText {
                let substringExpr = substringExpression(for: databaseType, column: quoted, length: 256)
                result.append(ColumnExclusion(columnName: col, placeholderExpression: substringExpr))
            }
        }

        return result
    }

    private static func substringExpression(for dbType: DatabaseType, column: String, length: Int) -> String {
        switch dbType {
        case .sqlite:
            return "SUBSTR(\(column), 1, \(length))"
        default:
            return "SUBSTRING(\(column), 1, \(length))"
        }
    }
}
