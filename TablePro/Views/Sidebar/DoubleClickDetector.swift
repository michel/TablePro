//
//  DoubleClickDetector.swift
//  TablePro
//
//  Transparent overlay that detects double-clicks on sidebar rows.
//  Used for preview tabs: single-click opens a preview tab, double-click opens a permanent tab.
//

import AppKit
import SwiftUI

struct DoubleClickDetector: NSViewRepresentable {
    var onDoubleClick: () -> Void

    func makeNSView(context: Context) -> SidebarDoubleClickView {
        let view = SidebarDoubleClickView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: SidebarDoubleClickView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }
}

final class SidebarDoubleClickView: NSView {
    var onDoubleClick: (() -> Void)?

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }

    override var acceptsFirstResponder: Bool { false }
}
