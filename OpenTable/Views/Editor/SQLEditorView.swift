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

        // Line numbers DISABLED - they break text rendering
        // scrollView.hasVerticalRuler = true
        // scrollView.rulersVisible = true
        // let rulerView = LineNumberRulerView(textView: textView)
        // scrollView.verticalRulerView = rulerView

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
        
        // Keywords
        let pattern = "\\b(" + Self.keywords.joined(separator: "|") + ")\\b"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let m = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: SQLEditorTheme.keyword, range: m)
                }
            }
        }
        
        // Strings
        for p in ["'[^']*'", "\"[^\"]*\"", "`[^`]*`"] {
            if let regex = try? NSRegularExpression(pattern: p) {
                regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                    if let m = match?.range {
                        textStorage.addAttribute(.foregroundColor, value: SQLEditorTheme.string, range: m)
                    }
                }
            }
        }
        
        // Numbers
        if let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b") {
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let m = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: SQLEditorTheme.number, range: m)
                }
            }
        }
        
        // Comments
        for p in ["--[^\n]*", "/\\*[\\s\\S]*?\\*/"] {
            if let regex = try? NSRegularExpression(pattern: p) {
                regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                    if let m = match?.range {
                        textStorage.addAttribute(.foregroundColor, value: SQLEditorTheme.comment, range: m)
                    }
                }
            }
        }
        
        // NULL, TRUE, FALSE
        if let regex = try? NSRegularExpression(pattern: "\\b(NULL|TRUE|FALSE)\\b", options: .caseInsensitive) {
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let m = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: SQLEditorTheme.null, range: m)
                }
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

// MARK: - SQLTextStorage

final class SQLTextStorage: NSTextStorage {
    private let store = NSMutableAttributedString()
    
    private static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "LIKE", "BETWEEN",
        "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "INSERT", "INTO",
        "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "DROP", "ALTER", "TABLE",
        "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET", "AS", "DISTINCT",
        "COUNT", "SUM", "AVG", "MIN", "MAX", "ASC", "DESC", "CASE", "WHEN",
        "THEN", "ELSE", "END", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "UNIQUE"
    ]
    
    override var string: String { store.string }
    
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        store.attributes(at: location, effectiveRange: range)
    }
    
    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        store.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.count - range.length)
        endEditing()
    }
    
    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        store.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }
    
    override func processEditing() {
        let range = (string as NSString).paragraphRange(for: editedRange)
        applyHighlighting(in: range)
        super.processEditing()
    }
    
    func applyHighlighting(in range: NSRange? = nil) {
        let r = range ?? NSRange(location: 0, length: length)
        guard r.length > 0 else { return }
        
        // Reset to default
        store.addAttributes([.font: SQLEditorTheme.font, .foregroundColor: NSColor.black], range: r)
        
        // Keywords
        let pattern = "\\b(" + Self.keywords.joined(separator: "|") + ")\\b"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            regex.enumerateMatches(in: string, range: r) { match, _, _ in
                if let m = match?.range {
                    store.addAttribute(.foregroundColor, value: SQLEditorTheme.keyword, range: m)
                }
            }
        }
        
        // Strings
        for p in ["'[^']*'", "\"[^\"]*\"", "`[^`]*`"] {
            if let regex = try? NSRegularExpression(pattern: p) {
                regex.enumerateMatches(in: string, range: r) { match, _, _ in
                    if let m = match?.range {
                        store.addAttribute(.foregroundColor, value: SQLEditorTheme.string, range: m)
                    }
                }
            }
        }
        
        // Numbers
        if let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b") {
            regex.enumerateMatches(in: string, range: r) { match, _, _ in
                if let m = match?.range {
                    store.addAttribute(.foregroundColor, value: SQLEditorTheme.number, range: m)
                }
            }
        }
        
        // Comments
        for p in ["--[^\n]*", "/\\*[\\s\\S]*?\\*/"] {
            if let regex = try? NSRegularExpression(pattern: p) {
                regex.enumerateMatches(in: string, range: r) { match, _, _ in
                    if let m = match?.range {
                        store.addAttribute(.foregroundColor, value: SQLEditorTheme.comment, range: m)
                    }
                }
            }
        }
        
        // NULL, TRUE, FALSE
        if let regex = try? NSRegularExpression(pattern: "\\b(NULL|TRUE|FALSE)\\b", options: .caseInsensitive) {
            regex.enumerateMatches(in: string, range: r) { match, _, _ in
                if let m = match?.range {
                    store.addAttribute(.foregroundColor, value: SQLEditorTheme.null, range: m)
                }
            }
        }
    }
}

// MARK: - LineNumberRulerView

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    
    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        ruleThickness = 40
        clientView = textView
        
        NotificationCenter.default.addObserver(self, selector: #selector(needsRedraw),
                                               name: NSText.didChangeNotification, object: textView)
        textView.enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(needsRedraw),
                                               name: NSView.boundsDidChangeNotification,
                                               object: textView.enclosingScrollView?.contentView)
    }
    
    required init(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }
    
    @objc private func needsRedraw() { needsDisplay = true }
    
    override func drawHashMarksAndLabels(in rect: NSRect) {
        SQLEditorTheme.background.setFill()
        rect.fill()
        
        NSColor.separatorColor.setStroke()
        NSBezierPath.strokeLine(from: NSPoint(x: bounds.maxX - 0.5, y: rect.minY),
                                to: NSPoint(x: bounds.maxX - 0.5, y: rect.maxY))
        
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        
        let text = textView.string as NSString
        var lineNum = 1
        text.enumerateSubstrings(in: NSRange(location: 0, length: charRange.location),
                                  options: [.byLines, .substringNotRequired]) { _, _, _, _ in lineNum += 1 }
        
        var idx = charRange.location
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let color = NSColor.secondaryLabelColor
        
        while idx < min(charRange.upperBound, text.length) {
            let lineRange = text.lineRange(for: NSRange(location: idx, length: 0))
            let glyph = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            lineRect.origin.y -= visibleRect.origin.y
            
            let s = "\(lineNum)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: ruleThickness - size.width - 8,
                              y: lineRect.midY - size.height / 2), withAttributes: attrs)
            
            lineNum += 1
            idx = NSMaxRange(lineRange)
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
