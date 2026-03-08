import Foundation

public struct ConnectionField: Codable, Sendable {
    public let id: String
    public let label: String
    public let placeholder: String
    public let isRequired: Bool
    public let isSecure: Bool
    public let defaultValue: String?

    public init(
        id: String,
        label: String,
        placeholder: String = "",
        required: Bool = false,
        secure: Bool = false,
        defaultValue: String? = nil
    ) {
        self.id = id
        self.label = label
        self.placeholder = placeholder
        self.isRequired = required
        self.isSecure = secure
        self.defaultValue = defaultValue
    }
}
