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
    @Binding var fontSize: CGFloat
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        // Configure text view
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 50 + 16, height: 16) // Left padding for line numbers
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.labelColor
        
        // Disable line wrapping for better code view
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        
        // Set text FIRST (most important!)
        textView.string = ddl
        
        // THEN apply syntax highlighting
        applySyntaxHighlighting(to: textView, fontSize: fontSize)
        
        // Finally add line numbers
        addLineNumbersRuler(to: scrollView, textView: textView)
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        // Update font size if changed
        if let currentFont = textView.font, currentFont.pointSize != fontSize {
            textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            applySyntaxHighlighting(to: textView, fontSize: fontSize)
        }
        
        // Update text if changed
        if textView.string != ddl {
            textView.string = ddl
            applySyntaxHighlighting(to: textView, fontSize: fontSize)
            
            // Add line numbers if not present
            if scrollView.verticalRulerView == nil {
                addLineNumbersRuler(to: scrollView, textView: textView)
            }
        }
        
        // Refresh line numbers
        scrollView.verticalRulerView?.needsDisplay = true
    }
    
    /// Add line numbers ruler view to the scroll view
    private func addLineNumbersRuler(to scrollView: NSScrollView, textView: NSTextView) {
        // Only add if we have content
        guard !textView.string.isEmpty else { return }
        
        let rulerView = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = rulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
    }
    
    /// Apply SQL syntax highlighting to the text view (on existing text)
    private func applySyntaxHighlighting(to textView: NSTextView, fontSize: CGFloat) {
        guard let textStorage = textView.textStorage else { return }
        
        let fullRange = NSRange(location: 0, length: textStorage.length)
        
        // Base font and color
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textStorage.addAttribute(.font, value: font, range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        
        // Enhanced SQL Keywords with better dark mode colors
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
        
        // Use brighter colors for dark mode
        let keywordColor = NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1.0) // Bright blue
        let stringColor = NSColor(calibratedRed: 1.0, green: 0.4, blue: 0.4, alpha: 1.0) // Bright red
        let numberColor = NSColor(calibratedRed: 0.8, green: 0.5, blue: 1.0, alpha: 1.0) // Bright purple
        let commentColor = NSColor(calibratedRed: 0.4, green: 0.8, blue: 0.4, alpha: 1.0) // Bright green
        
        for keyword in keywords {
            highlightPattern("\\b\\(keyword)\\b", color: keywordColor, in: textStorage)
        }
        
        // String literals
        highlightPattern("'[^']*'", color: stringColor, in: textStorage)
        highlightPattern("\"[^\"]*\"", color: stringColor, in: textStorage)
        
        // Backtick-quoted identifiers (MySQL style)
        highlightPattern("`[^`]*`", color: NSColor.systemOrange, in: textStorage)
        
        // Numbers
        highlightPattern("\\b\\d+\\b", color: numberColor, in: textStorage)
        
        // Comments
        highlightPattern("--[^\n]*", color: commentColor, in: textStorage)
        highlightPattern("/\\*[^*]*\\*/", color: commentColor, in: textStorage)
    }
    
    /// Highlight all matches of a regex pattern with the specified color
    private func highlightPattern(_ pattern: String, color: NSColor, in textStorage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return
        }
        
        let range = NSRange(location: 0, length: textStorage.length)
        let matches = regex.matches(in: textStorage.string, options: [], range: range)
        
        for match in matches {
            textStorage.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}

/// Custom NSRulerView for displaying line numbers
class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    
    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        
        self.clientView = textView
        self.ruleThickness = 50
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }
        
        // Background
        NSColor.controlBackgroundColor.setFill()
        rect.fill()
        
        // Right border
        NSColor.separatorColor.setStroke()
        let borderPath = NSBezierPath()
        borderPath.move(to: NSPoint(x: rect.maxX - 0.5, y: rect.minY))
        borderPath.line(to: NSPoint(x: rect.maxX - 0.5, y: rect.maxY))
        borderPath.lineWidth = 1
        borderPath.stroke()
        
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        
        let text = textView.string as NSString
        var lineNumber = 1
        var index = 0
        
        // Count line number for first visible character
        if charRange.location > 0 {
            let textBeforeVisible = text.substring(to: charRange.location)
            lineNumber = textBeforeVisible.components(separatedBy: "\n").count
        }
        
        // Draw line numbers
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]
        
        while index < charRange.length {
            let lineRange = text.lineRange(for: NSRange(location: charRange.location + index, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            
            let yPosition = lineRect.minY + textView.textContainerInset.height - visibleRect.minY
            
            let numberRect = NSRect(
                x: 5,
                y: yPosition,
                width: ruleThickness - 10,
                height: lineRect.height
            )
            
            "\(lineNumber)".draw(in: numberRect, withAttributes: attrs)
            
            lineNumber += 1
            index += lineRange.length
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var fontSize: CGFloat = 13
        
        var body: some View {
            DDLTextView(
                ddl: """
                CREATE TABLE `users` (
                  `id` int(11) NOT NULL AUTO_INCREMENT,
                  `email` varchar(255) NOT NULL,
                  `name` varchar(100) DEFAULT NULL,
                  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
                  PRIMARY KEY (`id`),
                  UNIQUE KEY `email_unique` (`email`),
                  KEY `idx_created_at` (`created_at`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
                """,
                fontSize: $fontSize
            )
            .frame(width: 600, height: 400)
        }
    }
    
    return PreviewWrapper()
}
