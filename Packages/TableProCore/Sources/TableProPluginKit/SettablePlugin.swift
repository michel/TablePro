import Foundation

public protocol SettablePlugin: AnyObject {
    associatedtype Settings: Codable & Equatable

    static var settingsStorageId: String { get }

    var settings: Settings { get set }
}
