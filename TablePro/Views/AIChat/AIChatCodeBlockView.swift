//
//  AIChatCodeBlockView.swift
//  TablePro
//
//  Code block view with copy and insert-to-editor actions.
//

import SwiftUI

/// Displays a code block from AI response with action buttons
struct AIChatCodeBlockView: View {
    let code: String
    let language: String?

    @State private var isCopied: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language badge and actions
            HStack {
                if let language {
                    Text(language.uppercased())
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .separatorColor).opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isCopied = false
                    }
                } label: {
                    Label(
                        isCopied ? String(localized: "Copied") : String(localized: "Copy"),
                        systemImage: isCopied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if isSQL {
                    Button {
                        NotificationCenter.default.post(
                            name: .insertQueryFromAI,
                            object: code
                        )
                    } label: {
                        Label(String(localized: "Insert"), systemImage: "square.and.pencil")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                if isSQL {
                    Text(highlightedSQL(code))
                        .textSelection(.enabled)
                        .padding(10)
                } else {
                    Text(code)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
        )
    }

    private var isSQL: Bool {
        guard let language else { return false }
        let sqlLanguages = ["sql", "mysql", "postgresql", "postgres", "sqlite"]
        return sqlLanguages.contains(language.lowercased())
    }

    // MARK: - Static SQL Regex Patterns (compiled once)

    private enum SQLPatterns {
        // swiftlint:disable force_try
        static let singleLineComment = try! NSRegularExpression(pattern: "--[^\r\n]*")
        static let multiLineComment = try! NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/")
        static let stringLiteral = try! NSRegularExpression(pattern: "'[^']*'")
        static let number = try! NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b")
        static let nullBoolLiteral = try! NSRegularExpression(
            pattern: "\\b(NULL|TRUE|FALSE)\\b",
            options: .caseInsensitive
        )
        static let keyword: NSRegularExpression = {
            let keywords = [
                "SELECT", "FROM", "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS",
                "ON", "AND", "OR", "NOT", "IN", "EXISTS", "BETWEEN", "LIKE", "IS", "AS",
                "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET", "UNION", "ALL", "DISTINCT",
                "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "ALTER", "DROP",
                "TABLE", "INDEX", "VIEW", "IF", "THEN", "ELSE", "END", "CASE", "WHEN",
                "COUNT", "SUM", "AVG", "MIN", "MAX", "ASC", "DESC",
                "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "DEFAULT", "CONSTRAINT", "UNIQUE",
                "CHECK", "CASCADE", "TRUNCATE", "RETURNING", "WITH", "RECURSIVE",
                "OVER", "PARTITION", "WINDOW", "GRANT", "REVOKE",
                "BEGIN", "COMMIT", "ROLLBACK", "EXPLAIN", "ANALYZE"
            ]
            let pattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
            return try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        }()
        // swiftlint:enable force_try
    }

    // swiftlint:disable:next function_body_length
    private func highlightedSQL(_ code: String) -> AttributedString {
        var result = AttributedString(code)
        result.font = .system(size: 12, design: .monospaced)

        var protectedRanges: [Range<AttributedString.Index>] = []

        func applyColor(_ nsRange: NSRange, color: NSColor, protect: Bool = false) {
            guard let stringRange = Range(nsRange, in: code),
                  let attrStart = AttributedString.Index(stringRange.lowerBound, within: result),
                  let attrEnd = AttributedString.Index(stringRange.upperBound, within: result) else {
                return
            }
            let range = attrStart..<attrEnd
            result[range].foregroundColor = Color(nsColor: color)
            if protect {
                protectedRanges.append(range)
            }
        }

        func isProtected(_ nsRange: NSRange) -> Bool {
            guard let stringRange = Range(nsRange, in: code),
                  let attrStart = AttributedString.Index(stringRange.lowerBound, within: result),
                  let attrEnd = AttributedString.Index(stringRange.upperBound, within: result) else {
                return false
            }
            let range = attrStart..<attrEnd
            return protectedRanges.contains { $0.overlaps(range) }
        }

        let nsCode = code as NSString
        let fullRange = NSRange(location: 0, length: nsCode.length)

        // 1. Single-line comments: --.*
        for match in SQLPatterns.singleLineComment.matches(in: code, range: fullRange) {
            applyColor(match.range, color: .systemGreen, protect: true)
        }

        // 2. Multi-line comments: /* ... */
        for match in SQLPatterns.multiLineComment.matches(in: code, range: fullRange) {
            applyColor(match.range, color: .systemGreen, protect: true)
        }

        // 3. String literals: '...'
        for match in SQLPatterns.stringLiteral.matches(in: code, range: fullRange) {
            applyColor(match.range, color: .systemRed, protect: true)
        }

        // 4. Numbers: \b\d+(\.\d+)?\b
        for match in SQLPatterns.number.matches(in: code, range: fullRange) {
            guard !isProtected(match.range) else { continue }
            applyColor(match.range, color: .systemPurple)
        }

        // 5. NULL / TRUE / FALSE
        for match in SQLPatterns.nullBoolLiteral.matches(in: code, range: fullRange) {
            guard !isProtected(match.range) else { continue }
            applyColor(match.range, color: .systemOrange)
        }

        // 6. SQL keywords
        for match in SQLPatterns.keyword.matches(in: code, range: fullRange) {
            guard !isProtected(match.range) else { continue }
            applyColor(match.range, color: .systemBlue)
        }

        return result
    }
}
