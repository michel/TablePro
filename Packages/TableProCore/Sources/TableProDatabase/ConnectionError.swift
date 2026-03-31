import Foundation

public enum ConnectionError: Error, LocalizedError {
    case pluginNotFound(String)
    case notConnected
    case sshNotSupported

    public var errorDescription: String? {
        switch self {
        case .pluginNotFound(let type):
            return "No driver plugin for database type: \(type)"
        case .notConnected:
            return "Not connected to database"
        case .sshNotSupported:
            return "SSH tunneling is not available on this platform"
        }
    }
}
