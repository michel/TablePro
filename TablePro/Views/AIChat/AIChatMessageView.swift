//
//  AIChatMessageView.swift
//  TablePro
//
//  Individual chat message bubble view with role-based styling.
//

import SwiftUI

/// Displays a single AI chat message with appropriate styling
struct AIChatMessageView: View {
    let message: AIChatMessage
    var onRetry: (() -> Void)?
    var onRegenerate: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                messageContent

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if message.role == .assistant, let usage = message.usage {
                    Text("\(usage.inputTokens) in / \(usage.outputTokens) out tokens")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                if let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.red)
                            Text("Generation failed.")
                                .foregroundStyle(.secondary)
                            Text("Retry")
                                .fontWeight(.medium)
                                .foregroundColor(.accentColor)
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                if let onRegenerate {
                    Button {
                        onRegenerate()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Regenerate")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        if message.content.isEmpty {
            TypingIndicatorView()
                .padding(10)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            let blocks = parseContent(message.content)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let text):
                        markdownLinesView(for: text)
                    case .code(let code, let language):
                        AIChatCodeBlockView(code: code, language: language)
                    }
                }
            }
            .padding(10)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var bubbleBackground: some ShapeStyle {
        if message.role == .user {
            return AnyShapeStyle(Color.accentColor.opacity(0.15))
        } else {
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
        }
    }

    // MARK: - Line-by-Line Markdown Rendering

    @ViewBuilder
    private func markdownLinesView(for text: String) -> some View {
        let lines = text.components(separatedBy: "\n")

        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.isEmpty {
                    Spacer().frame(height: 4)
                } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                    Divider()
                } else if trimmed.hasPrefix("#") {
                    headerView(trimmed)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    bulletView(String(trimmed.dropFirst(2)))
                } else if isNumberedListLine(trimmed) {
                    numberedView(trimmed)
                } else {
                    Text(inlineMarkdown(trimmed))
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func headerView(_ line: String) -> some View {
        let parsed = parseHeaderLine(line)
        if !parsed.content.isEmpty {
            Text(inlineMarkdown(parsed.content))
                .font(headerFont(for: parsed.level))
                .fontWeight(.semibold)
                .textSelection(.enabled)
                .padding(.top, 2)
        }
    }

    private func parseHeaderLine(_ line: String) -> (level: Int, content: String) {
        var level = 0
        for char in line {
            if char == "#" { level += 1 } else { break }
        }
        let content = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        return (level, content)
    }

    private func headerFont(for level: Int) -> Font {
        switch level {
        case 1: .title2
        case 2: .title3
        default: .headline
        }
    }

    @ViewBuilder
    private func bulletView(_ content: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\u{2022}")
                .foregroundStyle(.secondary)
            Text(inlineMarkdown(content))
                .textSelection(.enabled)
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func numberedView(_ line: String) -> some View {
        if let dotIndex = line.firstIndex(of: ".") {
            let number = String(line[line.startIndex..<dotIndex])
            let rest = String(line[line.index(after: dotIndex)...])
                .trimmingCharacters(in: .whitespaces)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(inlineMarkdown(rest))
                    .textSelection(.enabled)
            }
            .padding(.leading, 4)
        }
    }

    private func isNumberedListLine(_ line: String) -> Bool {
        guard let dotIndex = line.firstIndex(of: ".") else { return false }
        let prefix = line[line.startIndex..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return false }
        let afterDot = line.index(after: dotIndex)
        return afterDot < line.endIndex && line[afterDot] == " "
    }

    // MARK: - Content Parsing (code fences vs text)

    private enum ContentBlock {
        case text(String)
        case code(String, String?)
    }

    /// Splits content into text blocks and code blocks (``` fenced)
    private func parseContent(_ content: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        let lines = content.components(separatedBy: "\n")
        var textLines: [String] = []
        var inCodeBlock = false
        var codeLines: [String] = []
        var codeLanguage: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if !inCodeBlock && trimmed.hasPrefix("```") {
                // Flush accumulated text
                let text = textLines.joined(separator: "\n")
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.text(text))
                }
                textLines = []

                // Enter code block, extract language hint
                let afterFence = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)
                codeLanguage = afterFence.isEmpty ? nil : afterFence
                codeLines = []
                inCodeBlock = true
            } else if inCodeBlock && trimmed.hasPrefix("```") {
                // Close code block
                let code = codeLines.joined(separator: "\n")
                    .trimmingCharacters(in: .newlines)
                blocks.append(.code(code, codeLanguage))
                codeLines = []
                codeLanguage = nil
                inCodeBlock = false
            } else if inCodeBlock {
                codeLines.append(line)
            } else {
                textLines.append(line)
            }
        }

        // Flush remaining
        if inCodeBlock {
            // Unclosed code block (streaming in progress)
            let code = codeLines.joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            blocks.append(.code(code, codeLanguage))
        } else {
            let text = textLines.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.text(text))
            }
        }

        return blocks
    }

    // MARK: - Inline Markdown

    private static var markdownCache: [String: AttributedString] = [:]
    private static let maxCacheSize = 50

    private func inlineMarkdown(_ text: String) -> AttributedString {
        if let cached = Self.markdownCache[text] {
            return cached
        }
        let result: AttributedString
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            result = attributed
        } else {
            result = AttributedString(text)
        }
        if Self.markdownCache.count >= Self.maxCacheSize {
            Self.markdownCache.removeAll()
        }
        Self.markdownCache[text] = result
        return result
    }
}

// MARK: - Typing Indicator

/// Animated three-dot typing indicator (pill-shaped bubble)
private struct TypingIndicatorView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .offset(y: animating ? -3 : 0)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .frame(height: 20)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .separatorColor).opacity(0.2))
        .clipShape(Capsule())
        .onAppear { animating = true }
    }
}
