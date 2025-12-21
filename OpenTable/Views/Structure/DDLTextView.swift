//
//  DDLTextView.swift
//  OpenTable
//
//  AppKit-based text view for displaying DDL with syntax highlighting
//

import SwiftUI
import AppKit

/// AppKit-based text view with SQL syntax highlighting for DDL display
struct DDLTextView: NSViewRepresentable {
    let ddl: String
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        // Configure text view
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.labelColor
        
        // Enable line wrapping
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        
        // Apply syntax highlighting
        applySyntaxHighlighting(to: textView, ddl: ddl)
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        // Only update if DDL changed
        if textView.string != ddl {
            applySyntaxHighlighting(to: textView, ddl: ddl)
        }
    }
    
    /// Apply SQL syntax highlighting to the text view
    private func applySyntaxHighlighting(to textView: NSTextView, ddl: String) {
        let attributedString = NSMutableAttributedString(string: ddl)
        let fullRange = NSRange(location: 0, length: attributedString.length)
        
        // Base font and color
        attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: fullRange)
        attributedString.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        
        // SQL Keywords (blue)
        let keywords = [
            "CREATE", "TABLE", "PRIMARY", "KEY", "FOREIGN", "REFERENCES",
            "NOT", "NULL", "DEFAULT", "UNIQUE", "INDEX", "AUTO_INCREMENT",
            "ON", "DELETE", "UPDATE", "CASCADE", "RESTRICT", "SET", "ACTION",
            "CONSTRAINT", "CHECK", "ALTER", "ADD", "DROP", "COLUMN",
            "INT", "INTEGER", "VARCHAR", "CHAR", "TEXT", "BLOB", "DATE",
            "TIMESTAMP", "DATETIME", "BOOLEAN", "DECIMAL", "FLOAT", "DOUBLE",
            "BIGINT", "SMALLINT", "TINYINT", "MEDIUMINT", "SERIAL", "BIGSERIAL",
            "UNSIGNED", "SIGNED", "ZEROFILL", "COMMENT", "ENGINE", "CHARSET",
            "COLLATE", "AS", "GENERATED", "ALWAYS", "STORED", "VIRTUAL"
        ]
        
        for keyword in keywords {
            highlightPattern("\\b\(keyword)\\b", color: .systemBlue, in: attributedString)
        }
        
        // String literals (red)
        highlightPattern("'[^']*'", color: .systemRed, in: attributedString)
        highlightPattern("\"[^\"]*\"", color: .systemRed, in: attributedString)
        
        // Numbers (purple)
        highlightPattern("\\b\\d+\\b", color: .systemPurple, in: attributedString)
        
        // Comments (green)
        highlightPattern("--[^\n]*", color: .systemGreen, in: attributedString)
        highlightPattern("/\\*[^*]*\\*/", color: .systemGreen, in: attributedString)
        
        // Apply to text view
        textView.textStorage?.setAttributedString(attributedString)
    }
    
    /// Highlight all matches of a regex pattern with the specified color
    private func highlightPattern(_ pattern: String, color: NSColor, in attributedString: NSMutableAttributedString) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return
        }
        
        let range = NSRange(location: 0, length: attributedString.length)
        let matches = regex.matches(in: attributedString.string, options: [], range: range)
        
        for match in matches {
            attributedString.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}

#Preview {
    DDLTextView(ddl: """
        CREATE TABLE `users` (
          `id` int(11) NOT NULL AUTO_INCREMENT,
          `email` varchar(255) NOT NULL,
          `name` varchar(100) DEFAULT NULL,
          `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `email_unique` (`email`),
          KEY `idx_created_at` (`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        """)
        .frame(width: 600, height: 400)
}
