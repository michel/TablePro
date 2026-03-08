//
//  MySQLPlugin.swift
//  MySQLDriverPlugin
//
//  MySQL/MariaDB database driver plugin using libmariadb (MariaDB Connector/C)
//

import CMariaDB
import Foundation
import os
import TableProPluginKit

// MARK: - Plugin Entry Point

final class MySQLPlugin: NSObject, TableProPlugin, DriverPlugin {
    static let pluginName = "MySQL Driver"
    static let pluginVersion = "1.0.0"
    static let pluginDescription = "MySQL/MariaDB support via libmariadb"
    static let capabilities: [PluginCapability] = [.databaseDriver]

    static let databaseTypeId = "MySQL"
    static let databaseDisplayName = "MySQL"
    static let iconName = "cylinder.fill"
    static let defaultPort = 3306
    static let additionalConnectionFields: [ConnectionField] = []
    static let additionalDatabaseTypeIds: [String] = ["MariaDB"]

    func createDriver(config: DriverConnectionConfig) -> any PluginDatabaseDriver {
        MySQLPluginDriver(config: config)
    }
}
