//
//  SQLCodePreview.swift
//  TablePro
//
//  Simple read-only SQL code preview using native NSTextView
//

import AppKit
import SwiftUI

/// Read-only SQL code preview with line numbers
struct SQLCodePreview: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        // Create text storage and layout manager
        let textStorage = NSTextStorage(string: "")
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer()

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        // Create text view - structural setup only
        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]

        // Configure text container for proper scrolling
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false

        // Create scroll view
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            // Update text if changed
            if textView.string != text {
                textView.string = text
            }
            // Update appearance
            textView.textColor = NSColor.textColor
            textView.backgroundColor = NSColor.textBackgroundColor
            nsView.backgroundColor = NSColor.textBackgroundColor
        }
    }
}
