import Foundation
import TableProModels
import TableProPluginKit

public final class PluginMetadataProvider: Sendable {
    private let pluginLoader: PluginLoader

    public init(pluginLoader: PluginLoader) {
        self.pluginLoader = pluginLoader
    }

    public func displayName(for type: DatabaseType) -> String {
        plugin(for: type)?.databaseDisplayName ?? type.rawValue.capitalized
    }

    public func defaultPort(for type: DatabaseType) -> Int {
        plugin(for: type)?.defaultPort ?? 3306
    }

    public func iconName(for type: DatabaseType) -> String {
        plugin(for: type)?.iconName ?? "server.rack"
    }

    public func supportsSSH(for type: DatabaseType) -> Bool {
        plugin(for: type)?.supportsSSH ?? false
    }

    public func supportsSSL(for type: DatabaseType) -> Bool {
        plugin(for: type)?.supportsSSL ?? false
    }

    public func sqlDialect(for type: DatabaseType) -> SQLDialectDescriptor? {
        plugin(for: type)?.sqlDialect
    }

    public func brandColorHex(for type: DatabaseType) -> String {
        plugin(for: type)?.brandColorHex ?? "#808080"
    }

    public func editorLanguage(for type: DatabaseType) -> EditorLanguage {
        plugin(for: type)?.editorLanguage ?? .sql
    }

    public func connectionMode(for type: DatabaseType) -> ConnectionMode {
        plugin(for: type)?.connectionMode ?? .network
    }

    public func supportsDatabaseSwitching(for type: DatabaseType) -> Bool {
        plugin(for: type)?.supportsDatabaseSwitching ?? true
    }

    public func supportsSchemaSwitching(for type: DatabaseType) -> Bool {
        plugin(for: type)?.supportsSchemaSwitching ?? false
    }

    public func groupingStrategy(for type: DatabaseType) -> GroupingStrategy {
        plugin(for: type)?.databaseGroupingStrategy ?? .byDatabase
    }

    private func plugin(for type: DatabaseType) -> (any DriverPlugin.Type)? {
        guard let plugin = pluginLoader.driverPlugin(for: type.pluginTypeId) else { return nil }
        return Swift.type(of: plugin)
    }
}
