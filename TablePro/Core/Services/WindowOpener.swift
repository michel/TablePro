//
//  WindowOpener.swift
//  TablePro
//
//  Bridges SwiftUI's openWindow environment action to imperative code.
//  Stored by ContentView on appear so MainContentCommandActions can open native tabs.
//

import os
import SwiftUI

@MainActor
internal final class WindowOpener {
    private static let logger = Logger(subsystem: "com.TablePro", category: "WindowOpener")

    internal static let shared = WindowOpener()

    /// Set by ContentView when it appears. Safe to store — OpenWindowAction is app-scoped, not view-scoped.
    internal var openWindow: OpenWindowAction?

    /// Opens a new native window tab with the given payload.
    /// If tabbingMode is .preferred, macOS automatically adds it to the current tab group.
    internal func openNativeTab(_ payload: EditorTabPayload) {
        guard let openWindow else {
            Self.logger.warning("openNativeTab called before openWindow was set — payload dropped")
            return
        }
        print("[openNativeTab] CREATING WINDOW — type=\(payload.tabType) table=\(payload.tableName ?? "nil") db=\(payload.databaseName ?? "nil") connId=\(payload.connectionId.uuidString.prefix(8))")
        print("[openNativeTab] CALL STACK:\n\(Thread.callStackSymbols.prefix(10).joined(separator: "\n"))")
        openWindow(id: "main", value: payload)
    }
}
