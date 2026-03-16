//
//  PluginMetadataRegistry.swift
//  TablePro
//
//  Thread-safe, non-actor metadata cache populated at compile time.
//  All static plugin metadata is served from here, eliminating metatype
//  dispatch on dynamically loaded bundles (which can crash due to
//  missing witness table entries).
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
    let brandColorHex: String
    let queryLanguageName: String
    let editorLanguage: EditorLanguage
    let connectionMode: ConnectionMode
    let supportsDatabaseSwitching: Bool

    let capabilities: CapabilityFlags
    let schema: SchemaInfo
    let editor: EditorConfig
    let connection: ConnectionConfig

    struct CapabilityFlags: Sendable {
        let supportsSchemaSwitching: Bool
        let supportsImport: Bool
        let supportsExport: Bool
        let supportsSSH: Bool
        let supportsSSL: Bool
        let supportsCascadeDrop: Bool
        let supportsForeignKeyDisable: Bool
        let supportsReadOnlyMode: Bool
        let supportsQueryProgress: Bool
        let requiresReconnectForDatabaseSwitch: Bool

        static let defaults = CapabilityFlags(
            supportsSchemaSwitching: false,
            supportsImport: true,
            supportsExport: true,
            supportsSSH: true,
            supportsSSL: true,
            supportsCascadeDrop: false,
            supportsForeignKeyDisable: true,
            supportsReadOnlyMode: true,
            supportsQueryProgress: false,
            requiresReconnectForDatabaseSwitch: false
        )
    }

    struct SchemaInfo: Sendable {
        let defaultSchemaName: String
        let defaultGroupName: String
        let tableEntityName: String
        let defaultPrimaryKeyColumn: String?
        let immutableColumns: [String]
        let systemDatabaseNames: [String]
        let systemSchemaNames: [String]
        let fileExtensions: [String]
        let databaseGroupingStrategy: GroupingStrategy
        let structureColumnFields: [StructureColumnField]

        static let defaults = SchemaInfo(
            defaultSchemaName: "public",
            defaultGroupName: "main",
            tableEntityName: "Tables",
            defaultPrimaryKeyColumn: nil,
            immutableColumns: [],
            systemDatabaseNames: [],
            systemSchemaNames: [],
            fileExtensions: [],
            databaseGroupingStrategy: .byDatabase,
            structureColumnFields: [.name, .type, .nullable, .defaultValue, .autoIncrement, .comment]
        )
    }

    struct EditorConfig: Sendable {
        let sqlDialect: SQLDialectDescriptor?
        let statementCompletions: [CompletionEntry]
        let columnTypesByCategory: [String: [String]]

        static let defaults = EditorConfig(
            sqlDialect: nil,
            statementCompletions: [],
            columnTypesByCategory: [
                "Integer": ["INTEGER", "INT", "SMALLINT", "BIGINT", "TINYINT"],
                "Float": ["FLOAT", "DOUBLE", "DECIMAL", "NUMERIC", "REAL"],
                "String": ["VARCHAR", "CHAR", "TEXT", "NVARCHAR", "NCHAR"],
                "Date": ["DATE", "TIME", "DATETIME", "TIMESTAMP"],
                "Binary": ["BLOB", "BINARY", "VARBINARY"],
                "Boolean": ["BOOLEAN", "BOOL"],
                "JSON": ["JSON"]
            ]
        )
    }

    struct ConnectionConfig: Sendable {
        let additionalConnectionFields: [ConnectionField]

        static let defaults = ConnectionConfig(
            additionalConnectionFields: []
        )
    }
}

final class PluginMetadataRegistry: @unchecked Sendable {
    static let shared = PluginMetadataRegistry()

    private let lock = NSLock()
    private var snapshots: [String: PluginMetadataSnapshot] = [:]
    private var schemeIndex: [String: String] = [:]
    private var reverseTypeIndex: [String: String] = [:]

    private init() {
        registerBuiltInDefaults()
    }

    private func registerBuiltInDefaults() {
        // Built-in plugins (MySQL, MariaDB, PostgreSQL, Redshift, SQLite) self-register
        // their metadata at load time via buildMetadataSnapshot() in PluginManager.registerCapabilities().
        // Only registry plugin defaults (for downloadable plugins not yet installed) are pre-populated here.
        for entry in registryPluginDefaults() {
            snapshots[entry.typeId] = entry.snapshot
            for scheme in entry.snapshot.urlSchemes {
                schemeIndex[scheme.lowercased()] = entry.typeId
            }
        }

        // Built-in type aliases: multi-type plugins where an alias maps to a primary plugin type ID
        reverseTypeIndex["MariaDB"] = "MySQL"
        reverseTypeIndex["Redshift"] = "PostgreSQL"
        reverseTypeIndex["ScyllaDB"] = "Cassandra"
    }

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

    // MARK: - Snapshot Builder

    func buildMetadataSnapshot(
        from driverType: any DriverPlugin.Type,
        isDownloadable: Bool = false,
        parameterStyle: ParameterStyle = .questionMark
    ) -> PluginMetadataSnapshot {
        let schemes = driverType.urlSchemes
        let primaryScheme = schemes.first ?? driverType.databaseTypeId.lowercased()

        return PluginMetadataSnapshot(
            displayName: driverType.databaseDisplayName,
            iconName: driverType.iconName,
            defaultPort: driverType.defaultPort,
            requiresAuthentication: driverType.requiresAuthentication,
            supportsForeignKeys: driverType.supportsForeignKeys,
            supportsSchemaEditing: driverType.supportsSchemaEditing,
            isDownloadable: isDownloadable,
            primaryUrlScheme: primaryScheme,
            parameterStyle: parameterStyle,
            navigationModel: driverType.navigationModel,
            explainVariants: driverType.explainVariants,
            pathFieldRole: driverType.pathFieldRole,
            supportsHealthMonitor: driverType.supportsHealthMonitor,
            urlSchemes: schemes,
            postConnectActions: driverType.postConnectActions,
            brandColorHex: driverType.brandColorHex,
            queryLanguageName: driverType.queryLanguageName,
            editorLanguage: driverType.editorLanguage,
            connectionMode: driverType.connectionMode,
            supportsDatabaseSwitching: driverType.supportsDatabaseSwitching,
            capabilities: PluginMetadataSnapshot.CapabilityFlags(
                supportsSchemaSwitching: driverType.supportsSchemaSwitching,
                supportsImport: driverType.supportsImport,
                supportsExport: driverType.supportsExport,
                supportsSSH: driverType.supportsSSH,
                supportsSSL: driverType.supportsSSL,
                supportsCascadeDrop: driverType.supportsCascadeDrop,
                supportsForeignKeyDisable: driverType.supportsForeignKeyDisable,
                supportsReadOnlyMode: driverType.supportsReadOnlyMode,
                supportsQueryProgress: driverType.supportsQueryProgress,
                requiresReconnectForDatabaseSwitch: driverType.requiresReconnectForDatabaseSwitch
            ),
            schema: PluginMetadataSnapshot.SchemaInfo(
                defaultSchemaName: driverType.defaultSchemaName,
                defaultGroupName: driverType.defaultGroupName,
                tableEntityName: driverType.tableEntityName,
                defaultPrimaryKeyColumn: driverType.defaultPrimaryKeyColumn,
                immutableColumns: driverType.immutableColumns,
                systemDatabaseNames: driverType.systemDatabaseNames,
                systemSchemaNames: driverType.systemSchemaNames,
                fileExtensions: driverType.fileExtensions,
                databaseGroupingStrategy: driverType.databaseGroupingStrategy,
                structureColumnFields: driverType.structureColumnFields
            ),
            editor: PluginMetadataSnapshot.EditorConfig(
                sqlDialect: driverType.sqlDialect,
                statementCompletions: driverType.statementCompletions,
                columnTypesByCategory: driverType.columnTypesByCategory
            ),
            connection: PluginMetadataSnapshot.ConnectionConfig(
                additionalConnectionFields: driverType.additionalConnectionFields
            )
        )
    }

    func databaseType(forUrlScheme scheme: String) -> DatabaseType? {
        guard let typeId = typeId(forUrlScheme: scheme) else { return nil }
        return DatabaseType(rawValue: typeId)
    }

    func allFileExtensions() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        var result: [String: String] = [:]
        for (typeId, snapshot) in snapshots {
            for ext in snapshot.schema.fileExtensions {
                let key = ext.lowercased()
                if result[key] == nil {
                    result[key] = typeId
                }
            }
        }
        return result
    }

    func allUrlSchemes() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return schemeIndex
    }

    // MARK: - Type Registration Helpers

    /// Registers an alias type ID that maps to a primary type ID.
    /// Used for multi-type plugins (e.g., MariaDB → MySQL, Redshift → PostgreSQL).
    func registerTypeAlias(_ aliasTypeId: String, primaryTypeId: String) {
        lock.lock()
        reverseTypeIndex[aliasTypeId] = primaryTypeId
        lock.unlock()
    }

    /// Returns all registered type IDs.
    func allRegisteredTypeIds() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(snapshots.keys)
    }

    /// Resolves a database type raw value to its plugin type ID.
    /// For multi-type plugins (MySQL serves MariaDB), maps the alias to the primary.
    func pluginTypeId(for rawValue: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        if snapshots[rawValue] != nil {
            return reverseTypeIndex[rawValue] ?? rawValue
        }
        return reverseTypeIndex[rawValue] ?? rawValue
    }

    /// Returns whether the given type ID is registered.
    func hasType(_ typeId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return snapshots[typeId] != nil
    }
}
