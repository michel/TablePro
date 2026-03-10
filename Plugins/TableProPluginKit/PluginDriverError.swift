//
//  PluginDriverError.swift
//  TableProPluginKit
//

import Foundation

public protocol PluginDriverError: LocalizedError, Sendable {
    var pluginErrorMessage: String { get }
    var pluginErrorCode: Int? { get }
    var pluginSqlState: String? { get }
    var pluginErrorDetail: String? { get }
}

public extension PluginDriverError {
    var pluginErrorCode: Int? { nil }
    var pluginSqlState: String? { nil }
    var pluginErrorDetail: String? { nil }
}
