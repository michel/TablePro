//
//  NSApplication+WindowManagement.swift
//  TablePro
//
//  macOS 13-compatible window management helpers.
//

import AppKit

extension NSApplication {
    /// Close all windows whose identifier contains the given ID.
    /// This is a macOS 13-compatible replacement for SwiftUI's `dismissWindow(id:)` (macOS 14+).
    func closeWindows(withId id: String) {
        for window in windows where window.identifier?.rawValue.contains(id) == true {
            window.close()
        }
    }
}
