//
//  DataGridCellView.swift
//  TablePro
//

import AppKit

/// Custom cell view that draws change-state backgrounds via `draw(_:)` instead
/// of `layer.backgroundColor`. AppKit's `NSTableRowView` sets `backgroundStyle`
/// to `.emphasized` when the row is selected — we skip the custom background in
/// that case so the native selection highlight shows through.
final class DataGridCellView: NSTableCellView {
    var changeBackgroundColor: NSColor?

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        if backgroundStyle != .emphasized, let color = changeBackgroundColor {
            color.setFill()
            dirtyRect.fill()
        }
        super.draw(dirtyRect)
    }
}
