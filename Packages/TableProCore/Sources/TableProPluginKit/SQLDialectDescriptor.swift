import Foundation

public enum AutoLimitStyle: String, Sendable {
    case limit
    case fetchFirst
    case top
    case none
}

public struct SQLDialectDescriptor: Sendable {
    public let identifierQuote: String
    public let keywords: Set<String>
    public let functions: Set<String>
    public let dataTypes: Set<String>
    public let tableOptions: [String]

    public let regexSyntax: RegexSyntax
    public let booleanLiteralStyle: BooleanLiteralStyle
    public let likeEscapeStyle: LikeEscapeStyle
    public let paginationStyle: PaginationStyle
    public let offsetFetchOrderBy: String
    public let requiresBackslashEscaping: Bool

    public let autoLimitStyle: AutoLimitStyle

    public enum RegexSyntax: String, Sendable {
        case regexp
        case tilde
        case regexpMatches
        case match
        case regexpLike
        case unsupported
    }

    public enum BooleanLiteralStyle: String, Sendable {
        case truefalse
        case numeric
    }

    public enum LikeEscapeStyle: String, Sendable {
        case implicit
        case explicit
    }

    public enum PaginationStyle: String, Sendable {
        case limit
        case offsetFetch
    }

    public init(
        identifierQuote: String,
        keywords: Set<String>,
        functions: Set<String>,
        dataTypes: Set<String>,
        tableOptions: [String] = [],
        regexSyntax: RegexSyntax = .unsupported,
        booleanLiteralStyle: BooleanLiteralStyle = .numeric,
        likeEscapeStyle: LikeEscapeStyle = .explicit,
        paginationStyle: PaginationStyle = .limit,
        offsetFetchOrderBy: String = "ORDER BY (SELECT NULL)",
        requiresBackslashEscaping: Bool = false,
        autoLimitStyle: AutoLimitStyle = .limit
    ) {
        self.identifierQuote = identifierQuote
        self.keywords = keywords
        self.functions = functions
        self.dataTypes = dataTypes
        self.tableOptions = tableOptions
        self.regexSyntax = regexSyntax
        self.booleanLiteralStyle = booleanLiteralStyle
        self.likeEscapeStyle = likeEscapeStyle
        self.paginationStyle = paginationStyle
        self.offsetFetchOrderBy = offsetFetchOrderBy
        self.requiresBackslashEscaping = requiresBackslashEscaping
        self.autoLimitStyle = autoLimitStyle
    }
}
