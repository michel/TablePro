//
//  PluginMetadataRegistry.swift
//  TablePro
//
//  Thread-safe, non-actor metadata cache populated at plugin load time.
//  Provides synchronous access to plugin metadata from any context.
//

import Foundation
import TableProPluginKit

struct PluginMetadataSnapshot: Sendable {
    let displayName: String
    let iconName: String
    let defaultPort: Int
    let requiresAuthentication: Bool
    let supportsForeignKeys: Bool
    let supportsSchemaEditing: Bool
    let isDownloadable: Bool
    let primaryUrlScheme: String
    let parameterStyle: ParameterStyle
    let navigationModel: NavigationModel
    let explainVariants: [ExplainVariant]
    let pathFieldRole: PathFieldRole
    let supportsHealthMonitor: Bool
    let urlSchemes: [String]
    let postConnectActions: [PostConnectAction]
}

final class PluginMetadataRegistry: @unchecked Sendable {
    static let shared = PluginMetadataRegistry()

    private let lock = NSLock()
    private var snapshots: [String: PluginMetadataSnapshot] = [:]
    private var schemeIndex: [String: String] = [:]

    private init() {
        registerBuiltInDefaults()
    }

    // swiftlint:disable function_body_length
    private func registerBuiltInDefaults() {
        let defaults: [(typeId: String, snapshot: PluginMetadataSnapshot)] = [
            ("MySQL", PluginMetadataSnapshot(
                displayName: "MySQL", iconName: "mysql-icon", defaultPort: 3_306,
                requiresAuthentication: true, supportsForeignKeys: true, supportsSchemaEditing: true,
                isDownloadable: false, primaryUrlScheme: "mysql", parameterStyle: .questionMark,
                navigationModel: .standard, explainVariants: [], pathFieldRole: .database,
                supportsHealthMonitor: true, urlSchemes: ["mysql"], postConnectActions: []
            )),
            ("MariaDB", PluginMetadataSnapshot(
                displayName: "MariaDB", iconName: "mariadb-icon", defaultPort: 3_306,
                requiresAuthentication: true, supportsForeignKeys: true, supportsSchemaEditing: true,
                isDownloadable: false, primaryUrlScheme: "mariadb", parameterStyle: .questionMark,
                navigationModel: .standard, explainVariants: [], pathFieldRole: .database,
                supportsHealthMonitor: true, urlSchemes: ["mariadb"], postConnectActions: []
            )),
            ("PostgreSQL", PluginMetadataSnapshot(
                displayName: "PostgreSQL", iconName: "postgresql-icon", defaultPort: 5_432,
                requiresAuthentication: true, supportsForeignKeys: true, supportsSchemaEditing: true,
                isDownloadable: false, primaryUrlScheme: "postgresql", parameterStyle: .dollar,
                navigationModel: .standard, explainVariants: [], pathFieldRole: .database,
                supportsHealthMonitor: true, urlSchemes: ["postgresql", "postgres"], postConnectActions: []
            )),
            ("Redshift", PluginMetadataSnapshot(
                displayName: "Redshift", iconName: "redshift-icon", defaultPort: 5_439,
                requiresAuthentication: true, supportsForeignKeys: true, supportsSchemaEditing: false,
                isDownloadable: false, primaryUrlScheme: "redshift", parameterStyle: .dollar,
                navigationModel: .standard, explainVariants: [], pathFieldRole: .database,
                supportsHealthMonitor: true, urlSchemes: ["redshift"], postConnectActions: []
            )),
            ("SQLite", PluginMetadataSnapshot(
                displayName: "SQLite", iconName: "sqlite-icon", defaultPort: 0,
                requiresAuthentication: false, supportsForeignKeys: true, supportsSchemaEditing: true,
                isDownloadable: true, primaryUrlScheme: "sqlite", parameterStyle: .questionMark,
                navigationModel: .standard, explainVariants: [], pathFieldRole: .filePath,
                supportsHealthMonitor: false, urlSchemes: ["sqlite"], postConnectActions: []
            )),
            ("MongoDB", PluginMetadataSnapshot(
                displayName: "MongoDB", iconName: "mongodb-icon", defaultPort: 27_017,
                requiresAuthentication: false, supportsForeignKeys: false, supportsSchemaEditing: false,
                isDownloadable: false, primaryUrlScheme: "mongodb", parameterStyle: .questionMark,
                navigationModel: .standard, explainVariants: [], pathFieldRole: .database,
                supportsHealthMonitor: true, urlSchemes: ["mongodb", "mongodb+srv"], postConnectActions: []
            )),
            ("Redis", PluginMetadataSnapshot(
                displayName: "Redis", iconName: "redis-icon", defaultPort: 6_379,
                requiresAuthentication: false, supportsForeignKeys: false, supportsSchemaEditing: false,
                isDownloadable: false, primaryUrlScheme: "redis", parameterStyle: .questionMark,
                navigationModel: .inPlace, explainVariants: [], pathFieldRole: .databaseIndex,
                supportsHealthMonitor: true, urlSchemes: ["redis", "rediss"],
                postConnectActions: [.selectDatabaseFromConnectionField(fieldId: "redisDatabase")]
            )),
            ("SQL Server", PluginMetadataSnapshot(
                displayName: "SQL Server", iconName: "mssql-icon", defaultPort: 1_433,
                requiresAuthentication: true, supportsForeignKeys: true, supportsSchemaEditing: true,
                isDownloadable: false, primaryUrlScheme: "sqlserver", parameterStyle: .questionMark,
                navigationModel: .standard, explainVariants: [], pathFieldRole: .database,
                supportsHealthMonitor: true, urlSchemes: ["sqlserver", "mssql"],
                postConnectActions: [.selectDatabaseFromLastSession]
            )),
            ("Oracle", PluginMetadataSnapshot(
                displayName: "Oracle", iconName: "oracle-icon", defaultPort: 1_521,
                requiresAuthentication: true, supportsForeignKeys: true, supportsSchemaEditing: true,
                isDownloadable: true, primaryUrlScheme: "oracle", parameterStyle: .questionMark,
                navigationModel: .standard, explainVariants: [], pathFieldRole: .serviceName,
                supportsHealthMonitor: true, urlSchemes: ["oracle"], postConnectActions: []
            )),
            ("ClickHouse", PluginMetadataSnapshot(
                displayName: "ClickHouse", iconName: "clickhouse-icon", defaultPort: 8_123,
                requiresAuthentication: true, supportsForeignKeys: false, supportsSchemaEditing: true,
                isDownloadable: true, primaryUrlScheme: "clickhouse", parameterStyle: .questionMark,
                navigationModel: .standard, explainVariants: [
                    ExplainVariant(id: "plan", label: "Plan", sqlPrefix: "EXPLAIN"),
                    ExplainVariant(id: "pipeline", label: "Pipeline", sqlPrefix: "EXPLAIN PIPELINE"),
                    ExplainVariant(id: "ast", label: "AST", sqlPrefix: "EXPLAIN AST"),
                    ExplainVariant(id: "syntax", label: "Syntax", sqlPrefix: "EXPLAIN SYNTAX"),
                    ExplainVariant(id: "estimate", label: "Estimate", sqlPrefix: "EXPLAIN ESTIMATE"),
                ], pathFieldRole: .database,
                supportsHealthMonitor: true, urlSchemes: ["clickhouse", "ch"], postConnectActions: []
            )),
            ("DuckDB", PluginMetadataSnapshot(
                displayName: "DuckDB", iconName: "duckdb-icon", defaultPort: 0,
                requiresAuthentication: false, supportsForeignKeys: true, supportsSchemaEditing: true,
                isDownloadable: true, primaryUrlScheme: "duckdb", parameterStyle: .dollar,
                navigationModel: .standard, explainVariants: [], pathFieldRole: .filePath,
                supportsHealthMonitor: false, urlSchemes: ["duckdb"], postConnectActions: []
            )),
            ("Cassandra", PluginMetadataSnapshot(
                displayName: "Cassandra / ScyllaDB", iconName: "cassandra-icon", defaultPort: 9_042,
                requiresAuthentication: false, supportsForeignKeys: false, supportsSchemaEditing: true,
                isDownloadable: true, primaryUrlScheme: "cassandra", parameterStyle: .questionMark,
                navigationModel: .standard, explainVariants: [], pathFieldRole: .database,
                supportsHealthMonitor: true, urlSchemes: ["cassandra", "cql", "scylladb", "scylla"],
                postConnectActions: []
            )),
            ("ScyllaDB", PluginMetadataSnapshot(
                displayName: "ScyllaDB", iconName: "scylladb-icon", defaultPort: 9_042,
                requiresAuthentication: false, supportsForeignKeys: false, supportsSchemaEditing: true,
                isDownloadable: true, primaryUrlScheme: "scylladb", parameterStyle: .questionMark,
                navigationModel: .standard, explainVariants: [], pathFieldRole: .database,
                supportsHealthMonitor: true, urlSchemes: ["scylladb", "scylla"],
                postConnectActions: []
            )),
        ]
        for entry in defaults {
            snapshots[entry.typeId] = entry.snapshot
            for scheme in entry.snapshot.urlSchemes {
                schemeIndex[scheme.lowercased()] = entry.typeId
            }
        }
    }
    // swiftlint:enable function_body_length

    func register(snapshot: PluginMetadataSnapshot, forTypeId typeId: String) {
        lock.lock()
        defer { lock.unlock() }
        snapshots[typeId] = snapshot
        for scheme in snapshot.urlSchemes {
            schemeIndex[scheme.lowercased()] = typeId
        }
    }

    func unregister(typeId: String) {
        lock.lock()
        defer { lock.unlock() }
        if let snapshot = snapshots.removeValue(forKey: typeId) {
            for scheme in snapshot.urlSchemes {
                schemeIndex.removeValue(forKey: scheme.lowercased())
            }
        }
    }

    func snapshot(forTypeId typeId: String) -> PluginMetadataSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshots[typeId]
    }

    func typeId(forUrlScheme scheme: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return schemeIndex[scheme.lowercased()]
    }

    func databaseType(forUrlScheme scheme: String) -> DatabaseType? {
        guard let typeId = typeId(forUrlScheme: scheme) else { return nil }
        return DatabaseType(rawValue: typeId)
    }
}

extension PluginMetadataSnapshot {
    init(from pluginType: any DriverPlugin.Type) {
        self.displayName = pluginType.databaseDisplayName
        self.iconName = pluginType.iconName
        self.defaultPort = pluginType.defaultPort
        self.requiresAuthentication = pluginType.requiresAuthentication
        self.supportsForeignKeys = pluginType.supportsForeignKeys
        self.supportsSchemaEditing = pluginType.supportsSchemaEditing
        self.isDownloadable = pluginType.isDownloadable
        self.primaryUrlScheme = pluginType.urlSchemes.first ?? pluginType.databaseTypeId.lowercased()
        // parameterStyle is instance-level on PluginDatabaseDriver, not type-level on DriverPlugin.
        // Use default here; consumers needing the actual style should query the driver instance.
        self.parameterStyle = .questionMark
        self.navigationModel = pluginType.navigationModel
        self.explainVariants = pluginType.explainVariants
        self.pathFieldRole = pluginType.pathFieldRole
        self.supportsHealthMonitor = pluginType.supportsHealthMonitor
        self.urlSchemes = pluginType.urlSchemes
        self.postConnectActions = pluginType.postConnectActions
    }
}
