import Foundation

public struct TableFilter: Identifiable, Codable, Sendable {
    public var id: UUID
    public var columnName: String
    public var filterOperator: FilterOperator
    public var value: String
    public var secondValue: String
    public var isEnabled: Bool
    public var rawSQL: String?

    public static let rawSQLColumn = "__raw_sql__"

    public var isValid: Bool {
        if columnName == Self.rawSQLColumn {
            guard let sql = rawSQL, !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            return true
        }
        guard !columnName.isEmpty else { return false }
        switch filterOperator {
        case .isNull, .isNotNull:
            return true
        case .between:
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !secondValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public init(
        id: UUID = UUID(),
        columnName: String = "",
        filterOperator: FilterOperator = .equal,
        value: String = "",
        secondValue: String = "",
        isEnabled: Bool = true,
        rawSQL: String? = nil
    ) {
        self.id = id
        self.columnName = columnName
        self.filterOperator = filterOperator
        self.value = value
        self.secondValue = secondValue
        self.isEnabled = isEnabled
        self.rawSQL = rawSQL
    }
}

public enum FilterOperator: String, Codable, Sendable, CaseIterable {
    case equal
    case notEqual
    case greaterThan
    case greaterThanOrEqual
    case lessThan
    case lessThanOrEqual
    case like
    case notLike
    case isNull
    case isNotNull
    case `in`
    case notIn
    case between
    case contains
    case startsWith
    case endsWith

    public var sqlSymbol: String {
        switch self {
        case .equal: return "="
        case .notEqual: return "!="
        case .greaterThan: return ">"
        case .greaterThanOrEqual: return ">="
        case .lessThan: return "<"
        case .lessThanOrEqual: return "<="
        case .like: return "LIKE"
        case .notLike: return "NOT LIKE"
        case .isNull: return "IS NULL"
        case .isNotNull: return "IS NOT NULL"
        case .in: return "IN"
        case .notIn: return "NOT IN"
        case .between: return "BETWEEN"
        case .contains: return "LIKE"
        case .startsWith: return "LIKE"
        case .endsWith: return "LIKE"
        }
    }
}

public enum FilterLogicMode: String, Codable, Sendable {
    case and = "AND"
    case or = "OR"
}
