import Foundation

public enum ConnectionColor: String, CaseIterable, Identifiable, Codable, Sendable {
    case none = "None"
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case purple = "Purple"
    case pink = "Pink"
    case gray = "Gray"

    public var id: String { rawValue }
    public var isDefault: Bool { self == .none }
}
