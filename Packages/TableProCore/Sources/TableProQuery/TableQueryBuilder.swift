import Foundation
import TableProModels
import TableProPluginKit

public struct TableQueryBuilder: Sendable {
    private let dialect: SQLDialectDescriptor?
    private let pluginDriver: (any PluginDatabaseDriver)?

    public init(
        dialect: SQLDialectDescriptor? = nil,
        pluginDriver: (any PluginDatabaseDriver)? = nil
    ) {
        self.dialect = dialect
        self.pluginDriver = pluginDriver
    }

    public func buildBrowseQuery(
        tableName: String,
        sortState: SortState = SortState(),
        limit: Int,
        offset: Int
    ) -> String {
        if let driver = pluginDriver {
            let sortColumns = sortState.columns.enumerated().map { (index, col) in
                (columnIndex: index, ascending: col.ascending)
            }
            if let query = driver.buildBrowseQuery(
                table: tableName,
                sortColumns: sortColumns,
                columns: [],
                limit: limit,
                offset: offset
            ) {
                return query
            }
        }

        let quoted = quoteIdentifier(tableName)
        var sql = "SELECT * FROM \(quoted)"

        if sortState.isSorting {
            sql += " " + buildOrderByClause(sortState: sortState)
        }

        sql += " " + buildPaginationClause(limit: limit, offset: offset)
        return sql
    }

    public func buildFilteredQuery(
        tableName: String,
        filters: [TableFilter],
        logicMode: FilterLogicMode = .and,
        sortState: SortState = SortState(),
        limit: Int,
        offset: Int
    ) -> String {
        if let driver = pluginDriver {
            let filterTuples = filters.filter { $0.isEnabled && $0.isValid }.map { f in
                (column: f.columnName, op: f.filterOperator.sqlSymbol, value: f.value)
            }
            let sortColumns = sortState.columns.enumerated().map { (index, col) in
                (columnIndex: index, ascending: col.ascending)
            }
            if let query = driver.buildFilteredQuery(
                table: tableName,
                filters: filterTuples,
                logicMode: logicMode.rawValue,
                sortColumns: sortColumns,
                columns: [],
                limit: limit,
                offset: offset
            ) {
                return query
            }
        }

        let quoted = quoteIdentifier(tableName)
        var sql = "SELECT * FROM \(quoted)"

        if let dialect {
            let generator = FilterSQLGenerator(dialect: dialect)
            let whereClause = generator.generateWhereClause(from: filters, logicMode: logicMode)
            if !whereClause.isEmpty {
                sql += " \(whereClause)"
            }
        }

        if sortState.isSorting {
            sql += " " + buildOrderByClause(sortState: sortState)
        }

        sql += " " + buildPaginationClause(limit: limit, offset: offset)
        return sql
    }

    private func buildOrderByClause(sortState: SortState) -> String {
        let parts = sortState.columns.map { col in
            "\(quoteIdentifier(col.name)) \(col.ascending ? "ASC" : "DESC")"
        }
        return "ORDER BY \(parts.joined(separator: ", "))"
    }

    private func buildPaginationClause(limit: Int, offset: Int) -> String {
        let style = dialect?.paginationStyle ?? .limit
        switch style {
        case .limit:
            return "LIMIT \(limit) OFFSET \(offset)"
        case .offsetFetch:
            let orderBy = dialect?.offsetFetchOrderBy ?? "ORDER BY (SELECT NULL)"
            return "\(orderBy) OFFSET \(offset) ROWS FETCH NEXT \(limit) ROWS ONLY"
        }
    }

    private func quoteIdentifier(_ name: String) -> String {
        let q = dialect?.identifierQuote ?? "\""
        let escaped = name.replacingOccurrences(of: q, with: "\(q)\(q)")
        return "\(q)\(escaped)\(q)"
    }
}
