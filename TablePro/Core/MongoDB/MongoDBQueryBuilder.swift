//
//  MongoDBQueryBuilder.swift
//  TablePro
//
//  Builds MongoDB Shell syntax query strings for collection browsing.
//  Parallel to TableQueryBuilder for SQL databases.
//

import Foundation

struct MongoDBQueryBuilder {
    // MARK: - Base Query

    /// Build: db.collection.find({}).sort({}).skip(offset).limit(limit)
    func buildBaseQuery(
        collection: String,
        sortState: SortState? = nil,
        columns: [String] = [],
        limit: Int = 200,
        offset: Int = 0
    ) -> String {
        var query = "\(Self.mongoCollectionAccessor(collection)).find({})"

        if let sort = buildSortDocument(sortState: sortState, columns: columns) {
            query += ".sort(\(sort))"
        }

        if offset > 0 {
            query += ".skip(\(offset))"
        }

        query += ".limit(\(limit))"
        return query
    }

    /// Build: db.collection.find({filter}).sort({}).skip(offset).limit(limit)
    func buildFilteredQuery(
        collection: String,
        filters: [TableFilter],
        logicMode: FilterLogicMode = .and,
        sortState: SortState? = nil,
        columns: [String] = [],
        limit: Int = 200,
        offset: Int = 0
    ) -> String {
        let filterDoc = buildFilterDocument(from: filters, logicMode: logicMode)
        var query = "\(Self.mongoCollectionAccessor(collection)).find(\(filterDoc))"

        if let sort = buildSortDocument(sortState: sortState, columns: columns) {
            query += ".sort(\(sort))"
        }

        if offset > 0 {
            query += ".skip(\(offset))"
        }

        query += ".limit(\(limit))"
        return query
    }

    /// Build quick search query: $or across all text-like fields
    func buildQuickSearchQuery(
        collection: String,
        searchText: String,
        columns: [String],
        sortState: SortState? = nil,
        limit: Int = 200,
        offset: Int = 0
    ) -> String {
        let escaped = escapeRegexChars(searchText)
        let conditions = columns.map { column in
            "\"\(Self.escapeJsonString(column))\": {\"$regex\": \"\(escaped)\", \"$options\": \"i\"}"
        }

        let filter: String
        if conditions.isEmpty {
            filter = "{}"
        } else {
            filter = "{\"$or\": [{\(conditions.joined(separator: "}, {"))}]}"
        }

        var query = "\(Self.mongoCollectionAccessor(collection)).find(\(filter))"

        if let sort = buildSortDocument(sortState: sortState, columns: columns) {
            query += ".sort(\(sort))"
        }

        if offset > 0 {
            query += ".skip(\(offset))"
        }

        query += ".limit(\(limit))"
        return query
    }

    /// Build a query combining filter rows AND quick search with $and
    func buildCombinedQuery(
        collection: String,
        filters: [TableFilter],
        logicMode: FilterLogicMode = .and,
        searchText: String,
        searchColumns: [String],
        sortState: SortState? = nil,
        columns: [String] = [],
        limit: Int = 200,
        offset: Int = 0
    ) -> String {
        let filterDoc = buildFilterDocument(from: filters, logicMode: logicMode)

        let escaped = escapeRegexChars(searchText)
        let searchConditions = searchColumns.map { column in
            "{\"" + Self.escapeJsonString(column) + "\": {\"$regex\": \"" + escaped + "\", \"$options\": \"i\"}}"
        }
        let searchDoc = searchConditions.isEmpty ? "{}" : "{\"$or\": [" + searchConditions.joined(separator: ", ") + "]}"

        let combinedFilter = "{\"$and\": [\(filterDoc), \(searchDoc)]}"

        var query = "\(Self.mongoCollectionAccessor(collection)).find(\(combinedFilter))"

        if let sort = buildSortDocument(sortState: sortState, columns: columns) {
            query += ".sort(\(sort))"
        }

        if offset > 0 {
            query += ".skip(\(offset))"
        }

        query += ".limit(\(limit))"
        return query
    }

    // MARK: - Count Query

    /// Build: db.collection.countDocuments({filter})
    func buildCountQuery(collection: String, filterJson: String = "{}") -> String {
        "\(Self.mongoCollectionAccessor(collection)).countDocuments(\(filterJson))"
    }

    // MARK: - Filter Document

    /// Convert TableFilter array to MongoDB filter document string
    func buildFilterDocument(from filters: [TableFilter], logicMode: FilterLogicMode = .and) -> String {
        let activeFilters = filters.filter { $0.isEnabled && !$0.columnName.isEmpty }
        guard !activeFilters.isEmpty else { return "{}" }

        let conditions = activeFilters.compactMap { filter -> String? in
            buildCondition(from: filter)
        }

        guard !conditions.isEmpty else { return "{}" }

        if conditions.count == 1 {
            return "{\(conditions[0])}"
        }

        let logicOp = logicMode == .and ? "$and" : "$or"
        let conditionDocs = conditions.map { "{\($0)}" }
        return "{\"\(logicOp)\": [\(conditionDocs.joined(separator: ", "))]}"
    }

    // MARK: - Private Helpers

    private static func mongoCollectionAccessor(_ name: String) -> String {
        guard let firstChar = name.first,
              !firstChar.isNumber,
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return "db[\"\(escapeJsonString(name))\"]"
        }
        return "db.\(name)"
    }

    private func buildCondition(from filter: TableFilter) -> String? {
        let field = Self.escapeJsonString(filter.columnName)
        let value = filter.value

        switch filter.filterOperator {
        case .equal:
            return "\"\(field)\": \(jsonValue(value))"
        case .notEqual:
            return "\"\(field)\": {\"$ne\": \(jsonValue(value))}"
        case .greaterThan:
            return "\"\(field)\": {\"$gt\": \(jsonValue(value))}"
        case .greaterOrEqual:
            return "\"\(field)\": {\"$gte\": \(jsonValue(value))}"
        case .lessThan:
            return "\"\(field)\": {\"$lt\": \(jsonValue(value))}"
        case .lessOrEqual:
            return "\"\(field)\": {\"$lte\": \(jsonValue(value))}"
        case .contains:
            return "\"\(field)\": {\"$regex\": \"\(escapeRegexChars(value))\", \"$options\": \"i\"}"
        case .notContains:
            return "\"\(field)\": {\"$not\": {\"$regex\": \"\(escapeRegexChars(value))\", \"$options\": \"i\"}}"
        case .startsWith:
            return "\"\(field)\": {\"$regex\": \"^\(escapeRegexChars(value))\", \"$options\": \"i\"}"
        case .endsWith:
            return "\"\(field)\": {\"$regex\": \"\(escapeRegexChars(value))$\", \"$options\": \"i\"}"
        case .isNull:
            return "\"\(field)\": null"
        case .isNotNull:
            return "\"\(field)\": {\"$ne\": null}"
        case .isEmpty:
            return "\"\(field)\": \"\""
        case .isNotEmpty:
            return "\"\(field)\": {\"$ne\": \"\"}"
        case .regex:
            return "\"\(field)\": {\"$regex\": \"\(value)\", \"$options\": \"i\"}"
        case .inList:
            let items = value.split(separator: ",")
                .map { jsonValue(String($0).trimmingCharacters(in: .whitespaces)) }
            return "\"\(field)\": {\"$in\": [\(items.joined(separator: ", "))]}"
        case .notInList:
            let items = value.split(separator: ",")
                .map { jsonValue(String($0).trimmingCharacters(in: .whitespaces)) }
            return "\"\(field)\": {\"$nin\": [\(items.joined(separator: ", "))]}"
        case .between:
            let parts = value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { return nil }
            return "\"\(field)\": {\"$gte\": \(jsonValue(parts[0])), \"$lte\": \(jsonValue(parts[1]))}"
        }
    }

    private func buildSortDocument(sortState: SortState?, columns: [String]) -> String? {
        guard let state = sortState, state.isSorting else { return nil }

        let parts = state.columns.compactMap { sortCol -> String? in
            guard sortCol.columnIndex >= 0, sortCol.columnIndex < columns.count else { return nil }
            let columnName = Self.escapeJsonString(columns[sortCol.columnIndex])
            let direction = sortCol.direction == .ascending ? 1 : -1
            return "\"\(columnName)\": \(direction)"
        }

        guard !parts.isEmpty else { return nil }
        return "{\(parts.joined(separator: ", "))}"
    }

    /// Auto-detect value type for JSON representation
    private func jsonValue(_ value: String) -> String {
        if value == "true" || value == "false" { return value }
        if value == "null" { return value }
        if Int64(value) != nil { return value }
        if Double(value) != nil, value.contains(".") { return value }
        return "\"\(Self.escapeJsonString(value))\""
    }

    static func escapeJsonString(_ value: String) -> String {
        var result = ""
        result.reserveCapacity((value as NSString).length)
        for char in value {
            switch char {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if let ascii = char.asciiValue, ascii < 0x20 {
                    result += String(format: "\\u%04X", ascii)
                } else {
                    result.append(char)
                }
            }
        }
        return result
    }

    private func escapeRegexChars(_ str: String) -> String {
        let specialChars = "\\^$.|?*+()[]{}"
        var result = ""
        for char in str {
            if specialChars.contains(char) {
                result.append("\\")
            }
            result.append(char)
        }
        return result
    }
}
