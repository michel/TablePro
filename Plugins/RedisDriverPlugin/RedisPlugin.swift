//
//  RedisPlugin.swift
//  RedisDriverPlugin
//
//  Redis database driver plugin using hiredis (Redis C client library)
//

import Foundation
import os
import TableProPluginKit

// MARK: - Plugin Entry Point

final class RedisPlugin: NSObject, TableProPlugin, DriverPlugin {
    static let pluginName = "Redis Driver"
    static let pluginVersion = "1.0.0"
    static let pluginDescription = "Redis support via hiredis"
    static let capabilities: [PluginCapability] = [.databaseDriver]

    static let databaseTypeId = "Redis"
    static let databaseDisplayName = "Redis"
    static let iconName = "cylinder.fill"
    static let defaultPort = 6379
    static let additionalConnectionFields: [ConnectionField] = []
    static let additionalDatabaseTypeIds: [String] = []

    func createDriver(config: DriverConnectionConfig) -> any PluginDatabaseDriver {
        RedisPluginDriver(config: config)
    }
}
