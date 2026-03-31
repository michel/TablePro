import Foundation

public struct CompletionEntry: Sendable {
    public let label: String
    public let detail: String?
    public let iconName: String
    public let kind: CompletionKind

    public enum CompletionKind: String, Sendable {
        case keyword
        case function
        case table
        case column
        case schema
        case database
        case snippet
    }

    public init(label: String, detail: String? = nil, iconName: String = "text.word.spacing", kind: CompletionKind = .keyword) {
        self.label = label
        self.detail = detail
        self.iconName = iconName
        self.kind = kind
    }

    public init(label: String, insertText: String) {
        self.label = label
        self.detail = insertText
        self.iconName = "text.word.spacing"
        self.kind = .snippet
    }
}
