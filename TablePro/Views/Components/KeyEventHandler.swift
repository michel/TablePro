//
//  KeyEventHandler.swift
//  TablePro
//
//  macOS 13-compatible replacement for SwiftUI's onKeyPress (macOS 14+).
//  Uses NSViewRepresentable with a local event monitor.
//

import AppKit
import SwiftUI

/// Key codes used by KeyEventHandler
enum KeyEventCode {
    case `return`
    case upArrow
    case downArrow
    case other(UInt16)
}

/// macOS 13-compatible key event handler using a local NSEvent monitor.
/// Usage: `.background(KeyEventHandler { keyCode in ... })`
struct KeyEventHandler: NSViewRepresentable {
    let handler: (KeyEventCode) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = KeyEventNSView()
        view.handler = handler
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyEventNSView)?.handler = handler
    }
}

private class KeyEventNSView: NSView {
    var handler: ((KeyEventCode) -> Bool)?

    override var acceptsFirstResponder: Bool { false }

    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.window?.isKeyWindow == true else { return event }

                let code: KeyEventCode
                switch event.keyCode {
                case 36: code = .return
                case 126: code = .upArrow
                case 125: code = .downArrow
                default: code = .other(event.keyCode)
                }

                if self.handler?(code) == true {
                    return nil // consumed
                }
                return event
            }
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
