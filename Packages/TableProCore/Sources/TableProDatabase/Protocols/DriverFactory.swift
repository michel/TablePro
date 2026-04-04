import Foundation
import TableProModels

/// Creates database drivers for a given connection.
/// macOS: plugin-based implementation. iOS: direct driver creation.
public protocol DriverFactory: Sendable {
    func createDriver(for connection: DatabaseConnection, password: String?) throws -> any DatabaseDriver
    func supportedTypes() -> [DatabaseType]
}
