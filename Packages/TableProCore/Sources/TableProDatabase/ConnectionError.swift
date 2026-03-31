import Foundation

public enum ConnectionError: Error, LocalizedError {
    case driverNotFound(String)
    case notConnected
    case sshNotSupported

    public var errorDescription: String? {
        switch self {
        case .driverNotFound(let type):
            return "No driver available for database type: \(type)"
        case .notConnected:
            return "Not connected to database"
        case .sshNotSupported:
            return "SSH tunneling is not available on this platform"
        }
    }
}
