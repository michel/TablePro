//
//  WindowOpener.swift
//  TablePro
//
//  Bridges SwiftUI's openWindow environment action to imperative code.
//  Stored by ContentView on appear so MainContentCommandActions can open native tabs.
//

import SwiftUI

@MainActor
final class WindowOpener {
    static let shared = WindowOpener()

    /// Set by ContentView when it appears. Safe to store — OpenWindowAction is app-scoped, not view-scoped.
    var openWindow: OpenWindowAction?

    /// Opens a new native window tab with the given payload.
    /// If tabbingMode is .preferred, macOS automatically adds it to the current tab group.
    func openNativeTab(_ payload: EditorTabPayload) {
        openWindow?(id: "main", value: payload)
    }
}
