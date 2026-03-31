//
//  StaticPluginLoader.swift
//  TableProMobile
//
//  iOS plugin loader — returns compiled-in drivers.
//  macOS uses BundlePluginLoader (runtime .tableplugin loading).
//

import Foundation
import TableProDatabase
@preconcurrency import TableProPluginKit

final class StaticPluginLoader: PluginLoader, Sendable {
    nonisolated(unsafe) private let plugins: [any DriverPlugin]

    init() {
        // TODO: Register compiled-in plugins when C libs are cross-compiled for iOS
        plugins = []
    }

    func availablePlugins() -> [any DriverPlugin] {
        plugins
    }

    func driverPlugin(for typeId: String) -> (any DriverPlugin)? {
        plugins.first { type(of: $0).databaseTypeId == typeId }
    }
}
