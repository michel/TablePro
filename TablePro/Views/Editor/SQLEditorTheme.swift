//
//  SQLEditorTheme.swift
//  TablePro
//
//  Centralized theme constants for the SQL editor.
//  User-configurable values are cached and updated via reloadFromSettings().
//

import AppKit

/// Centralized theme configuration for the SQL editor
struct SQLEditorTheme {
    // MARK: - Cached Settings (Thread-Safe)

    /// Cached font from settings - call reloadFromSettings() on main thread to update
    private(set) static var font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    /// Cached line number font - call reloadFromSettings() on main thread to update
    private(set) static var lineNumberFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    /// Cached line highlight enabled flag
    private(set) static var highlightCurrentLine = true

    /// Cached show line numbers flag
    private(set) static var showLineNumbers = true

    /// Cached tab width setting
    private(set) static var tabWidth = 4

    /// Cached auto-indent setting
    private(set) static var autoIndent = true

    /// Cached word wrap setting
    private(set) static var wordWrap = false

    /// Reload settings from provided EditorSettings. Must be called on main thread.
    @MainActor
    static func reloadFromSettings(_ settings: EditorSettings) {
        font = settings.fontFamily.font(size: CGFloat(settings.clampedFontSize))
        let lineNumberSize = max(CGFloat(settings.clampedFontSize) - 2, 9)
        lineNumberFont = NSFont.monospacedSystemFont(ofSize: lineNumberSize, weight: .regular)
        highlightCurrentLine = settings.highlightCurrentLine
        showLineNumbers = settings.showLineNumbers
        tabWidth = settings.clampedTabWidth
        autoIndent = settings.autoIndent
        wordWrap = settings.wordWrap
    }

    // MARK: - Colors

    /// Background color for the editor
    static let background = NSColor.textBackgroundColor

    /// Default text color
    static let text = NSColor.textColor

    /// Current line highlight color (respects cached setting)
    static var currentLineHighlight: NSColor {
        if highlightCurrentLine {
            return NSColor.controlAccentColor.withAlphaComponent(0.08)
        } else {
            return .clear
        }
    }

    /// Insertion point (cursor) color
    static let insertionPoint = NSColor.controlAccentColor

    // MARK: - Syntax Highlighting Colors

    /// SQL keywords (SELECT, FROM, WHERE, etc.)
    static let keyword = NSColor.systemBlue

    /// String literals ('...', "...", `...`)
    static let string = NSColor.systemRed

    /// Numeric literals
    static let number = NSColor.systemPurple

    /// Comments (-- and /* */)
    static let comment = NSColor.systemGreen

    /// NULL, TRUE, FALSE
    static let null = NSColor.systemOrange
}
