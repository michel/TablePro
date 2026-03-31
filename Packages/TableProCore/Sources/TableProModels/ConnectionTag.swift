import Foundation

public struct ConnectionTag: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String

    public init(
        id: UUID = UUID(),
        name: String = "",
        colorHex: String = "#808080"
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}
