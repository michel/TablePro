//
//  ThemeLayout.swift
//  TablePro
//

import Foundation
import SwiftUI
// MARK: - Theme Fonts

internal struct ThemeFonts: Codable, Equatable, Sendable {
    var editorFontFamily: String
    var editorFontSize: Int
    var dataGridFontFamily: String
    var dataGridFontSize: Int

    static let `default` = ThemeFonts(
        editorFontFamily: "System Mono",
        editorFontSize: 13,
        dataGridFontFamily: "System Mono",
        dataGridFontSize: 13
    )

    init(editorFontFamily: String, editorFontSize: Int, dataGridFontFamily: String, dataGridFontSize: Int) {
        self.editorFontFamily = editorFontFamily
        self.editorFontSize = editorFontSize
        self.dataGridFontFamily = dataGridFontFamily
        self.dataGridFontSize = dataGridFontSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ThemeFonts.default

        editorFontFamily = try container.decodeIfPresent(String.self, forKey: .editorFontFamily)
            ?? fallback.editorFontFamily
        editorFontSize = try container.decodeIfPresent(Int.self, forKey: .editorFontSize) ?? fallback.editorFontSize
        dataGridFontFamily = try container.decodeIfPresent(String.self, forKey: .dataGridFontFamily)
            ?? fallback.dataGridFontFamily
        dataGridFontSize = try container.decodeIfPresent(Int.self, forKey: .dataGridFontSize)
            ?? fallback.dataGridFontSize
    }
}

// MARK: - Theme Spacing

internal struct ThemeSpacing: Codable, Equatable, Sendable {
    var xxxs: CGFloat
    var xxs: CGFloat
    var xs: CGFloat
    var sm: CGFloat
    var md: CGFloat
    var lg: CGFloat
    var xl: CGFloat
    var listRowInsets: ThemeEdgeInsets

    static let `default` = ThemeSpacing(
        xxxs: 2, xxs: 4, xs: 8, sm: 12, md: 16, lg: 20, xl: 24,
        listRowInsets: .default
    )

    init(
        xxxs: CGFloat, xxs: CGFloat, xs: CGFloat, sm: CGFloat,
        md: CGFloat, lg: CGFloat, xl: CGFloat, listRowInsets: ThemeEdgeInsets
    ) {
        self.xxxs = xxxs; self.xxs = xxs; self.xs = xs; self.sm = sm
        self.md = md; self.lg = lg; self.xl = xl; self.listRowInsets = listRowInsets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ThemeSpacing.default
        xxxs = try container.decodeIfPresent(CGFloat.self, forKey: .xxxs) ?? fallback.xxxs
        xxs = try container.decodeIfPresent(CGFloat.self, forKey: .xxs) ?? fallback.xxs
        xs = try container.decodeIfPresent(CGFloat.self, forKey: .xs) ?? fallback.xs
        sm = try container.decodeIfPresent(CGFloat.self, forKey: .sm) ?? fallback.sm
        md = try container.decodeIfPresent(CGFloat.self, forKey: .md) ?? fallback.md
        lg = try container.decodeIfPresent(CGFloat.self, forKey: .lg) ?? fallback.lg
        xl = try container.decodeIfPresent(CGFloat.self, forKey: .xl) ?? fallback.xl
        listRowInsets = try container.decodeIfPresent(ThemeEdgeInsets.self, forKey: .listRowInsets) ?? fallback.listRowInsets
    }
}

internal struct ThemeEdgeInsets: Codable, Equatable, Sendable {
    var top: CGFloat
    var leading: CGFloat
    var bottom: CGFloat
    var trailing: CGFloat

    static let `default` = ThemeEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)

    var swiftUI: EdgeInsets { EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing) }
    var appKit: NSEdgeInsets { NSEdgeInsets(top: top, left: leading, bottom: bottom, right: trailing) }

    init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ThemeEdgeInsets.default
        top = try container.decodeIfPresent(CGFloat.self, forKey: .top) ?? fallback.top
        leading = try container.decodeIfPresent(CGFloat.self, forKey: .leading) ?? fallback.leading
        bottom = try container.decodeIfPresent(CGFloat.self, forKey: .bottom) ?? fallback.bottom
        trailing = try container.decodeIfPresent(CGFloat.self, forKey: .trailing) ?? fallback.trailing
    }
}

// MARK: - Theme Typography

internal struct ThemeTypography: Codable, Equatable, Sendable {
    var tiny: CGFloat
    var caption: CGFloat
    var small: CGFloat
    var medium: CGFloat
    var body: CGFloat
    var title3: CGFloat
    var title2: CGFloat

    static let `default` = ThemeTypography(
        tiny: 9, caption: 10, small: 11, medium: 12, body: 13, title3: 15, title2: 17
    )

    init(
        tiny: CGFloat, caption: CGFloat, small: CGFloat, medium: CGFloat,
        body: CGFloat, title3: CGFloat, title2: CGFloat
    ) {
        self.tiny = tiny; self.caption = caption; self.small = small; self.medium = medium
        self.body = body; self.title3 = title3; self.title2 = title2
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ThemeTypography.default
        tiny = try container.decodeIfPresent(CGFloat.self, forKey: .tiny) ?? fallback.tiny
        caption = try container.decodeIfPresent(CGFloat.self, forKey: .caption) ?? fallback.caption
        small = try container.decodeIfPresent(CGFloat.self, forKey: .small) ?? fallback.small
        medium = try container.decodeIfPresent(CGFloat.self, forKey: .medium) ?? fallback.medium
        body = try container.decodeIfPresent(CGFloat.self, forKey: .body) ?? fallback.body
        title3 = try container.decodeIfPresent(CGFloat.self, forKey: .title3) ?? fallback.title3
        title2 = try container.decodeIfPresent(CGFloat.self, forKey: .title2) ?? fallback.title2
    }
}

// MARK: - Theme Icon Sizes

internal struct ThemeIconSizes: Codable, Equatable, Sendable {
    var tinyDot: CGFloat
    var statusDot: CGFloat
    var small: CGFloat
    var `default`: CGFloat
    var medium: CGFloat
    var large: CGFloat
    var extraLarge: CGFloat
    var huge: CGFloat
    var massive: CGFloat

    static let `default` = ThemeIconSizes(
        tinyDot: 6, statusDot: 8, small: 12, default: 14, medium: 16,
        large: 20, extraLarge: 24, huge: 32, massive: 64
    )

    init(
        tinyDot: CGFloat, statusDot: CGFloat, small: CGFloat, `default`: CGFloat,
        medium: CGFloat, large: CGFloat, extraLarge: CGFloat, huge: CGFloat, massive: CGFloat
    ) {
        self.tinyDot = tinyDot; self.statusDot = statusDot; self.small = small
        self.`default` = `default`; self.medium = medium; self.large = large
        self.extraLarge = extraLarge; self.huge = huge; self.massive = massive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ThemeIconSizes.default
        tinyDot = try container.decodeIfPresent(CGFloat.self, forKey: .tinyDot) ?? fallback.tinyDot
        statusDot = try container.decodeIfPresent(CGFloat.self, forKey: .statusDot) ?? fallback.statusDot
        small = try container.decodeIfPresent(CGFloat.self, forKey: .small) ?? fallback.small
        `default` = try container.decodeIfPresent(CGFloat.self, forKey: .default) ?? fallback.default
        medium = try container.decodeIfPresent(CGFloat.self, forKey: .medium) ?? fallback.medium
        large = try container.decodeIfPresent(CGFloat.self, forKey: .large) ?? fallback.large
        extraLarge = try container.decodeIfPresent(CGFloat.self, forKey: .extraLarge) ?? fallback.extraLarge
        huge = try container.decodeIfPresent(CGFloat.self, forKey: .huge) ?? fallback.huge
        massive = try container.decodeIfPresent(CGFloat.self, forKey: .massive) ?? fallback.massive
    }
}

// MARK: - Theme Corner Radius

internal struct ThemeCornerRadius: Codable, Equatable, Sendable {
    var small: CGFloat
    var medium: CGFloat
    var large: CGFloat

    static let `default` = ThemeCornerRadius(small: 4, medium: 6, large: 8)

    init(small: CGFloat, medium: CGFloat, large: CGFloat) {
        self.small = small; self.medium = medium; self.large = large
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ThemeCornerRadius.default
        small = try container.decodeIfPresent(CGFloat.self, forKey: .small) ?? fallback.small
        medium = try container.decodeIfPresent(CGFloat.self, forKey: .medium) ?? fallback.medium
        large = try container.decodeIfPresent(CGFloat.self, forKey: .large) ?? fallback.large
    }
}

// MARK: - Theme Row Heights

internal struct ThemeRowHeights: Codable, Equatable, Sendable {
    var compact: CGFloat
    var table: CGFloat
    var comfortable: CGFloat

    static let `default` = ThemeRowHeights(compact: 24, table: 32, comfortable: 44)

    init(compact: CGFloat, table: CGFloat, comfortable: CGFloat) {
        self.compact = compact; self.table = table; self.comfortable = comfortable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ThemeRowHeights.default
        compact = try container.decodeIfPresent(CGFloat.self, forKey: .compact) ?? fallback.compact
        table = try container.decodeIfPresent(CGFloat.self, forKey: .table) ?? fallback.table
        comfortable = try container.decodeIfPresent(CGFloat.self, forKey: .comfortable) ?? fallback.comfortable
    }
}

// MARK: - Theme Animations

internal struct ThemeAnimations: Codable, Equatable, Sendable {
    var fast: Double
    var normal: Double
    var smooth: Double
    var slow: Double

    static let `default` = ThemeAnimations(fast: 0.1, normal: 0.15, smooth: 0.2, slow: 0.3)

    init(fast: Double, normal: Double, smooth: Double, slow: Double) {
        self.fast = fast; self.normal = normal; self.smooth = smooth; self.slow = slow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ThemeAnimations.default
        fast = try container.decodeIfPresent(Double.self, forKey: .fast) ?? fallback.fast
        normal = try container.decodeIfPresent(Double.self, forKey: .normal) ?? fallback.normal
        smooth = try container.decodeIfPresent(Double.self, forKey: .smooth) ?? fallback.smooth
        slow = try container.decodeIfPresent(Double.self, forKey: .slow) ?? fallback.slow
    }
}
