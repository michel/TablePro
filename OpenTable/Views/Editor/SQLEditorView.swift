//
//  SQLEditorView.swift
//  OpenTable
//
//  Production-quality SQL editor using AppKit NSTextView
//

import SwiftUI
import AppKit

// MARK: - Theme

/// Editor theme with proper system colors
struct SQLEditorTheme {
    // Use standard text field colors - these work correctly in both modes
    static let background = NSColor.controlBackgroundColor
    static let text = NSColor.controlTextColor
    
    // Syntax colors
    static let keyword = NSColor.systemBlue
    static let string = NSColor.systemRed
    static let number = NSColor.systemPurple
    static let comment = NSColor.systemGreen
    static let null = NSColor.systemOrange
    
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .vibrantDark]) != nil
    }
}

// MARK: - SQLEditorView

struct SQLEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: Int  // Track cursor for query-at-cursor execution
    var onExecute: (() -> Void)?
    var schemaProvider: SQLSchemaProvider?  // Optional for autocomplete
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        // MUST use frame: initializer, NOT NSTextView()
        let textView = CompletionTextView(frame: .zero)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 5

        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = SQLEditorTheme.font
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.drawsBackground = true
        textView.insertionPointColor = NSColor.controlAccentColor

        textView.string = text
        textView.delegate = context.coordinator
        textView.completionCoordinator = context.coordinator

        // MUST set documentView BEFORE setting up ruler
        scrollView.documentView = textView

        context.coordinator.textView = textView
        
        // Apply initial syntax highlighting
        applySyntaxHighlighting(to: textView)
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else { return }
        textView.string = text
        applySyntaxHighlighting(to: textView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, cursorPosition: $cursorPosition, onExecute: onExecute, schemaProvider: schemaProvider, highlighter: applySyntaxHighlighting)
    }
    
    // MARK: - Syntax Highlighting
    
    private static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "LIKE", "BETWEEN",
        "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "INSERT", "INTO",
        "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "DROP", "ALTER", "TABLE",
        "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET", "AS", "DISTINCT",
        "COUNT", "SUM", "AVG", "MIN", "MAX", "ASC", "DESC", "CASE", "WHEN",
        "THEN", "ELSE", "END", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "UNIQUE"
    ]
    
    // MARK: - Cached Regex Patterns (compiled once for performance)
    
    private static let keywordRegex: NSRegularExpression? = {
        let pattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
        return try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()
    
    private static let stringRegexes: [NSRegularExpression] = {
        ["'[^']*'", "\"[^\"]*\"", "`[^`]*`"].compactMap { try? NSRegularExpression(pattern: $0) }
    }()
    
    private static let numberRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b")
    }()
    
    private static let commentRegexes: [NSRegularExpression] = {
        ["--[^\n]*", "/\\*[\\s\\S]*?\\*/"].compactMap { try? NSRegularExpression(pattern: $0) }
    }()
    
    private static let nullBoolRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\b(NULL|TRUE|FALSE)\\b", options: .caseInsensitive)
    }()
    
    private func applySyntaxHighlighting(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let text = textView.string
        let fullRange = NSRange(location: 0, length: text.count)
        guard fullRange.length > 0 else { return }
        
        // Preserve selection
        let selectedRanges = textView.selectedRanges
        
        textStorage.beginEditing()
        
        // Reset to default
        textStorage.addAttributes([
            .font: SQLEditorTheme.font,
            .foregroundColor: NSColor.textColor
        ], range: fullRange)
        
        // Keywords (using cached regex)
        Self.keywordRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let m = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SQLEditorTheme.keyword, range: m)
            }
        }
        
        // Strings (using cached regexes)
        for regex in Self.stringRegexes {
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let m = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: SQLEditorTheme.string, range: m)
                }
            }
        }
        
        // Numbers (using cached regex)
        Self.numberRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let m = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SQLEditorTheme.number, range: m)
            }
        }
        
        // Comments (using cached regexes)
        for regex in Self.commentRegexes {
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let m = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: SQLEditorTheme.comment, range: m)
                }
            }
        }
        
        // NULL, TRUE, FALSE (using cached regex)
        Self.nullBoolRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let m = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SQLEditorTheme.null, range: m)
            }
        }
        
        textStorage.endEditing()
        
        // Restore selection
        textView.selectedRanges = selectedRanges
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onExecute: (() -> Void)?
        weak var textView: NSTextView?
        var highlighter: ((NSTextView) -> Void)?
        
        // Autocomplete
        private var schemaProvider: SQLSchemaProvider?
        private var completionProvider: SQLCompletionProvider?
        private let completionWindow = SQLCompletionWindowController()
        private var completionDebounceTask: Task<Void, Never>?
        private var currentContext: SQLContext?
        private var suppressNextCompletion: Bool = false  // Prevent loop after inserting completion
        @Binding var cursorPosition: Int  // Track cursor position for query-at-cursor
        
        init(text: Binding<String>, cursorPosition: Binding<Int>, onExecute: (() -> Void)?, schemaProvider: SQLSchemaProvider?, highlighter: @escaping (NSTextView) -> Void) {
            _text = text
            _cursorPosition = cursorPosition
            self.onExecute = onExecute
            self.schemaProvider = schemaProvider
            self.highlighter = highlighter
            
            super.init()
            
            if let provider = schemaProvider {
                self.completionProvider = SQLCompletionProvider(schemaProvider: provider)
            }
            
            // Set up completion callbacks
            completionWindow.onSelect = { [weak self] item in
                self?.insertCompletion(item)
            }
        }
        
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string
            cursorPosition = tv.selectedRange().location  // Update cursor position
            highlighter?(tv)
            
            // Trigger autocomplete with debounce
            triggerCompletionDebounced()
        }
        
        // Track selection changes for cursor position
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            cursorPosition = tv.selectedRange().location
        }
        
        // MARK: - Autocomplete
        
        private func triggerCompletionDebounced() {
            // Skip if we just inserted a completion
            if suppressNextCompletion {
                suppressNextCompletion = false
                return
            }
            
            completionDebounceTask?.cancel()
            completionDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000) // 150ms debounce
                guard !Task.isCancelled else { return }
                await self.showCompletions()
            }
        }
        
        func triggerCompletionManually() {
            Task { @MainActor in
                await showCompletions()
            }
        }
        
        @MainActor
        private func showCompletions() async {
            guard let textView = textView,
                  let completionProvider = completionProvider else { return }
            
            let cursorPosition = textView.selectedRange().location
            let text = textView.string
            
            // Don't show autocomplete right after semicolon (end of statement)
            if cursorPosition > 0 {
                let prevIndex = text.index(text.startIndex, offsetBy: cursorPosition - 1)
                let prevChar = text[prevIndex]
                if prevChar == ";" || prevChar == "\n" {
                    // Check if we're at the very end or just after semicolon/newline with no new content
                    let afterCursor = String(text[text.index(text.startIndex, offsetBy: cursorPosition)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if afterCursor.isEmpty || cursorPosition == text.count {
                        completionWindow.dismiss()
                        return
                    }
                }
            }
            
            let (items, context) = await completionProvider.getCompletions(
                text: text,
                cursorPosition: cursorPosition
            )
            
            self.currentContext = context
            
            // Show completions if we have items
            // Allow empty prefix for context-aware suggestions (e.g., columns after SELECT)
            guard !items.isEmpty else {
                completionWindow.dismiss()
                return
            }
            
            // Get cursor screen position with safe bounds checking
            guard let layoutManager = textView.layoutManager,
                  let _ = textView.textContainer,
                  text.count > 0 else { return }
            
            // Ensure cursor position is valid
            let safePosition = min(max(0, cursorPosition), text.count)
            
            // Ensure layout is up to date
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: text.count))
            
            // Get glyph count safely
            let glyphCount = layoutManager.numberOfGlyphs
            guard glyphCount > 0 else { return }
            
            // Safe glyph index calculation
            let charIndex = min(safePosition, text.count - 1)
            let glyphIndex = min(layoutManager.glyphIndexForCharacter(at: max(0, charIndex)), glyphCount - 1)
            
            // Get line rect safely
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            
            // Get glyph location within line
            if glyphIndex < glyphCount {
                let glyphPoint = layoutManager.location(forGlyphAt: glyphIndex)
                lineRect.origin.x += glyphPoint.x
            }
            
            let textContainerOrigin = textView.textContainerOrigin
            lineRect.origin.x += textContainerOrigin.x
            lineRect.origin.y += textContainerOrigin.y + lineRect.height
            
            // Convert to screen coordinates
            let windowPoint = textView.convert(lineRect.origin, to: nil)
            guard let screenPoint = textView.window?.convertPoint(toScreen: windowPoint) else { return }
            
            completionWindow.showCompletions(items, at: screenPoint, relativeTo: textView.window)
        }
        
        private func insertCompletion(_ item: SQLCompletionItem) {
            guard let textView = textView,
                  let context = currentContext else { return }
            
            // Calculate range to replace
            let insertText = item.insertText
            let replaceStart = context.prefixRange.lowerBound
            let replaceEnd = context.prefixRange.upperBound
            let replaceRange = NSRange(location: replaceStart, length: replaceEnd - replaceStart)
            
            // Suppress next autocomplete trigger to prevent loop
            suppressNextCompletion = true
            
            // Insert the completion
            if textView.shouldChangeText(in: replaceRange, replacementString: insertText) {
                textView.replaceCharacters(in: replaceRange, with: insertText)
                textView.didChangeText()
            }
        }
        
        /// Handle key events for completion navigation
        func handleKeyDown(_ event: NSEvent) -> Bool {
            // Ctrl+Space to trigger completion
            if event.modifierFlags.contains(.control) && event.keyCode == 49 {
                triggerCompletionManually()
                return true
            }
            
            // Let completion window handle arrow keys, return, escape
            return completionWindow.handleKeyEvent(event)
        }
        
        /// Dismiss completion window
        func dismissCompletion() {
            completionWindow.dismiss()
        }
    }
}

// MARK: - CompletionTextView

/// NSTextView subclass that intercepts key events for autocomplete
final class CompletionTextView: NSTextView {
    weak var completionCoordinator: SQLEditorView.Coordinator?
    
    override func keyDown(with event: NSEvent) {
        // Let coordinator handle completion-related keys first
        if let coordinator = completionCoordinator,
           coordinator.handleKeyDown(event) {
            return
        }
        
        // Cmd+Enter to execute query
        if event.modifierFlags.contains(.command) && event.keyCode == 36 {
            completionCoordinator?.onExecute?()
            return
        }
        
        super.keyDown(with: event)
    }
    
    override func resignFirstResponder() -> Bool {
        completionCoordinator?.dismissCompletion()
        return super.resignFirstResponder()
    }
}

#Preview {
    SQLEditorView(text: .constant("SELECT * FROM users\nWHERE active = true;"), cursorPosition: .constant(0))
        .frame(width: 500, height: 200)
}
