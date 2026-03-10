import Foundation
import SwiftUI

public protocol TableProPlugin: AnyObject {
    static var pluginName: String { get }
    static var pluginVersion: String { get }
    static var pluginDescription: String { get }
    static var capabilities: [PluginCapability] { get }
    static var dependencies: [String] { get }
    func settingsView() -> AnyView?

    init()
}

public extension TableProPlugin {
    static var dependencies: [String] { [] }
    func settingsView() -> AnyView? { nil }
}
