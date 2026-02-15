//
//  NSApplication+WindowManagement.swift
//  TablePro
//
//  Window management helpers.
//  Note: Now that macOS 14 is the minimum, SwiftUI's dismissWindow(id:) is available.
//  This extension could be replaced with the native API in a future refactor.
//

import AppKit

extension NSApplication {
    /// Close all windows whose identifier contains the given ID.
    /// Legacy workaround from when the minimum was macOS 13. Now that macOS 14+ is the minimum,
    /// callers could use SwiftUI's `dismissWindow(id:)` instead.
    func closeWindows(withId id: String) {
        for window in windows where window.identifier?.rawValue.contains(id) == true {
            window.close()
        }
    }
}
