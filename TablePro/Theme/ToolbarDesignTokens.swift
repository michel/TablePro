//
//  ToolbarDesignTokens.swift
//  TablePro
//
//  Component-specific design tokens for toolbar display.
//  Builds on DesignConstants.swift by referencing base values and adding toolbar-specific semantics.
//
//  ARCHITECTURE: DesignConstants (base) → ToolbarDesignTokens (component-specific)
//

import AppKit
import Foundation
import SwiftUI

/// Component-specific design tokens for toolbar components
/// References DesignConstants for shared values, defines only toolbar-specific semantics
enum ToolbarDesignTokens {
    // MARK: - Typography Hierarchy (Xcode-inspired)

    enum Typography {
        /// Database type label (11pt, regular, monospaced) - subtle
        static let databaseType = Font.system(
            size: DesignConstants.FontSize.small,
            weight: .regular,
            design: .monospaced
        )

        /// Database name (12pt, medium) - clean and readable
        static let databaseName = Font.system(
            size: DesignConstants.FontSize.medium,
            weight: .medium
        )

        /// Execution time (11pt, regular, monospaced)
        static let executionTime = Font.system(
            size: DesignConstants.FontSize.small,
            weight: .regular,
            design: .monospaced
        )

        /// Tag label (11pt, medium) - clean like Xcode breadcrumbs
        static let tagLabel = Font.system(
            size: DesignConstants.FontSize.small,
            weight: .medium
        )
    }

    // MARK: - Tag Styling

    enum Tag {
        /// Tag capsule background opacity
        static let backgroundOpacity: CGFloat = 0.2

        /// Tag horizontal padding (8pt)
        static let horizontalPadding = DesignConstants.Spacing.xs

        /// Tag vertical padding (4pt)
        static let verticalPadding = DesignConstants.Spacing.xxs
    }

    // MARK: - Colors (Xcode-inspired minimal)

    enum Colors {
        /// Secondary text color - references base constant
        static let secondaryText = DesignConstants.Colors.secondaryText

        /// Tertiary text color - system semantic color
        static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    }
}
