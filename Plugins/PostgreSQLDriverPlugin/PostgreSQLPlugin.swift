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

    func createDriver(config: DriverConnectionConfig) -> any PluginDatabaseDriver {
        let variant = config.additionalFields["driverVariant"] ?? ""
        if variant == "Redshift" {
            return RedshiftPluginDriver(config: config)
        }
        return PostgreSQLPluginDriver(config: config)
    }
}
