//
//  KeyEventHandler.swift
//  TablePro
//
//  Key event handler using NSViewRepresentable with a local event monitor.
//  Originally written as a macOS 13 workaround. Now that macOS 14+ is the minimum,
//  SwiftUI's onKeyPress is available and this could be migrated in a future refactor.
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

/// Key event handler using a local NSEvent monitor.
/// Legacy approach from macOS 13 era; SwiftUI's onKeyPress (macOS 14+) is now available.
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
