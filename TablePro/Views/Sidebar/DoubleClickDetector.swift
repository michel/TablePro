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
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                self?.handleMouseUp(event)
                return event
            }
        } else if window == nil, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        guard event.clickCount == 2,
              let eventWindow = event.window,
              eventWindow === window else { return }
        let locationInSelf = convert(event.locationInWindow, from: nil)
        if bounds.contains(locationInSelf) {
            onDoubleClick?()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var acceptsFirstResponder: Bool { false }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
