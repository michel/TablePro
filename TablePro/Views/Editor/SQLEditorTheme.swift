//
//  SQLEditorTheme.swift
//  TablePro
//
//  Centralized theme constants for the SQL editor.
//  User-configurable values are cached and updated via reloadFromSettings().
//

import AppKit
import os

/// Centralized theme configuration for the SQL editor
struct SQLEditorTheme {
    // MARK: - Cached Settings (Thread-Safe)

    private static let logger = Logger(subsystem: "com.TablePro", category: "SQLEditorTheme")

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

    // MARK: - Accessibility Text Size

    /// The default macOS body font size (13pt). Used as the baseline for computing
    /// the accessibility scale factor from NSFont.preferredFont(forTextStyle:).
    private static let defaultBodyFontSize: CGFloat = 13.0

    /// Scale factor derived from the system's accessibility text size preference
    /// (System Settings > Accessibility > Display > Text Size).
    /// Computed by comparing the preferred body font size to the default 13pt baseline.
    /// Applied as a multiplier on top of the user's configured font size.
    static var accessibilityScaleFactor: CGFloat {
        let preferredBodyFont = NSFont.preferredFont(forTextStyle: .body)
        let scale = preferredBodyFont.pointSize / defaultBodyFontSize
        // Clamp to a reasonable range to prevent extreme sizes
        return min(max(scale, 0.5), 3.0)
    }

    /// Reload settings from provided EditorSettings. Must be called on main thread.
    /// The user's chosen font size is scaled by the system's accessibility text size preference.
    @MainActor
    static func reloadFromSettings(_ settings: EditorSettings) {
        let scale = accessibilityScaleFactor
        let scaledSize = round(CGFloat(settings.clampedFontSize) * scale)
        font = settings.fontFamily.font(size: scaledSize)
        let lineNumberSize = max(round((CGFloat(settings.clampedFontSize) - 2) * scale), 9)
        lineNumberFont = NSFont.monospacedSystemFont(ofSize: lineNumberSize, weight: .regular)
        highlightCurrentLine = settings.highlightCurrentLine
        showLineNumbers = settings.showLineNumbers
        tabWidth = settings.clampedTabWidth
        autoIndent = settings.autoIndent
        wordWrap = settings.wordWrap

        if scale != 1.0 {
            logger.debug("Accessibility scale factor: \(scale, format: .fixed(precision: 2)), effective font size: \(scaledSize)")
        }
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
