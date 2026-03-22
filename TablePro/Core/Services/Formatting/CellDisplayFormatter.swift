//
//  CellDisplayFormatter.swift
//  TablePro
//
//  Pure formatter that transforms raw cell values into display-ready strings.
//  Used by InMemoryRowProvider's display cache to compute values once per cell.
//

import Foundation

@MainActor
enum CellDisplayFormatter {
    static let maxDisplayLength = 10_000

    static func format(_ rawValue: String?, columnType: ColumnType?) -> String? {
        guard let value = rawValue, !value.isEmpty else { return rawValue }

        var displayValue = value

        if let columnType {
            if columnType.isDateType {
                if let formatted = DateFormattingService.shared.format(dateString: displayValue) {
                    displayValue = formatted
                }
            } else if BlobFormattingService.shared.requiresFormatting(columnType: columnType) {
                displayValue = BlobFormattingService.shared.formatIfNeeded(
                    displayValue, columnType: columnType, for: .grid
                )
            }
        }

        let nsDisplay = displayValue as NSString
        if nsDisplay.length > maxDisplayLength {
            displayValue = nsDisplay.substring(to: maxDisplayLength) + "..."
        }

        displayValue = displayValue.sanitizedForCellDisplay

        return displayValue
    }
}
