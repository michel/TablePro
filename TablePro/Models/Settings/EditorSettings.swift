//
//  EditorSettings.swift
//  TablePro
//

import AppKit
import Foundation

/// Available monospace fonts for the SQL editor
enum EditorFont: String, Codable, CaseIterable, Identifiable {
    case systemMono = "System Mono"
    case sfMono = "SF Mono"
    case menlo = "Menlo"
    case monaco = "Monaco"
    case courierNew = "Courier New"

    var id: String { rawValue }

    var displayName: String { rawValue }

    /// Get the actual NSFont for this option
    func font(size: CGFloat) -> NSFont {
        switch self {
        case .systemMono:
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .sfMono:
            return NSFont(name: "SFMono-Regular", size: size)
                ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .menlo:
            return NSFont(name: "Menlo", size: size)
                ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .monaco:
            return NSFont(name: "Monaco", size: size)
                ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .courierNew:
            return NSFont(name: "Courier New", size: size)
                ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    /// Check if this font is available on the system
    var isAvailable: Bool {
        switch self {
        case .systemMono:
            return true
        case .sfMono:
            return NSFont(name: "SFMono-Regular", size: 12) != nil
        case .menlo:
            return NSFont(name: "Menlo", size: 12) != nil
        case .monaco:
            return NSFont(name: "Monaco", size: 12) != nil
        case .courierNew:
            return NSFont(name: "Courier New", size: 12) != nil
        }
    }
}

/// Editor settings
struct EditorSettings: Codable, Equatable {
    var showLineNumbers: Bool
    var highlightCurrentLine: Bool
    var tabWidth: Int // 2, 4, or 8 spaces
    var autoIndent: Bool
    var wordWrap: Bool
    var vimModeEnabled: Bool

    static let `default` = EditorSettings(
        showLineNumbers: true,
        highlightCurrentLine: true,
        tabWidth: 4,
        autoIndent: true,
        wordWrap: false,
        vimModeEnabled: false
    )

    init(
        showLineNumbers: Bool = true,
        highlightCurrentLine: Bool = true,
        tabWidth: Int = 4,
        autoIndent: Bool = true,
        wordWrap: Bool = false,
        vimModeEnabled: Bool = false
    ) {
        self.showLineNumbers = showLineNumbers
        self.highlightCurrentLine = highlightCurrentLine
        self.tabWidth = tabWidth
        self.autoIndent = autoIndent
        self.wordWrap = wordWrap
        self.vimModeEnabled = vimModeEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Old fontFamily/fontSize keys are ignored (moved to ThemeFonts)
        showLineNumbers = try container.decodeIfPresent(Bool.self, forKey: .showLineNumbers) ?? true
        highlightCurrentLine = try container.decodeIfPresent(Bool.self, forKey: .highlightCurrentLine) ?? true
        tabWidth = try container.decodeIfPresent(Int.self, forKey: .tabWidth) ?? 4
        autoIndent = try container.decodeIfPresent(Bool.self, forKey: .autoIndent) ?? true
        wordWrap = try container.decodeIfPresent(Bool.self, forKey: .wordWrap) ?? false
        vimModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .vimModeEnabled) ?? false
    }

    /// Clamped tab width (1-16)
    var clampedTabWidth: Int {
        min(max(tabWidth, 1), 16)
    }
}
