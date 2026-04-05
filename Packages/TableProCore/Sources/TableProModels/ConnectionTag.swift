import Foundation

public struct ConnectionTag: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var color: ConnectionColor
    public var isPreset: Bool

    public init(
        id: UUID = UUID(),
        name: String = "",
        isPreset: Bool = false,
        color: ConnectionColor = .gray
    ) {
        self.id = id
        self.name = name
        self.isPreset = isPreset
        self.color = color
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, color, colorHex, isPreset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isPreset = try container.decodeIfPresent(Bool.self, forKey: .isPreset) ?? false

        if let color = try container.decodeIfPresent(ConnectionColor.self, forKey: .color) {
            self.color = color
        } else if let hex = try container.decodeIfPresent(String.self, forKey: .colorHex) {
            self.color = ConnectionTag.colorFromHex(hex)
        } else {
            self.color = .gray
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
        try container.encode(isPreset, forKey: .isPreset)
    }

    private static func colorFromHex(_ hex: String) -> ConnectionColor {
        let normalized = hex.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        switch normalized {
        case "ff0000", "ff3b30", "cc0000": return .red
        case "ff9500", "ff8c00", "ffa500": return .orange
        case "ffcc00", "ffff00", "ffd700": return .yellow
        case "34c759", "28cd41", "00ff00", "008000": return .green
        case "007aff", "0000ff", "5856d6": return .blue
        case "af52de", "800080", "9b59b6": return .purple
        case "ff2d55", "ff69b4", "ffc0cb": return .pink
        default: return .gray
        }
    }

    public static let presets: [ConnectionTag] = [
        ConnectionTag(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            name: "local",
            isPreset: true,
            color: .green
        ),
        ConnectionTag(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID(),
            name: "development",
            isPreset: true,
            color: .blue
        ),
        ConnectionTag(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003") ?? UUID(),
            name: "production",
            isPreset: true,
            color: .red
        ),
        ConnectionTag(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004") ?? UUID(),
            name: "testing",
            isPreset: true,
            color: .orange
        )
    ]
}
