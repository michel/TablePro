import Foundation

public enum PluginCapability: Int, Codable, Sendable {
    case databaseDriver
    case exportFormat
    case importFormat
    case sqlDialect
    case aiProvider
    case cellRenderer
    case sidebarPanel
}
