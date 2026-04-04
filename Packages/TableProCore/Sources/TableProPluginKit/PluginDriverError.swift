import Foundation

public protocol PluginDriverError: Error, LocalizedError, Sendable {
    var pluginErrorCode: Int? { get }
    var pluginSqlState: String? { get }
    var pluginMessage: String { get }
    var pluginDetail: String? { get }
}

public extension PluginDriverError {
    var pluginErrorCode: Int? { nil }
    var pluginSqlState: String? { nil }
    var pluginDetail: String? { nil }

    var errorDescription: String? {
        var desc = pluginMessage
        if let code = pluginErrorCode, code != 0 {
            desc = "[\(code)] \(desc)"
        }
        if let state = pluginSqlState {
            desc += " (SQLSTATE: \(state))"
        }
        if let detail = pluginDetail, !detail.isEmpty {
            desc += "\nDetail: \(detail)"
        }
        return desc
    }
}
