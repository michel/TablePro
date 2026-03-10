import Foundation

public protocol DriverPlugin: TableProPlugin {
    static var databaseTypeId: String { get }
    static var databaseDisplayName: String { get }
    static var iconName: String { get }
    static var defaultPort: Int { get }
    static var additionalConnectionFields: [ConnectionField] { get }
    static var additionalDatabaseTypeIds: [String] { get }

    static func driverVariant(for databaseTypeId: String) -> String?

    func createDriver(config: DriverConnectionConfig) -> any PluginDatabaseDriver
}

public extension DriverPlugin {
    static var additionalConnectionFields: [ConnectionField] { [] }
    static var additionalDatabaseTypeIds: [String] { [] }
    static func driverVariant(for databaseTypeId: String) -> String? { nil }
}
