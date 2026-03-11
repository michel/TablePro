//
//  PostgreSQLPlugin.swift
//  PostgreSQLDriverPlugin
//
//  PostgreSQL/Redshift database driver plugin using libpq
//

import Foundation
import os
import TableProPluginKit

// MARK: - Plugin Entry Point

final class PostgreSQLPlugin: NSObject, TableProPlugin, DriverPlugin {
    static let pluginName = "PostgreSQL Driver"
    static let pluginVersion = "1.0.0"
    static let pluginDescription = "PostgreSQL/Redshift support via libpq"
    static let capabilities: [PluginCapability] = [.databaseDriver]

    static let databaseTypeId = "PostgreSQL"
    static let databaseDisplayName = "PostgreSQL"
    static let iconName = "cylinder.fill"
    static let defaultPort = 5432
    static let additionalConnectionFields: [ConnectionField] = []
    static let additionalDatabaseTypeIds: [String] = ["Redshift"]

    // MARK: - UI/Capability Metadata

    static let urlSchemes: [String] = ["postgresql", "postgres"]
    static let brandColorHex = "#336791"
    static let systemDatabaseNames: [String] = ["postgres", "template0", "template1"]
    static let databaseGroupingStrategy: GroupingStrategy = .bySchema
    static let columnTypesByCategory: [String: [String]] = [
        "Integer": ["SMALLINT", "INTEGER", "BIGINT", "SERIAL", "BIGSERIAL", "SMALLSERIAL"],
        "Float": ["REAL", "DOUBLE PRECISION", "NUMERIC", "DECIMAL", "MONEY"],
        "String": ["CHARACTER VARYING", "VARCHAR", "CHARACTER", "CHAR", "TEXT", "NAME"],
        "Date": ["DATE", "TIME", "TIMESTAMP", "TIMESTAMPTZ", "INTERVAL", "TIME WITH TIME ZONE", "TIMESTAMP WITH TIME ZONE"],
        "Binary": ["BYTEA"],
        "Boolean": ["BOOLEAN"],
        "JSON": ["JSON", "JSONB"],
        "UUID": ["UUID"],
        "Array": ["ARRAY"],
        "Network": ["INET", "CIDR", "MACADDR", "MACADDR8"],
        "Geometric": ["POINT", "LINE", "LSEG", "BOX", "PATH", "POLYGON", "CIRCLE"],
        "Range": ["INT4RANGE", "INT8RANGE", "NUMRANGE", "TSRANGE", "TSTZRANGE", "DATERANGE"],
        "Text Search": ["TSVECTOR", "TSQUERY"],
        "XML": ["XML"]
    ]

    static func driverVariant(for databaseTypeId: String) -> String? {
        switch databaseTypeId {
        case "PostgreSQL": return "PostgreSQL"
        case "Redshift": return "Redshift"
        default: return nil
        }
    }

    func createDriver(config: DriverConnectionConfig) -> any PluginDatabaseDriver {
        let variant = config.additionalFields["driverVariant"] ?? ""
        if variant == "Redshift" {
            return RedshiftPluginDriver(config: config)
        }
        return PostgreSQLPluginDriver(config: config)
    }
}
