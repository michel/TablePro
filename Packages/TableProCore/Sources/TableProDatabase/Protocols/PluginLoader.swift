import Foundation
import TableProPluginKit

public protocol PluginLoader: Sendable {
    func availablePlugins() -> [any DriverPlugin]
    func driverPlugin(for typeId: String) -> (any DriverPlugin)?
}
