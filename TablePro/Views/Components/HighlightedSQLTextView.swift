//
//  HighlightedSQLTextView.swift
//  TablePro
//
//  Read-only NSTextView with regex-based SQL syntax highlighting.
//  Used for query previews in the history panel.
//

import AppKit
import SwiftUI

/// Read-only text view that applies SQL syntax highlighting via regex
struct HighlightedSQLTextView: NSViewRepresentable {
    let sql: String
    var fontSize: CGFloat = 13

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        // Configure text view
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.labelColor

        // Disable line wrapping
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = true

        // Set text and highlight
        textView.string = sql
        if !sql.isEmpty {
            applyHighlighting(to: textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Update font if changed
        if let currentFont = textView.font, currentFont.pointSize != fontSize {
            textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            if !textView.string.isEmpty {
                applyHighlighting(to: textView)
            }
        }

        // Update text if changed
        if textView.string != sql {
            textView.string = sql
            if !sql.isEmpty {
                applyHighlighting(to: textView)
            }
        }
    }

    // MARK: - Syntax Highlighting

    private func applyHighlighting(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        guard textStorage.length > 0 else { return }

        let fullRange = NSRange(location: 0, length: textStorage.length)

        // Reset to base style
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textStorage.addAttribute(.font, value: font, range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

        // SQL Keywords (blue)
        let keywords = [
            "CREATE", "TABLE", "PRIMARY", "KEY", "FOREIGN", "REFERENCES",
            "NOT", "NULL", "DEFAULT", "UNIQUE", "INDEX", "AUTO_INCREMENT",
            "ON", "DELETE", "UPDATE", "CASCADE", "RESTRICT", "SET",
            "INT", "INTEGER", "VARCHAR", "CHAR", "TEXT", "TIMESTAMP", "DATETIME",
            "SELECT", "FROM", "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER",
            "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET", "INSERT", "INTO",
            "VALUES", "DROP", "ALTER", "ADD", "COLUMN", "IF", "EXISTS", "AS",
            "AND", "OR", "IN", "LIKE", "BETWEEN", "IS", "DISTINCT", "COUNT",
            "SUM", "AVG", "MIN", "MAX", "CASE", "WHEN", "THEN", "ELSE", "END",
            "UNION", "ALL", "WITH", "RECURSIVE"
        ]

        for keyword in keywords {
            highlightPattern("\\b\(keyword)\\b", color: .systemBlue, in: textStorage)
        }

        // Strings (red)
        highlightPattern("'[^']*'", color: .systemRed, in: textStorage)

        // Backticks (orange)
        highlightPattern("`[^`]*`", color: .systemOrange, in: textStorage)

        // Numbers (purple)
        highlightPattern("\\b\\d+\\b", color: .systemPurple, in: textStorage)
    }

    private func highlightPattern(_ pattern: String, color: NSColor, in textStorage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }

        let range = NSRange(location: 0, length: textStorage.length)
        let matches = regex.matches(in: textStorage.string, options: [], range: range)

        for match in matches {
            textStorage.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
