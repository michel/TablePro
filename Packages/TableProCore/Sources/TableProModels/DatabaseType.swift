import Foundation

public struct DatabaseType: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    // MARK: - Known Constants

    public static let mysql = DatabaseType(rawValue: "mysql")
    public static let mariadb = DatabaseType(rawValue: "mariadb")
    public static let postgresql = DatabaseType(rawValue: "postgresql")
    public static let sqlite = DatabaseType(rawValue: "sqlite")
    public static let redis = DatabaseType(rawValue: "redis")
    public static let mongodb = DatabaseType(rawValue: "mongodb")
    public static let clickhouse = DatabaseType(rawValue: "clickhouse")
    public static let mssql = DatabaseType(rawValue: "mssql")
    public static let oracle = DatabaseType(rawValue: "oracle")
    public static let duckdb = DatabaseType(rawValue: "duckdb")
    public static let cassandra = DatabaseType(rawValue: "cassandra")
    public static let redshift = DatabaseType(rawValue: "redshift")
    public static let etcd = DatabaseType(rawValue: "etcd")
    public static let cloudflareD1 = DatabaseType(rawValue: "cloudflared1")
    public static let dynamodb = DatabaseType(rawValue: "dynamodb")
    public static let bigquery = DatabaseType(rawValue: "bigquery")

    public static let allKnownTypes: [DatabaseType] = [
        .mysql, .mariadb, .postgresql, .sqlite, .redis, .mongodb,
        .clickhouse, .mssql, .oracle, .duckdb, .cassandra, .redshift,
        .etcd, .cloudflareD1, .dynamodb, .bigquery
    ]

    /// Plugin type ID for plugin lookup.
    /// Multi-type plugins share a single driver: mariadb -> "mysql", redshift -> "postgresql"
    public var pluginTypeId: String {
        switch self {
        case .mariadb: return DatabaseType.mysql.rawValue
        case .redshift: return DatabaseType.postgresql.rawValue
        default: return rawValue
        }
    }
}
